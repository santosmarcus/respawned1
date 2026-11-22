// Pet Surrender withdrawal (CommunityAdoptionRequestRepository.
// withdrawSurrender), inquiries on surrenders listed for Community Adoption,
// and vehicle-capacity checks on transport offers
// (TransportAssignmentRepository.createAssignmentOffer).
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { createEnv, seed } from './setup.js';

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

const surrender = (extra = {}) => ({
  reporterId: 'reporter', organizationId: '', rescueType: 'Pet Surrender',
  status: 'community_adoption', orgInvolvement: 'not_org_facilitated', ...extra,
});
const withdrawal = (reason = 'keeping') => ({
  status: 'withdrawn',
  surrenderWithdrawal: { reason, previousStatus: 'community_adoption', withdrawnBy: 'reporter' },
});

describe('surrender withdrawal', () => {
  test('the reporter withdraws an active surrender with a reason, once', async () => {
    await admin((db) => db.doc('cases/s1').set(surrender()));
    await assertFails(as('stranger').doc('cases/s1').update(withdrawal()));
    await assertFails(as('reporter').doc('cases/s1').update({ status: 'withdrawn' }));
    await assertFails(as('reporter').doc('cases/s1').update(withdrawal('')));
    await assertSucceeds(as('reporter').doc('cases/s1').update(withdrawal()));
    // No second withdrawal, no reopening; the reporter still reads it.
    await assertFails(as('reporter').doc('cases/s1').update(withdrawal('other')));
    await assertFails(as('reporter').doc('cases/s1').update({ status: 'community_adoption' }));
    await assertSucceeds(as('reporter').doc('cases/s1').get());
  });

  test('an older pending surrender can be withdrawn too', async () => {
    await admin((db) => db.doc('cases/s2').set(surrender({ status: 'pending' })));
    await assertSucceeds(as('reporter').doc('cases/s2').update(withdrawal()));
  });

  test('only surrenders, and a reporter cannot list a case for Community Adoption', async () => {
    await admin((db) => db.doc('cases/r1').set(surrender({ rescueType: 'Injury', status: 'pending' })));
    await assertFails(as('reporter').doc('cases/r1').update(withdrawal()));
    await assertFails(as('reporter').doc('cases/r1').update({ status: 'community_adoption' }));
    await admin((db) => db.doc('cases/s3').set(surrender({ status: 'pending' })));
    await assertFails(as('reporter').doc('cases/s3').update({ status: 'community_adoption' }));
  });

  test('other reporter edits on a listed surrender still work', async () => {
    await admin((db) => db.doc('cases/s4').set(surrender()));
    await assertSucceeds(as('reporter').doc('cases/s4').update({ description: 'Friendly, house trained' }));
  });
});

describe('community adoption inquiries on surrenders', () => {
  const request = (caseId) => as('adopter').collection('communityAdoptionRequests').doc(`q_${caseId}`).set({
    caseId, listerId: 'reporter', adopterId: 'adopter', status: 'pending', animalIndexes: [0],
  });

  test('a listed surrender takes inquiries; a withdrawn one does not', async () => {
    await admin(async (db) => {
      await db.doc('cases/s5').set(surrender());
      await db.doc('cases/s6').set(surrender({ status: 'withdrawn' }));
      await db.doc('cases/s7').set(surrender({ rescueType: 'Injury' }));
    });
    await assertSucceeds(request('s5'));
    await assertFails(request('s6'));
    // community_adoption only lists surrenders.
    await assertFails(request('s7'));
  });

  test('a listed surrender is publicly readable as a case', async () => {
    await admin((db) => db.doc('cases/s8').set(surrender()));
    await assertSucceeds(as('adopter').doc('cases/s8').get());
  });
});

describe('transport offers and vehicle capacity', () => {
  const vehicle = (vehicleType, maxAnimals) => admin((db) => db.doc('users/rider').update({
    transporterVerification: maxAnimals === undefined ? { vehicleType } : { vehicleType, maxAnimals },
  }));
  const animals = (n) => admin((db) => db.doc('cases/trip').set({
    reporterId: 'reporter', organizationId: 'orgA', status: 'accepted_pending_clinic',
    animals: Array.from({ length: n }, () => ({ species: 'Dog' })),
  }));
  // A new document each time: these are creates (createAssignmentOffer).
  let n = 0;
  const offer = (extra = {}) => as('staffA').doc(`cases/trip/transportAssignments/o${++n}`).set({
    riderId: 'rider', status: 'pending', caseId: 'trip', organizationId: 'orgA', ...extra,
  });

  test('a motorcycle takes one animal, never two', async () => {
    await vehicle('Motorcycle', 3);
    await animals(1);
    await assertSucceeds(offer());
    await animals(2);
    await assertFails(offer());
  });

  test('a declared capacity covers the trip; an undeclared one counts as one', async () => {
    await vehicle('Sedan', 3);
    await animals(3);
    await assertSucceeds(offer());
    await animals(4);
    await assertFails(offer());
    await vehicle('SUV');
    await animals(2);
    await assertFails(offer());
    await animals(1);
    await assertSucceeds(offer());
  });

  test('no registered vehicle, no offer; demo offers skip the check', async () => {
    await animals(1);
    await assertFails(offer());
    await animals(5);
    await assertSucceeds(offer({ isDemo: true }));
  });
});

describe('transporter vehicle details', () => {
  const setVehicle = (data) => as('rider').doc('users/rider').set({ transporterVerification: data }, { merge: true });

  test('an approved transporter declares a missing capacity once, then cannot raise it', async () => {
    await admin((db) => db.doc('users/rider').update({ transporterVerification: { vehicleType: 'Sedan' } }));
    await assertFails(setVehicle({ maxAnimals: 0 }));
    await assertFails(setVehicle({ maxAnimals: 21 }));
    await assertSucceeds(setVehicle({ maxAnimals: 2 }));
    await assertFails(setVehicle({ maxAnimals: 6 }));
    await assertFails(setVehicle({ vehicleType: 'Cargo Van/L300' }));
  });

  test('a resubmission for review may change the vehicle', async () => {
    await admin((db) => db.doc('users/rider').update({ transporterVerification: { vehicleType: 'Sedan', maxAnimals: 2 } }));
    await assertSucceeds(as('rider').doc('users/rider').set({
      transporterVerification: { vehicleType: 'Cargo Van/L300', maxAnimals: 6, status: 'pending' },
      transporterVerificationStatus: 'pending',
    }, { merge: true }));
  });
});
