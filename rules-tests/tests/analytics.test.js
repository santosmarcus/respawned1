// Module analytics: daily snapshots (snapshotDailyAnalytics) and the
// fields the app now writes for them: acceptedAt / rejectedAt on review,
// the referral reason, pickedUpAt / treatmentAcceptedAt in transit, and an
// expense's payment status.
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;
let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

test('daily snapshots: org staff read them, nobody writes them, the public never sees them', async () => {
  const path = 'organizations/orgA/analyticsSnapshots/2026-11-22';
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(path).set({ day: '2026-11-22', inTreatment: 3 }));
  await assertSucceeds(as('staffA').doc(path).get());
  await assertSucceeds(as('staffA').collection('organizations/orgA/analyticsSnapshots').orderBy('day', 'desc').limit(30).get());
  await assertFails(as('staffB').doc(path).get());
  await assertFails(as('reporter').doc(path).get());
  await assertFails(env.unauthenticatedContext().firestore().doc(path).get());
  await assertFails(as('ownerA').doc(path).set({ day: '2026-11-22', inTreatment: 0 }));
  await assertFails(as('ownerA').doc(path).delete());
});

test('staff stamp acceptedAt and the referral reason; a transporter stamps pickup and clinic times', async () => {
  await assertSucceeds(as('staffA').doc('cases/ownedA').update({ acceptedAt: FieldValue.serverTimestamp() }));
  await assertSucceeds(as('staffA').doc('cases/ownedA').update({
    referral: { referralReason: 'shelterAtCapacity', type: 'anotherOrganization' },
  }));
  await assertSucceeds(as('rider').doc('cases/assigned').update({
    status: 'treatment', pickedUpAt: FieldValue.serverTimestamp(),
  }));
  await assertSucceeds(as('rider').doc('cases/assigned').update({ treatmentAcceptedAt: FieldValue.serverTimestamp() }));
});

test('an expense can be saved as a running bill and later marked paid', async () => {
  await assertSucceeds(as('treasurerA').doc('cases/ownedA/expenses/e2').set({ amount: 900, paymentStatus: 'unpaid', paidAt: null }));
  await assertSucceeds(as('treasurerA').doc('cases/ownedA/expenses/e2').update({ paymentStatus: 'paid', paidAt: FieldValue.serverTimestamp() }));
});
