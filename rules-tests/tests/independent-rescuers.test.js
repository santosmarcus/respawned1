// Independent rescuers (organizations/{id}.kind == 'independent'):
// modules capped for everyone in them, the shelters' head start on new
// reports, first accept wins, protected limits and counters, the team cap,
// and the private home pin.
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { Timestamp, arrayUnion, serverTimestamp } from 'firebase/firestore';
import { createEnv, seed } from './setup.js';

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();
const minutesFromNow = (m) => Timestamp.fromMillis(Date.now() + m * 60 * 1000);

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // orgI: an approved independent rescuer (owner indOwner, Staff indStaff).
    await db.doc('users/indOwner').set({ role: 'organization', organizationId: 'orgI' });
    await db.doc('users/indStaff').set({ role: 'organization_member', organizationId: 'orgI' });
    await db.doc('users/otherInd').set({ role: 'organization', organizationId: 'orgJ' });
    await db.doc('organizations/orgI').set({
      ownerId: 'indOwner', name: 'Ana Rescue', kind: 'independent', verificationStatus: 'approved',
      memberCount: 2, activeCaseCount: 0, animalsInCareCount: 0,
    });
    await db.doc('organizations/orgI/members/indOwner').set({ role: 'admin', status: 'active' });
    await db.doc('organizations/orgI/members/indStaff').set({ role: 'staff', status: 'active' });
    await db.doc('organizations/orgI/settings/home').set({ name: 'Home', lat: 14.6, lng: 121.0 });
    await db.doc('organizations/orgJ').set({
      ownerId: 'otherInd', name: 'Ben Rescue', kind: 'independent', verificationStatus: 'approved',
    });
    await db.doc('organizations/orgJ/members/otherInd').set({ role: 'admin', status: 'active' });

    // Reports: one still in the shelters' head start, one opened to orgI,
    // one opened to someone else, and one owned by orgI.
    await db.doc('cases/headStart').set({
      reporterId: 'reporter', status: 'pending', organizationId: '',
      nearbyIndependentIds: ['orgI'], independentsOpenAt: minutesFromNow(10), independentsNotified: false,
    });
    await db.doc('cases/openToI').set({
      reporterId: 'reporter', status: 'pending', organizationId: '',
      nearbyIndependentIds: ['orgI'], independentsOpenAt: minutesFromNow(-1), independentsNotified: true,
    });
    await db.doc('cases/openToJ').set({
      reporterId: 'reporter', status: 'pending', organizationId: '',
      nearbyIndependentIds: ['orgJ'], independentsOpenAt: minutesFromNow(-1),
    });
    await db.doc('cases/ownedI').set({ reporterId: 'reporter', status: 'accepted_pending_clinic', organizationId: 'orgI' });
    await db.doc('animals/animalI').set({ name: 'Kiko', organizationId: 'orgI' });
    await db.doc('donations/dI').set({ userId: 'adopter', organizationId: 'orgI', amount: 100 });
  });
});

const accept = (uid, caseId, orgId) => as(uid).doc(`cases/${caseId}`).update({
  organizationId: orgId,
  status: 'accepted_pending_clinic',
  statusHistory: arrayUnion({ status: 'Accepted', timestamp: Timestamp.now() }),
});

describe('modules', () => {
  test('rescue, animal records and care work; money and other modules are closed, owner included', async () => {
    await assertSucceeds(as('indOwner').doc('cases/ownedI').get());
    await assertSucceeds(as('indStaff').doc('animals/animalI').update({ name: 'Kiko B' }));
    await assertSucceeds(as('indOwner').doc('animals/animalI').get());
    // Donations need financeView, which independents never have.
    await assertFails(as('indOwner').doc('donations/dI').get());
    // Events need the volunteers permission.
    await assertFails(as('indOwner').doc('events/evI').set({ organizationId: 'orgI', title: 'Drive', goingCount: 0 }));
  });

  test('adoptions stay read-only until a system admin turns them on', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('adoptions/adI').set({ organizationId: 'orgI', status: 'pending',
        personal: { adopterId: 'adopter', animalRecordId: 'animalI' } });
    });
    await assertFails(as('indOwner').doc('adoptions/adI').update({ note: 'called' }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('organizations/orgI').update({ enabledPermissions: ['rescue', 'animals', 'care', 'adoptions'] });
    });
    await assertSucceeds(as('indOwner').doc('adoptions/adI').update({ note: 'called' }));
    await assertSucceeds(as('indStaff').doc('adoptions/adI').update({ note: 'again' }));
  });
});

describe('getting cases', () => {
  test('shelters see and accept a new report during the head start; the independent can\'t accept yet', async () => {
    await assertSucceeds(as('staffA').doc('cases/headStart').get());
    await assertFails(accept('indOwner', 'headStart', 'orgI'));
    await assertSucceeds(accept('staffA', 'headStart', 'orgA'));
  });

  test('once open, the independent it opened to lists and accepts it; others can\'t', async () => {
    const mine = await assertSucceeds(as('indOwner').collection('cases')
      .where('organizationId', '==', '').where('nearbyIndependentIds', 'array-contains', 'orgI').get());
    const ids = mine.docs.map((d) => d.id).sort();
    if (!ids.includes('openToI') || ids.includes('openToJ')) throw new Error(`unexpected ${ids}`);
    // The whole unowned pool is shelters' only.
    await assertFails(as('indOwner').collection('cases').where('organizationId', '==', '').get());
    await assertFails(as('indOwner').doc('cases/openToJ').get());
    await assertFails(accept('indOwner', 'openToJ', 'orgI'));
    await assertSucceeds(accept('indOwner', 'openToI', 'orgI'));
  });

  test('first accept wins: nobody re-stamps a case another organization owns', async () => {
    await assertSucceeds(accept('staffA', 'openToI', 'orgA'));
    await assertFails(accept('indOwner', 'openToI', 'orgI'));
    await assertFails(accept('staffB', 'ownedA', 'orgB'));
  });

  test('a case referred to the independent is theirs to accept', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('cases/ownedA').update({ status: 'referred', referredToOrgId: 'orgI' });
    });
    await assertSucceeds(as('indOwner').doc('cases/ownedA').get());
    await assertSucceeds(as('indOwner').doc('cases/ownedA').update({
      organizationId: 'orgI', status: 'pending', ownerKind: 'independent',
    }));
  });
});

describe('limits, team and home', () => {
  test('nobody changes the kind, modules, caps or counters from the app', async () => {
    for (const field of [
      { kind: 'shelter' }, { enabledPermissions: ['rescue', 'campaigns'] }, { maxActiveCases: 50 },
      { activeCaseCount: 9 }, { memberCount: 1 }, { memberCap: 10 },
    ]) {
      await assertFails(as('indOwner').doc('organizations/orgI').update(field));
      await assertFails(as('admin').doc('organizations/orgI').update(field));
    }
    // Pausing is the rescuer's own call.
    await assertSucceeds(as('indOwner').doc('organizations/orgI').update({ acceptingCases: false }));
  });

  test('signing up: an independent draft, never with limits or counters', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/newInd').set({ role: 'organization', signupKind: 'independent' });
    });
    await assertSucceeds(as('newInd').doc('organizations/orgNew').set({
      ownerId: 'newInd', name: 'New', kind: 'independent', verificationStatus: 'draft', createdAt: serverTimestamp(),
    }));
    await assertFails(as('newInd').doc('organizations/orgNew2').set({
      ownerId: 'newInd', name: 'New', kind: 'independent', verificationStatus: 'draft', maxActiveCases: 99,
    }));
    await assertFails(as('newInd').doc('organizations/orgNew3').set({
      ownerId: 'newInd', name: 'New', kind: 'something', verificationStatus: 'draft',
    }));
  });

  test('a full team can\'t invite more people', async () => {
    const invite = (id) => as('indOwner').doc(`organizationInvitations/${id}`).set({
      organizationId: 'orgI', email: 'x@example.com', normalizedEmail: 'x@example.com', status: 'pending', role: 'staff',
    });
    await assertSucceeds(invite('orgI_x@example.com'));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('organizations/orgI').update({ memberCount: 5 });
    });
    await assertFails(invite('orgI_y@example.com'));
  });

  test('the home pin is the team\'s only', async () => {
    await assertSucceeds(as('indOwner').doc('organizations/orgI/settings/home').get());
    await assertSucceeds(as('indStaff').doc('organizations/orgI/settings/home').get());
    for (const uid of ['staffA', 'reporter', 'rider', 'otherInd']) {
      await assertFails(as(uid).doc('organizations/orgI/settings/home').get());
    }
  });
});
