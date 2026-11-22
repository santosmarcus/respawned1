// Admin + Staff permissions (firestore.rules staffWith, functions/org_access.js):
// what each preset may and may not do, the legacy fallbacks, and the
// members/invitations write rules that protect permissions.
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { createEnv, presets, seed } from './setup.js';

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();
const upload = (uid, path) => env.authenticatedContext(uid).storage().ref(path).put(new Uint8Array([1, 2, 3]));

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('donations/d1').set({ userId: 'adopter', campaignId: 'c1', organizationId: 'orgA', amount: 100 });
    await db.doc('donationPayments/p1').set({ donorId: 'adopter', organizationId: 'orgA', status: 'paid' });
    await db.doc('fundTransfers/t1').set({ organizationId: 'orgA', amount: 50 });
    await db.doc('orgExpenses/x1').set({ organizationId: 'orgA', amount: 10, category: 'staffCompensation' });
    await db.doc('campaigns/c1').set({ title: 'C1', organizationId: 'orgA' });
    await db.doc('campaigns/c1/history/h1').set({ action: 'created' });
    await db.doc('animals/a1').set({ name: 'Bao', organizationId: 'orgA' });
    await db.doc('animals/a1/vaccinations/v1').set({ name: 'Rabies', organizationId: 'orgA' });
    await db.doc('adoptions/ad1').set({ organizationId: 'orgA', personal: { adopterId: 'adopter' }, status: 'pending' });
    await db.doc('events/e1').set({ organizationId: 'orgA', title: 'Feeding', status: 'published', goingCount: 0 });
    await db.doc('auditLogs/l1').set({ organizationId: 'orgA', category: 'adoptions', action: 'x', actorId: 'ownerA' });
    await db.doc('volunteerApplications/rider').set({ uid: 'rider', status: 'pending' });
    await db.doc('organizations/orgA/settings/shelter').set({ maxCapacity: 20 });
    await db.doc('organizations/orgA/cashOuts/co1').set({ organizationId: 'orgA', amount: 500, status: 'needs_assignment' });
  });
});

describe('money', () => {
  test('donor records: finance viewers and Admins, nobody else', async () => {
    for (const uid of ['treasurerA', 'fullA', 'adminA', 'ownerA', 'platformMemberA']) {
      await assertSucceeds(as(uid).doc('donations/d1').get());
    }
    for (const uid of ['rescueA', 'careA', 'adoptA', 'noPermsA', 'inactiveAdminA', 'admin', 'staffB']) {
      await assertFails(as(uid).doc('donations/d1').get());
    }
  });

  test('payments, transfers, campaign history and general expenses', async () => {
    // Payments and running costs (staff pay): managing money only.
    for (const path of ['donationPayments/p1', 'orgExpenses/x1']) {
      await assertSucceeds(as('treasurerA').doc(path).get());
      await assertSucceeds(as('adminA').doc(path).get());
      await assertFails(as('fullA').doc(path).get());
      await assertFails(as('admin').doc(path).get());
    }
    // Transfers and campaign history: viewing is enough.
    for (const path of ['fundTransfers/t1', 'campaigns/c1/history/h1']) {
      await assertSucceeds(as('fullA').doc(path).get());
      await assertSucceeds(as('treasurerA').doc(path).get());
      await assertFails(as('rescueA').doc(path).get());
      await assertFails(as('admin').doc(path).get());
    }
  });

  test('general expenses: the treasurer records them, full staff cannot', async () => {
    const expense = { organizationId: 'orgA', amount: 25, category: 'utilities', status: 'approved',
      createdBy: 'treasurerA', approvedBy: 'ownerA' };
    await assertFails(as('fullA').collection('orgExpenses').add({ ...expense, createdBy: 'fullA' }));
  });

  test('case expenses: the treasurer writes, full staff and platform admins read only', async () => {
    const expense = { amount: 100, title: 'Vet' };
    await assertSucceeds(as('treasurerA').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('fullA').collection('cases/ownedA/expenses').add(expense));
    await assertFails(as('platformMemberA').collection('cases/pending1/expenses').add(expense));
    await assertSucceeds(as('fullA').doc('cases/ownedA/expenses/e1').get());
    await assertSucceeds(as('treasurerA').doc('cases/ownedA/expenses/e1').get());
    await assertFails(as('careA').doc('cases/ownedA/expenses/e1').get());
  });

  test('cash-outs: anyone who sees the money reads them, nobody writes from the app', async () => {
    for (const uid of ['treasurerA', 'fullA', 'adminA', 'ownerA']) {
      await assertSucceeds(as(uid).doc('organizations/orgA/cashOuts/co1').get());
    }
    for (const uid of ['rescueA', 'careA', 'adoptA', 'noPermsA', 'admin', 'staffB', 'adopter']) {
      await assertFails(as(uid).doc('organizations/orgA/cashOuts/co1').get());
    }
    for (const uid of ['treasurerA', 'adminA']) {
      await assertFails(as(uid).doc('organizations/orgA/cashOuts/co1').update({ status: 'assigned' }));
      await assertFails(as(uid).collection('organizations/orgA/cashOuts').add({ amount: 1, status: 'needs_assignment' }));
    }
  });

  test('the platform account gets money only through its membership', async () => {
    await assertSucceeds(as('platformMemberA').doc('donationPayments/p1').get());
    await assertFails(as('admin').doc('donationPayments/p1').get());
  });
});

describe('operations', () => {
  test('rescue cases: rescue staff work them, other Staff read only, carers not at all', async () => {
    await assertSucceeds(as('rescueA').doc('cases/ownedA').update({ note: 'x' }));
    await assertSucceeds(as('fullA').doc('cases/ownedA').update({ note: 'y' }));
    await assertFails(as('treasurerA').doc('cases/ownedA').update({ note: 'z' }));
    await assertFails(as('careA').doc('cases/ownedA').update({ note: 'z' }));
    // Every module is readable to Staff outside the care-tasks screen.
    await assertSucceeds(as('treasurerA').doc('cases/ownedA').get());
    await assertFails(as('careA').doc('cases/ownedA').get());
    await assertSucceeds(as('adoptA').doc('cases/ownedA').get());
    await assertSucceeds(as('rescueA').collection('cases').where('organizationId', '==', '').get());
    await assertFails(as('careA').collection('cases').where('organizationId', '==', '').get());
  });

  test('animals: records, rescue and adoption staff edit; care staff read their own', async () => {
    for (const uid of ['rescueA', 'adoptA', 'fullA']) {
      await assertSucceeds(as(uid).doc('animals/a1').update({ note: uid }));
    }
    await assertFails(as('careA').doc('animals/a1').update({ note: 'x' }));
    await assertFails(as('treasurerA').doc('animals/a1').update({ note: 'x' }));
    await assertSucceeds(as('careA').doc('animals/a1').get());
    await assertSucceeds(as('careA').doc('animals/a1/vaccinations/v1').get());
    // Analytics (insights) counts health records, so the treasurer may read them;
    // other organizations' staff may not.
    await assertFails(as('staffB').doc('animals/a1/vaccinations/v1').get());
    await assertSucceeds(as('treasurerA').doc('animals/a1').get());
    await assertSucceeds(as('treasurerA').doc('animals/a1/vaccinations/v1').get());
  });

  test('daily care: care staff record their own doses only', async () => {
    const dose = (by) => ({ givenBy: by, medicationId: 'm1' });
    await assertSucceeds(as('careA').doc('animals/a1/medicationDoses/d1').set(dose('careA')));
    await assertFails(as('careA').doc('animals/a1/medicationDoses/d2').set(dose('fullA')));
    await assertFails(as('treasurerA').doc('animals/a1/medicationDoses/d3').set(dose('treasurerA')));
    await assertSucceeds(as('careA').doc('organizations/orgA/stock/s1').set({ name: 'Food', quantity: 3 }));
    await assertFails(as('treasurerA').doc('organizations/orgA/stock/s1').set({ name: 'Food', quantity: 3 }));
  });

  test('adoptions: adoption staff work them, other Staff read only', async () => {
    await assertSucceeds(as('adoptA').doc('adoptions/ad1').get());
    await assertSucceeds(as('adoptA').doc('adoptions/ad1').update({ note: 'called' }));
    await assertSucceeds(as('rescueA').doc('adoptions/ad1').get());
    await assertFails(as('rescueA').doc('adoptions/ad1').update({ note: 'x' }));
    await assertFails(as('careA').doc('adoptions/ad1').get());
    await assertFails(as('treasurerA').doc('adoptions/ad1').update({ note: 'x' }));
  });

  test('volunteers, events and applications: volunteer staff manage, other Staff read', async () => {
    await assertSucceeds(as('fullA').doc('volunteerApplications/rider').get());
    await assertSucceeds(as('rescueA').doc('volunteerApplications/rider').get());
    await assertFails(as('careA').doc('volunteerApplications/rider').get());
    await assertFails(as('rescueA').doc('volunteerApplications/rider').update({ status: 'approved', reviewedBy: 'rescueA' }));
    await assertSucceeds(as('fullA').doc('events/e1').update({ title: 'Feeding day' }));
    await assertFails(as('careA').doc('events/e1').update({ title: 'x' }));
    await assertSucceeds(upload('fullA', 'events/orgA/cover.jpg'));
    await assertFails(upload('treasurerA', 'events/orgA/cover.jpg'));
  });

  test('audit log and analytics: every Staff member but carers reads them', async () => {
    await assertSucceeds(as('rescueA').doc('auditLogs/l1').get());
    await assertSucceeds(as('treasurerA').doc('auditLogs/l1').get());
    await assertSucceeds(as('adoptA').doc('auditLogs/l1').get());
    await assertFails(as('careA').doc('auditLogs/l1').get());
  });

  test('settings and the org profile: Admins write; care-only staff read only care setup', async () => {
    await assertSucceeds(as('adminA').doc('organizations/orgA/settings/shelter').set({ maxCapacity: 30 }));
    await assertFails(as('fullA').doc('organizations/orgA/settings/shelter').set({ maxCapacity: 30 }));
    await assertFails(as('platformMemberA').doc('organizations/orgB/settings/shelter').set({ maxCapacity: 1 }));
    await assertSucceeds(as('treasurerA').doc('organizations/orgA/settings/shelter').get());
    await assertFails(as('careA').doc('organizations/orgA/settings/shelter').get());
    await assertSucceeds(as('adminA').doc('organizations/orgA').update({ shelterName: 'Main' }));
    await assertFails(as('fullA').doc('organizations/orgA').update({ shelterName: 'Main' }));
  });
});

describe('fallbacks', () => {
  test('no permissions and inactive Admins get nothing', async () => {
    for (const uid of ['noPermsA', 'inactiveAdminA']) {
      await assertFails(as(uid).doc('cases/ownedA').get());
      await assertFails(as(uid).doc('animals/a1').get());
      await assertFails(as(uid).doc('donations/d1').get());
      await assertFails(as(uid).doc('organizations/orgA/settings/care').get());
    }
    await assertSucceeds(as('noPermsA').doc('users/noPermsA').get());
  });

  test('legacy staff and legacy carers both get the default Staff set, without money', async () => {
    for (const uid of ['legacyStaffA', 'legacyCarerA']) {
      await assertSucceeds(as(uid).doc('cases/ownedA').update({ note: 'legacy' }));
      await assertSucceeds(as(uid).doc('animals/a1/medicationDoses/d9').set({ givenBy: uid }));
      await assertFails(as(uid).doc('donations/d1').get());
      await assertFails(as(uid).doc('donationPayments/p1').get());
    }
  });
});

describe('who changes access', () => {
  test('no client writes permissions or preset, Admins included', async () => {
    await assertFails(as('adminA').doc('organizations/orgA/members/fullA').update({ permissions: presets.treasurer }));
    await assertFails(as('ownerA').doc('organizations/orgA/members/fullA').update({ preset: 'treasurer' }));
    await assertFails(as('fullA').doc('organizations/orgA/members/fullA').update({ permissions: presets.treasurer }));
    // Status changes stay with Admins.
    await assertSucceeds(as('adminA').doc('organizations/orgA/members/fullA').update({ status: 'inactive' }));
    await assertFails(as('fullA').doc('organizations/orgA/members/rescueA').update({ status: 'inactive' }));
  });

  test('only Admins invite, and only with known permissions', async () => {
    const invite = (extra = {}) => ({
      organizationId: 'orgA', email: 'x@example.com', normalizedEmail: 'x@example.com', status: 'pending',
      role: 'staff', permissions: presets.treasurer, preset: 'treasurer', ...extra,
    });
    await assertSucceeds(as('adminA').doc('organizationInvitations/i1').set(invite()));
    await assertFails(as('fullA').doc('organizationInvitations/i2').set(invite()));
    await assertFails(as('fullA').doc('organizationInvitations/i3').set(invite({ role: 'admin' })));
    await assertFails(as('adminA').doc('organizationInvitations/i4').set(invite({ permissions: ['everything'] })));
  });

  test('an Admin can check for an invitation that does not exist yet', async () => {
    // createInvitation used to read the doc in a transaction first; a missing
    // invitation must not be permission-denied for its org's Admins.
    await assertSucceeds(as('adminA').doc('organizationInvitations/orgA_new@example.com').get());
    await assertFails(as('fullA').doc('organizationInvitations/orgA_new@example.com').get());
    await assertFails(as('staffB').doc('organizationInvitations/orgA_new@example.com').get());
  });

  test('a phone invitation is matched by the verified sign-in number only', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('organizationInvitations/orgA_phone_639171234567').set({
      organizationId: 'orgA', email: '', normalizedEmail: '', phone: '09171234567', normalizedPhone: '+639171234567',
      status: 'pending', role: 'staff', permissions: presets.animalCare, preset: 'animalCare',
    }));
    const path = 'organizationInvitations/orgA_phone_639171234567';
    const right = env.authenticatedContext('stranger', { phone_number: '+639171234567' }).firestore();
    const wrong = env.authenticatedContext('reporter', { phone_number: '+639999999999' }).firestore();
    // No email on a phone-only account must not match an invitation's empty email.
    const noEmail = env.authenticatedContext('adopter', {}).firestore();
    await assertSucceeds(right.doc(path).get());
    await assertFails(wrong.doc(path).get());
    await assertFails(noEmail.doc(path).get());
    await assertSucceeds(right.collection('organizationInvitations')
      .where('normalizedPhone', '==', '+639171234567').where('status', '==', 'pending').get());
    const member = { uid: 'stranger', organizationId: 'orgA', role: 'staff', status: 'active',
      invitationId: 'orgA_phone_639171234567', permissions: presets.animalCare, preset: 'animalCare' };
    await assertFails(wrong.doc('organizations/orgA/members/reporter').set({ ...member, uid: 'reporter' }));
    await assertSucceeds(right.doc('organizations/orgA/members/stranger').set(member));
    await assertSucceeds(right.doc(path).update({ status: 'accepted' }));
  });

  test('accepting copies the invitation access exactly', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('organizationInvitations/t1').set({
      organizationId: 'orgA', email: 'stranger@example.com', normalizedEmail: 'stranger@example.com',
      status: 'pending', role: 'staff', permissions: presets.animalCare, preset: 'animalCare',
    }));
    const stranger = env.authenticatedContext('stranger', { email: 'stranger@example.com' }).firestore();
    const member = (extra = {}) => ({ uid: 'stranger', organizationId: 'orgA', role: 'staff', status: 'active',
      invitationId: 't1', permissions: presets.animalCare, preset: 'animalCare', ...extra });
    await assertFails(stranger.doc('organizations/orgA/members/stranger').set(member({ permissions: presets.treasurer })));
    await assertFails(stranger.doc('organizations/orgA/members/stranger').set(member({ role: 'admin' })));
    await assertSucceeds(stranger.doc('organizations/orgA/members/stranger').set(member()));
  });
});
