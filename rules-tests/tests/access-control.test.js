// Medical records, donor records, case expenses and the Audit page's
// Rescue/Records tabs: who may read and write them.
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { createEnv, seed } from './setup.js';

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

describe('animal medical records', () => {
  const medical = ['medications', 'medicationDoses', 'vaccinations', 'careRecords', 'careUpdates', 'medicalEpisodes'];

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/hiddenA').set({ name: 'Bao', organizationId: 'orgA', publicProfileHidden: true });
      for (const sub of medical) await db.doc(`animals/hiddenA/${sub}/r1`).set({ note: 'private' });
      await db.doc('animals/hiddenA/gallery/g1').set({ url: 'x' });
    });
  });

  test("the owning org's staff, its carers and platform staff read them", async () => {
    for (const sub of medical) {
      await assertSucceeds(as('staffA').doc(`animals/hiddenA/${sub}/r1`).get());
      await assertSucceeds(as('carerA').doc(`animals/hiddenA/${sub}/r1`).get());
      await assertSucceeds(as('admin').doc(`animals/hiddenA/${sub}/r1`).get());
      await assertSucceeds(as('carerA').collection(`animals/hiddenA/${sub}`).get());
    }
  });

  test('other signed-in users cannot read them', async () => {
    for (const sub of medical) {
      await assertFails(as('stranger').doc(`animals/hiddenA/${sub}/r1`).get());
      await assertFails(as('adopter').collection(`animals/hiddenA/${sub}`).get());
      await assertFails(as('rider').doc(`animals/hiddenA/${sub}/r1`).get());
    }
  });

  test('the full record is staff-only; non-medical subcollections stay readable', async () => {
    // Everyone else reads publicAnimals (see firestore.test.js).
    await assertFails(as('stranger').doc('animals/hiddenA').get());
    await assertSucceeds(as('staffA').doc('animals/hiddenA').get());
    await assertSucceeds(as('stranger').doc('animals/hiddenA/gallery/g1').get());
  });
});

describe('donation records', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('donations/mine').set({ userId: 'adopter', type: 'sponsorship', campaignId: 'c1', donorName: 'Ada' });
      await db.doc('donations/manual').set({
        userId: null, type: 'donation', campaignId: 'c1', organizationId: 'orgA',
        donorName: 'Jane', notes: 'Paid at the shelter', receiptUrl: 'https://example.com/r.jpg',
      });
    });
  });

  test('donors read and query their own records', async () => {
    await assertSucceeds(as('adopter').doc('donations/mine').get());
    await assertSucceeds(as('adopter').collection('donations')
      .where('userId', '==', 'adopter').where('type', '==', 'sponsorship').get());
  });

  test('nobody else reads donor records, even by campaign or organization', async () => {
    await assertFails(as('stranger').doc('donations/mine').get());
    await assertFails(as('stranger').doc('donations/manual').get());
    await assertFails(as('stranger').collection('donations').where('campaignId', '==', 'c1').get());
    await assertFails(as('stranger').collection('donations').where('organizationId', '==', 'orgA').get());
    await assertFails(as('carerA').doc('donations/manual').get());
  });

  test('staff read donation records', async () => {
    await assertSucceeds(as('staffA').doc('donations/manual').get());
    await assertSucceeds(as('staffA').collection('donations').orderBy('createdAt', 'desc').limit(10).get());
    await assertSucceeds(as('admin').collection('donations').where('campaignId', '==', 'c1').get());
  });
});

describe('case expenses', () => {
  const expense = { title: 'X-ray', amount: 800, receiptUrl: 'https://example.com/r.jpg' };

  test("only the owning org's financial admins and platform admins write them", async () => {
    await assertSucceeds(as('ownerA').collection('cases/ownedA/expenses').add(expense));
    await assertSucceeds(as('admin').collection('cases/ownedA/expenses').add(expense));
    await assertSucceeds(as('ownerA').doc('cases/ownedA/expenses/e1').update({ amount: 600 }));
    await assertSucceeds(as('ownerA').doc('cases/ownedA/expenses/e1').delete());
  });

  test('regular staff, carers, other orgs and transporters cannot', async () => {
    await assertFails(as('staffA').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('staffA').doc('cases/ownedA/expenses/e1').update({ amount: 1 }));
    await assertFails(as('staffA').doc('cases/ownedA/expenses/e1').delete());
    await assertFails(as('carerA').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('staffB').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('rider').collection('cases/assigned/expenses').add(expense));
    await assertFails(as('reporter').collection('cases/ownedA/expenses').add(expense));
  });

  test('case staff read them; the transporter and reporter do not', async () => {
    await assertSucceeds(as('staffA').doc('cases/ownedA/expenses/e1').get());
    await assertFails(as('reporter').doc('cases/ownedA/expenses/e1').get());
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/assigned/expenses/e2').set(expense));
    await assertFails(as('rider').doc('cases/assigned/expenses/e2').get());
  });

  test('the transporter still writes other case records', async () => {
    await assertSucceeds(as('rider').doc('cases/assigned/treatmentLogs/t1').set({ note: 'Picked up' }));
  });
});

describe('audit Rescue and Records tabs', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const at = new Date();
      await db.doc('cases/ownedA/activityLogs/l1').set({ action: 'Accepted', organizationId: 'orgA', timestamp: at });
      await db.doc('cases/ownedB').set({ reporterId: 'reporter', status: 'accepted_pending_clinic', organizationId: 'orgB' });
      await db.doc('cases/ownedB/activityLogs/l2').set({ action: 'Accepted', organizationId: 'orgB', timestamp: at });
      await db.doc('animals/animalA/managementLogs/m1').set({ action: 'Edited', organizationId: 'orgA', timestamp: at });
    });
  });

  test("staff list their own organization's case and animal logs", async () => {
    for (const group of ['activityLogs', 'managementLogs']) {
      await assertSucceeds(as('staffA').collectionGroup(group)
        .where('organizationId', '==', 'orgA').orderBy('timestamp', 'desc').limit(30).get());
    }
  });

  test("they cannot list every organization's logs or another organization's", async () => {
    for (const group of ['activityLogs', 'managementLogs']) {
      await assertFails(as('staffA').collectionGroup(group).orderBy('timestamp', 'desc').limit(30).get());
      await assertFails(as('staffB').collectionGroup(group).where('organizationId', '==', 'orgA').get());
      await assertFails(as('carerA').collectionGroup(group).where('organizationId', '==', 'orgA').get());
      await assertFails(as('stranger').collectionGroup(group).where('organizationId', '==', 'orgA').get());
    }
  });

  test('platform staff list all of them', async () => {
    await assertSucceeds(as('admin').collectionGroup('activityLogs').orderBy('timestamp', 'desc').get());
    await assertSucceeds(as('admin').collectionGroup('managementLogs').orderBy('timestamp', 'desc').get());
  });

  test("a case's own activity feed is unchanged", async () => {
    await assertSucceeds(as('reporter').collection('cases/ownedA/activityLogs').get());
  });
});
