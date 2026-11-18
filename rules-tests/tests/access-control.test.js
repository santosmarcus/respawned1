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

  test('the full record and every subcollection are staff-only', async () => {
    // Everyone else reads publicAnimals (see firestore.test.js).
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('animals/hiddenA/managementLogs/l1').set({ action: 'updated', organizationId: 'orgA' }));
    await assertFails(as('stranger').doc('animals/hiddenA').get());
    await assertSucceeds(as('staffA').doc('animals/hiddenA').get());
    for (const path of ['animals/hiddenA/gallery/g1', 'animals/hiddenA/managementLogs/l1']) {
      await assertFails(as('stranger').doc(path).get());
      await assertFails(as('staffB').doc(path).get());
      await assertSucceeds(as('staffA').doc(path).get());
      await assertSucceeds(as('carerA').doc(path).get());
    }
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

  test("staff read their own organization's donation records only", async () => {
    await assertSucceeds(as('staffA').doc('donations/manual').get());
    await assertSucceeds(as('staffA').collection('donations')
      .where('organizationId', '==', 'orgA').orderBy('createdAt', 'desc').limit(10).get());
    // Platform admins see no money: only the organization's own people do.
    await assertFails(as('admin').collection('donations').where('campaignId', '==', 'c1').get());
    await assertFails(as('staffB').doc('donations/manual').get());
    await assertFails(as('staffA').collection('donations').orderBy('createdAt', 'desc').limit(10).get());
    await assertFails(as('staffB').collection('donations').where('organizationId', '==', 'orgA').get());
  });
});

describe('case expenses', () => {
  const expense = { title: 'X-ray', amount: 800, receiptUrl: 'https://example.com/r.jpg' };

  test("only people who manage the owning org's money write them", async () => {
    await assertSucceeds(as('ownerA').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('admin').collection('cases/ownedA/expenses').add(expense));
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

describe('dashboard records across animals and cases', () => {
  const animalGroups = ['vaccinations', 'careRecords', 'medications', 'medicationDoses'];

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/animalB').set({ name: 'B', organizationId: 'orgB' });
      for (const g of animalGroups) {
        await db.doc(`animals/animalA/${g}/a1`).set({ organizationId: 'orgA', active: true });
        await db.doc(`animals/animalB/${g}/b1`).set({ organizationId: 'orgB', active: true });
      }
      await db.doc('cases/ownedA/expenses/x1').set({ organizationId: 'orgA', amount: 100 });
    });
  });

  test("staff and carers list their own organization's animal records", async () => {
    for (const g of animalGroups) {
      await assertSucceeds(as('staffA').collectionGroup(g).where('organizationId', '==', 'orgA').get());
      await assertSucceeds(as('carerA').collectionGroup(g).where('organizationId', '==', 'orgA').get());
      await assertSucceeds(as('admin').collectionGroup(g).get());
      await assertFails(as('staffA').collectionGroup(g).get());
      await assertFails(as('staffA').collectionGroup(g).where('organizationId', '==', 'orgB').get());
      // The collection-group match also covers direct reads.
      await assertFails(as('staffA').doc(`animals/animalB/${g}/b1`).get());
    }
  });

  test('case expenses: own organization staff, not carers', async () => {
    await assertSucceeds(as('staffA').collectionGroup('expenses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('carerA').collectionGroup('expenses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffB').collectionGroup('expenses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffA').collectionGroup('expenses').get());
  });
});

describe('PayMongo payment attempts', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('donationPayments/pA').set({ donorId: 'adopter', campaignId: 'c1', organizationId: 'orgA', status: 'needs_review', createdAt: 1 });
      await db.doc('donationPayments/pD').set({ donorId: 'stranger', campaignId: 'c9', organizationId: 'orgD', status: 'paid', createdAt: 2 });
      await db.doc('donationPayments/legacy').set({ donorId: 'stranger', campaignId: 'c1', status: 'paid', createdAt: 3 });
    });
  });

  test("an organization's financial admins list only its own attempts", async () => {
    await assertSucceeds(as('ownerA').collection('donationPayments').where('organizationId', '==', 'orgA').get());
    await assertSucceeds(as('ownerA').doc('donationPayments/pA').get());
    await assertFails(as('ownerA').collection('donationPayments').get());
    await assertFails(as('ownerA').collection('donationPayments').where('organizationId', '==', 'orgD').get());
    await assertFails(as('ownerA').doc('donationPayments/pD').get());
    // Older attempts with no organizationId wait for the backfill.
    await assertFails(as('ownerA').doc('donationPayments/legacy').get());
    // Another organization's Admin can't read orgA's.
    await assertFails(as('draftOwner').doc('donationPayments/pA').get());
  });

  test('non-admin staff and carers cannot read them', async () => {
    await assertFails(as('staffA').collection('donationPayments').where('organizationId', '==', 'orgA').get());
    await assertFails(as('carerA').doc('donationPayments/pA').get());
  });

  test('platform admins see none; donors read their own', async () => {
    await assertFails(as('admin').collection('donationPayments').get());
    await assertFails(as('admin').doc('donationPayments/pA').get());
    await assertSucceeds(as('adopter').doc('donationPayments/pA').get());
    await assertFails(as('adopter').doc('donationPayments/pD').get());
  });
});

describe('system admin console', () => {
  test('reads every profile, organization and member', async () => {
    await assertSucceeds(as('sysadmin').collection('users').get());
    await assertSucceeds(as('sysadmin').doc('users/rider').get());
    await assertSucceeds(as('sysadmin').collection('organizations').get());
    await assertSucceeds(as('sysadmin').collection('organizations/orgA/members').get());
  });

  test('cannot read cases, animals, adoptions or money', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/a1').set({ name: 'Bao', organizationId: 'orgA' });
      await db.doc('donations/d1').set({ userId: 'adopter', campaignId: 'c1', organizationId: 'orgA' });
      await db.doc('donationPayments/p1').set({ donorId: 'adopter', organizationId: 'orgA' });
      await db.doc('orgExpenses/x1').set({ organizationId: 'orgA', amount: 1 });
    });
    await assertFails(as('sysadmin').doc('cases/ownedA').get());
    await assertFails(as('sysadmin').doc('cases/pending1').get());
    await assertFails(as('sysadmin').doc('animals/a1').get());
    await assertFails(as('sysadmin').doc('donations/d1').get());
    await assertFails(as('sysadmin').doc('donationPayments/p1').get());
    await assertFails(as('sysadmin').doc('orgExpenses/x1').get());
    await assertFails(as('sysadmin').collection('adoptions').get());
  });

  test('cannot change profiles or approve organizations directly', async () => {
    await assertFails(as('sysadmin').doc('users/rider').update({ name: 'Changed' }));
    await assertFails(as('sysadmin').doc('users/rider').update({ role: 'general' }));
    await assertFails(as('sysadmin').doc('organizations/orgD').update({ verificationStatus: 'approved' }));
  });

  test('reviews volunteer and transporter applications', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('volunteerApplications/stranger').set({ uid: 'stranger', status: 'pending' });
      await db.doc('transporterApplications/rider').set({ uid: 'rider', status: 'pending' });
    });
    const review = (status) => ({ status, reviewedBy: 'sysadmin', reviewedAt: new Date() });

    await assertSucceeds(as('sysadmin').collection('volunteerApplications').where('status', '==', 'pending').get());
    await assertSucceeds(as('sysadmin').doc('volunteerApplications/stranger').update(review('approved')));
    await assertFails(as('sysadmin').doc('volunteerApplications/stranger').update({ status: 'approved', reviewedBy: 'someoneElse' }));

    await assertSucceeds(as('sysadmin').collection('transporterApplications').where('status', '==', 'pending').get());
    await assertSucceeds(as('sysadmin').doc('transporterApplications/rider').update(review('approved')));
    // Verifying the transporter's account: only the two verification fields.
    await assertSucceeds(as('sysadmin').doc('users/rider').update({ transporterVerificationStatus: 'approved', isVerified: true }));
    await assertFails(as('sysadmin').doc('users/rider').update({ transporterVerificationStatus: 'approved', isVerified: false }));
    // Only an account that applied.
    await assertFails(as('sysadmin').doc('users/rider2').update({ transporterVerificationStatus: 'approved', isVerified: true }));
  });

  test('nobody can give themselves the role', async () => {
    await assertFails(as('newcomer').doc('users/newcomer').set({ role: 'system_admin' }));
    await assertFails(as('stranger').doc('users/stranger').update({ role: 'system_admin' }));
  });
});

describe('referral share links', () => {
  test('no client reads or writes them, staff and platform admins included', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('referralShares/abcdefghijklmnopqrstuvwx').set({ caseId: 'ownedA', organizationId: 'orgA' }));
    for (const uid of ['staffA', 'ownerA', 'admin', 'sysadmin', 'reporter', 'stranger']) {
      await assertFails(as(uid).doc('referralShares/abcdefghijklmnopqrstuvwx').get());
      await assertFails(as(uid).collection('referralShares').get());
      await assertFails(as(uid).doc('referralShares/zzzzzzzzzzzzzzzzzzzzzzzz').set({ caseId: 'ownedA' }));
      await assertFails(as(uid).doc('referralShares/abcdefghijklmnopqrstuvwx/responses/r1').set({ response: 'will_handle' }));
    }
  });
});
