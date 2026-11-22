// Adoption release and unreserve as the admin app writes them
// (AdoptionApplicationRepository.releaseWithFollowUps / unreserve).
// The release is one atomic write: the animal, the application, one
// followUps doc per scheduled date and a managementLogs entry. Every doc
// re-runs the staff checks, so a long schedule must still fit Firestore's
// per-request limits.
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('adoptions/appA').update({ status: 'approved' });
    await db.doc('animals/animalA').update({
      adoptionStatus: 'reserved', reservedApplicationId: 'appA', reservedForUserId: 'adopter',
    });
  });
});

const releaseBatch = (db, followUpCount) => {
  const batch = db.batch();
  batch.update(db.doc('animals/animalA'), {
    adoptionStatus: 'adopted', status: 'adopted', adoptedByUserId: 'adopter', adoptedApplicationId: 'appA',
    adoptedAt: FieldValue.serverTimestamp(),
    reservedApplicationId: FieldValue.delete(), reservedForUserId: FieldValue.delete(), reservedAt: FieldValue.delete(),
  });
  batch.update(db.doc('adoptions/appA'), {
    status: 'adopted', releasedAt: FieldValue.serverTimestamp(), releasedBy: 'Staff A',
    deliveryAttempts: 0, rescheduleRequested: false, postAdoptionStatus: 'inProgress',
    followUpSchedules: [{ ruleId: 'r1', frequency: 'weekly' }], noFollowUpsPlanned: false,
    statusHistory: FieldValue.arrayUnion({ status: 'Released.' }),
  });
  for (let i = 0; i < followUpCount; i++) {
    batch.set(db.collection('adoptions/appA/followUps').doc(), { index: i, status: 'scheduled' });
  }
  batch.set(db.collection('animals/animalA/managementLogs').doc(), { action: 'Released', by: 'staffA' });
  return batch.commit();
};

test('a release with a year of weekly follow-ups is allowed', async () => {
  await assertSucceeds(releaseBatch(as('staffA'), 52));
});

const unreserveBatch = (db, adoptionStatus) => {
  const batch = db.batch();
  batch.update(db.doc('animals/animalA'), {
    adoptionStatus,
    reservedForUserId: FieldValue.delete(), reservedApplicationId: FieldValue.delete(), reservedAt: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.update(db.doc('adoptions/appA'), {
    reservedAt: FieldValue.delete(),
    statusHistory: FieldValue.arrayUnion({ status: 'Reservation cleared.' }),
  });
  return batch.commit();
};

test('unreserve returns a tagged animal to adoptable', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('animalTags/ABCD2345').set({ code: 'ABCD2345', animalId: 'animalA', organizationId: 'orgA', type: 'qr', active: true });
    await db.doc('animals/animalA').update({ qrTagId: 'ABCD2345' });
  });
  await assertSucceeds(unreserveBatch(as('staffA'), 'adoptable'));
});

// AdoptionApplicationRepository._statusAfterReservation: without a
// registered collar tag the animal goes back to not_ready instead.
test('unreserve of an untagged animal goes to not_ready, never adoptable', async () => {
  await assertFails(unreserveBatch(as('staffA'), 'adoptable'));
  await assertSucceeds(unreserveBatch(as('staffA'), 'not_ready'));
});
