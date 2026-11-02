// Firestore stops evaluating a request after 1,000 expressions and denies
// it. These are legitimate writes from the users who go furthest down the
// cases/{caseId} update rule (non-staff, so every earlier branch runs);
// each must still be allowed, which proves it fits the budget.
import { after, before, beforeEach, test } from 'node:test';
import { assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

test('community adoption claim by an outsider fits the budget', async () => {
  await assertSucceeds(as('stranger').doc('cases/ownedA').update({
    communityAdoptionIds: FieldValue.arrayUnion('ca1'),
    claimedAnimalIndexes: [0],
    status: 'closed',
    statusHistory: FieldValue.arrayUnion({ status: 'claimed' }),
  }));
});

test('a transporter registering adoption interest fits the budget', async () => {
  // Runs the whole transporter branch (incl. the offer lookup) first.
  await assertSucceeds(as('rider2').doc('cases/offered').update({
    willingAdopterId: 'rider2', willingAdopterName: 'R2', willingAdopterType: 'adopt',
    statusHistory: FieldValue.arrayUnion({ status: 'interest' }),
  }));
});

test("another organization's staff claiming a community adoption fits the budget", async () => {
  // Runs the whole staff branch (membership + approval lookups) first.
  await assertSucceeds(as('staffB').doc('cases/ownedA').update({
    communityAdoptionIds: FieldValue.arrayUnion('ca2'),
    claimedAnimalIndexes: [0],
    statusHistory: FieldValue.arrayUnion({ status: 'claimed' }),
  }));
});

test('clearing a stale offer pointer from a viewer fits the budget', async () => {
  await assertSucceeds(as('stranger').doc('cases/offered').update({ currentAssignmentId: FieldValue.delete() }));
});
