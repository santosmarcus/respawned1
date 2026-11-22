// Analytics data: adoption listing engagement counters
// (AnimalEngagementRepository) and the fields review, referral and transit
// now record for Reports by area (acceptedAt / rejectedAt, the referral
// reason, pickedUpAt / treatmentAcceptedAt).
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;
let env;
const as = (uid) => env.authenticatedContext(uid).firestore();
const day = '2026-11-22';
const counter = (uid) => as(uid).doc(`animals/animalA/engagement/${day}`);

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

test('anyone signed in adds exactly one view or save, stamped with the animal\'s organization', async () => {
  await assertFails(env.unauthenticatedContext().firestore().doc(`animals/animalA/engagement/${day}`)
    .set({ organizationId: 'orgA', day, views: 1 }));
  await assertFails(counter('adopter').set({ organizationId: 'orgB', day, views: 1 }));
  await assertFails(counter('adopter').set({ organizationId: 'orgA', day, views: 5 }));
  await assertFails(counter('adopter').set({ organizationId: 'orgA', day: '2026-11-21', views: 1 }));
  await assertFails(counter('adopter').set({ organizationId: 'orgA', day, views: 1, note: 'x' }));
  await assertSucceeds(counter('adopter').set({ organizationId: 'orgA', day, views: FieldValue.increment(1) }, { merge: true }));
  await assertSucceeds(counter('stranger').set({ organizationId: 'orgA', day, saves: FieldValue.increment(1) }, { merge: true }));
  await assertSucceeds(counter('reporter').set({ organizationId: 'orgA', day, views: FieldValue.increment(1) }, { merge: true }));
  // Not two at once, not a jump, not down, not the organization.
  await assertFails(counter('adopter').update({ views: 3, saves: 2 }));
  await assertFails(counter('adopter').update({ views: 10 }));
  await assertFails(counter('adopter').update({ views: 1 }));
  await assertFails(counter('adopter').update({ organizationId: 'orgB' }));
  await assertFails(counter('adopter').delete());
});

test('only the organization\'s staff read the counters', async () => {
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`animals/animalA/engagement/${day}`)
    .set({ organizationId: 'orgA', day, views: 4, saves: 1 }));
  await assertSucceeds(as('staffA').doc(`animals/animalA/engagement/${day}`).get());
  await assertSucceeds(as('staffA').collectionGroup('engagement').where('organizationId', '==', 'orgA').get());
  await assertFails(as('staffB').collectionGroup('engagement').where('organizationId', '==', 'orgA').get());
  await assertFails(as('adopter').doc(`animals/animalA/engagement/${day}`).get());
});

test('review, referral and transit times are recorded by the people doing them', async () => {
  await assertSucceeds(as('staffA').doc('cases/ownedA').update({ acceptedAt: FieldValue.serverTimestamp() }));
  await assertSucceeds(as('staffA').doc('cases/ownedA').update({
    referral: { referralReason: 'shelterAtCapacity', type: 'anotherOrganization' },
  }));
  await assertSucceeds(as('rider').doc('cases/assigned').update({ status: 'treatment', pickedUpAt: FieldValue.serverTimestamp() }));
  await assertSucceeds(as('rider').doc('cases/assigned').update({ treatmentAcceptedAt: FieldValue.serverTimestamp() }));
});

test('treatment spots are saved with the shelter settings by an admin only', async () => {
  await assertSucceeds(as('ownerA').doc('organizations/orgA/settings/shelter').set({ maxCapacity: 200, treatmentCapacity: 12 }, { merge: true }));
  await assertFails(as('staffA').doc('organizations/orgA/settings/shelter').set({ treatmentCapacity: 99 }, { merge: true }));
});
