import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;

let env;
const as = (uid, token = {}) => env.authenticatedContext(uid, token).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

describe('users', () => {
  test('cannot self-assign a staff role', async () => {
    await assertFails(as('stranger').doc('users/stranger').update({ role: 'admin' }));
    await assertFails(as('stranger').doc('users/stranger').update({ role: 'ngo_staff' }));
  });

  test('can pick an onboarding role', async () => {
    await assertSucceeds(as('stranger').doc('users/stranger').update({ role: 'pet_transporter' }));
  });

  test('new accounts cannot start as staff', async () => {
    await assertFails(as('newbie').doc('users/newbie').set({ role: 'admin' }));
    await assertSucceeds(as('newbie').doc('users/newbie').set({ role: '', isVerified: false }));
  });

  test('cannot link themselves to an organization they are not part of', async () => {
    await assertFails(as('stranger').doc('users/stranger').update({ organizationId: 'orgA' }));
  });

  test('cannot approve themselves', async () => {
    await assertFails(as('rider').doc('users/rider').update({ isVerified: true }));
    await assertFails(as('rider').doc('users/rider').update({ transporterVerificationStatus: 'approved' }));
    await assertSucceeds(as('rider').doc('users/rider').update({ transporterVerificationStatus: 'pending' }));
  });

  test("cannot edit someone else's profile", async () => {
    await assertFails(as('stranger').doc('users/reporter').update({ phone: '123' }));
  });

  test('an org admin can unlink their member; other orgs cannot', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('organizations/orgA/members/staffA').delete());
    await assertFails(as('staffB').doc('users/staffA').update({ organizationId: FieldValue.delete() }));
    await assertSucceeds(as('ownerA').doc('users/staffA').update({ organizationId: FieldValue.delete() }));
  });

  test('accepting an invitation links the account', async () => {
    const db = as('newbie', { email: 'newbie@example.com' });
    await db.doc('users/newbie').set({ role: 'organization_member' });
    const batch = db.batch();
    batch.update(db.doc('organizationInvitations/inv1'), { status: 'accepted' });
    batch.set(db.doc('organizations/orgA/members/newbie'), {
      uid: 'newbie', organizationId: 'orgA', role: 'staff', status: 'active', invitationId: 'inv1',
    });
    batch.set(db.doc('users/newbie'), { organizationId: 'orgA' }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('registering an organization links its owner', async () => {
    const db = as('founder');
    await db.doc('users/founder').set({ role: '' });
    await assertSucceeds(db.doc('organizations/newOrg').set({ ownerId: 'founder', name: 'New', verificationStatus: 'draft' }));
    await assertSucceeds(db.doc('users/founder').set({ role: 'organization' }, { merge: true }));
    await assertSucceeds(db.doc('organizations/newOrg/members/founder').set({ role: 'admin' }, { merge: true }));
    await assertSucceeds(db.doc('users/founder').update({ organizationId: 'newOrg' }));
  });
});

describe('organizations', () => {
  test('cannot approve their own organization', async () => {
    await assertFails(as('draftOwner').doc('organizations/orgD').update({ verificationStatus: 'approved' }));
    await assertSucceeds(as('draftOwner').doc('organizations/orgD').update({ verificationStatus: 'pending' }));
  });

  test('cannot create a pre-approved organization', async () => {
    await assertFails(as('stranger').doc('organizations/x').set({ ownerId: 'stranger', verificationStatus: 'approved' }));
    await assertFails(as('stranger').doc('organizations/x').set({ ownerId: 'stranger' }));
  });

  test('platform staff can bootstrap an organization', async () => {
    const db = as('admin');
    const batch = db.batch();
    batch.set(db.doc('organizations/boot'), { ownerId: 'admin', name: 'Boot', bootstrapped: true });
    batch.set(db.doc('users/admin'), { organizationId: 'boot' }, { merge: true });
    batch.set(db.doc('organizations/boot/members/admin'), { role: 'admin', status: 'active' }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test("only the organization's staff edit its profile", async () => {
    await assertFails(as('stranger').doc('organizations/orgA').update({ name: 'Hijacked' }));
    await assertFails(as('staffB').doc('organizations/orgA').update({ name: 'Hijacked' }));
    await assertSucceeds(as('staffA').doc('organizations/orgA').update({ shelterName: 'Main shelter' }));
  });
});

describe('cases', () => {
  test('reporters file their own reports only', async () => {
    await assertSucceeds(as('reporter').collection('cases').add({ reporterId: 'reporter', status: 'pending' }));
    await assertFails(as('reporter').collection('cases').add({ reporterId: 'stranger', status: 'pending' }));
  });

  test('reporters cannot stamp a new report with an organization', async () => {
    await assertFails(as('reporter').collection('cases').add({ reporterId: 'reporter', organizationId: 'orgA', status: 'pending' }));
    await assertFails(as('reporter').collection('cases').add({ reporterId: 'reporter', organizationId: 'orgB', status: 'pending' }));
    await assertSucceeds(as('reporter').collection('cases').add({ reporterId: 'reporter', organizationId: '', status: 'pending' }));
  });

  test("strangers and other organizations can't touch an owned case", async () => {
    await assertFails(as('stranger').doc('cases/ownedA').update({ status: 'completed' }));
    await assertFails(as('staffB').doc('cases/ownedA').update({ status: 'completed' }));
    await assertSucceeds(as('staffA').doc('cases/ownedA').update({ status: 'awaiting_assignment' }));
  });

  test('approved staff accept unowned cases for their own organization only', async () => {
    await assertFails(as('staffA').doc('cases/pending1').update({ status: 'accepted_pending_clinic', organizationId: 'orgB' }));
    await assertSucceeds(as('staffB').doc('cases/pending1').update({ status: 'accepted_pending_clinic', organizationId: 'orgB' }));
  });

  test('a draft organization cannot pick up cases', async () => {
    await assertFails(as('draftOwner').doc('cases/pending1').update({ status: 'accepted_pending_clinic', organizationId: 'orgD' }));
  });

  test('reporters edit their report but not its ownership', async () => {
    await assertSucceeds(as('reporter').doc('cases/ownedA').update({ hiddenFromExplore: true }));
    await assertFails(as('reporter').doc('cases/ownedA').update({ organizationId: 'orgB' }));
    await assertFails(as('reporter').doc('cases/ownedA').update({ riderId: 'reporter' }));
  });

  test('the offered transporter accepts; another cannot', async () => {
    const accept = (uid) => {
      const db = as(uid);
      const batch = db.batch();
      batch.update(db.doc('cases/offered/transportAssignments/as1'), { status: 'accepted', acceptedAt: 1 });
      batch.update(db.doc('cases/offered'), { status: 'assigned', riderId: uid, assignedVolunteerId: uid });
      return batch.commit();
    };
    await assertFails(accept('rider2'));
    await assertSucceeds(accept('rider'));
  });

  test('the assigned transporter reports progress', async () => {
    await assertSucceeds(as('rider').doc('cases/assigned').update({ status: 'dropoff', riderLastLat: 14.5, riderLastLng: 121 }));
    await assertFails(as('rider2').doc('cases/assigned').update({ status: 'completed' }));
    // No-op writes and status-history spam from outsiders are denied too.
    await assertFails(as('stranger').doc('cases/assigned').update({ status: 'dropoff' }));
  });

  test('transporters can claim an open pending case or decline any', async () => {
    await assertSucceeds(as('rider').doc('cases/pending1').update({
      status: 'accepted', assignedVolunteerId: 'rider', assignedVolunteerName: 'R',
    }));
    await assertSucceeds(as('rider2').doc('cases/ownedA').update({ declinedBy: FieldValue.arrayUnion('rider2') }));
    await assertFails(as('stranger').doc('cases/pending1').update({ status: 'accepted', assignedVolunteerId: 'stranger' }));
  });

  test('one person registers adoption interest; nobody can replace them', async () => {
    const interest = (uid) => as(uid).doc('cases/ownedA').update({
      willingAdopterId: uid, willingAdopterName: uid, willingAdopterType: 'adopt',
    });
    await assertSucceeds(interest('adopter'));
    await assertFails(interest('stranger'));
    await assertSucceeds(as('adopter').doc('cases/ownedA').update({ adopterArrivedAtTreatment: true }));
  });

  test('case chat is for participants only', async () => {
    await assertFails(as('stranger').collection('cases/ownedA/messages').get());
    await assertSucceeds(as('reporter').collection('cases/ownedA/messages').add({ text: 'hi' }));
    await assertSucceeds(as('staffA').collection('cases/ownedA/messages').get());
  });

  test('anyone can add a sighting', async () => {
    await assertSucceeds(as('stranger').collection('cases/ownedA/communityReports').add({ note: 'seen it' }));
  });

  test('platform staff can act on any case', async () => {
    await assertSucceeds(as('admin').doc('cases/ownedA').update({ status: 'completed' }));
  });
});

describe('animals', () => {
  test("only the owning organization's staff manage records", async () => {
    await assertSucceeds(as('staffA').collection('animals').add({ name: 'Kiko', organizationId: 'orgA' }));
    await assertFails(as('staffA').collection('animals').add({ name: 'Kiko', organizationId: 'orgB' }));
    await assertFails(as('stranger').collection('animals').add({ name: 'Kiko' }));
    await assertFails(as('staffB').doc('animals/animalA').update({ adoptionStatus: 'adopted' }));
    await assertFails(as('staffB').doc('animals/animalA/vaccinations/v1').set({ name: 'Rabies' }));
    await assertSucceeds(as('staffA').doc('animals/animalA/vaccinations/v1').set({ name: 'Rabies' }));
  });
});

describe('adoption readiness gate', () => {
  const readiness = { confirmedBy: 'staffA', items: ['health'] };

  test('a new adoptable record needs the readiness checklist', async () => {
    await assertFails(as('staffA').doc('animals/n1').set({ organizationId: 'orgA', adoptionStatus: 'adoptable' }));
    await assertSucceeds(as('staffA').doc('animals/n2').set({ organizationId: 'orgA', adoptionStatus: 'adoptable', adoptionReadiness: readiness }));
    await assertSucceeds(as('staffA').doc('animals/n3').set({ organizationId: 'orgA', adoptionStatus: 'not_ready' }));
  });

  test('flipping not_ready to adoptable needs it; re-saves and releases do not', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/nr').set({ organizationId: 'orgA', adoptionStatus: 'not_ready' });
      await db.doc('animals/res').set({ organizationId: 'orgA', adoptionStatus: 'reserved' });
    });
    await assertFails(as('staffA').doc('animals/nr').update({ adoptionStatus: 'adoptable' }));
    await assertSucceeds(as('staffA').doc('animals/nr').update({ adoptionStatus: 'adoptable', adoptionReadiness: readiness }));
    await assertSucceeds(as('staffA').doc('animals/animalA').update({ name: 'Mochi II' }));
    await assertSucceeds(as('staffA').doc('animals/res').update({ adoptionStatus: 'adoptable' }));
  });
});

describe('adoptions', () => {
  test('adopters submit pending applications for the right organization', async () => {
    const app = (data) => as('adopter').collection('adoptions').add({
      status: 'pending', personal: { adopterId: 'adopter', animalRecordId: 'animalA' }, ...data,
    });
    await assertSucceeds(app({ organizationId: 'orgA' }));
    await assertFails(app({ organizationId: 'orgB' }));
    await assertFails(app({ organizationId: 'orgA', status: 'approved' }));
  });

  test('adopters can withdraw but not approve', async () => {
    await assertFails(as('adopter').doc('adoptions/appA').update({ status: 'approved' }));
    await assertSucceeds(as('adopter').doc('adoptions/appA').update({ status: 'withdrawn' }));
  });

  test("the owning organization's staff decide", async () => {
    await assertFails(as('staffB').doc('adoptions/appA').update({ status: 'approved' }));
    await assertFails(as('stranger').doc('adoptions/appA').update({ status: 'approved' }));
    await assertSucceeds(as('staffA').doc('adoptions/appA').update({ status: 'approved' }));
  });

  test('applications are readable by the adopter and the owning org only', async () => {
    await assertSucceeds(as('adopter').doc('adoptions/appA').get());
    await assertSucceeds(as('staffA').doc('adoptions/appA').get());
    await assertSucceeds(as('admin').doc('adoptions/appA').get());
    await assertFails(as('stranger').doc('adoptions/appA').get());
    await assertFails(as('staffB').doc('adoptions/appA').get());
    await assertFails(as('carerA').doc('adoptions/appA').get());
  });

  test('adoption queries must be scoped to the adopter or the organization', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('adoptions/appB').set({
      organizationId: 'orgB', status: 'pending', personal: { adopterId: 'stranger', animalRecordId: 'animalB' },
    }));
    await assertSucceeds(as('adopter').collection('adoptions').where('personal.adopterId', '==', 'adopter').get());
    await assertSucceeds(as('staffA').collection('adoptions').where('organizationId', '==', 'orgA').get());
    await assertSucceeds(as('staffA').collection('adoptions')
      .where('organizationId', '==', 'orgA').where('status', 'in', ['pending', 'approved']).get());
    await assertSucceeds(as('admin').collection('adoptions').get());
    await assertFails(as('staffA').collection('adoptions').get());
    await assertFails(as('stranger').collection('adoptions').where('personal.animalRecordId', '==', 'animalA').get());
    await assertFails(as('staffB').collection('adoptions').where('organizationId', '==', 'orgA').get());
  });

  test('follow-up check-ins: adopter and staff only', async () => {
    await assertSucceeds(as('adopter').doc('adoptions/appA/checkins/c1').set({ howIsPetDoing: 'great' }));
    await assertFails(as('stranger').doc('adoptions/appA/checkins/c1').set({ howIsPetDoing: 'bad' }));
  });
});

describe('carers', () => {
  test('a carer records a dose they gave, not one for someone else', async () => {
    const dose = (givenBy) => ({ planId: 'p1', animalId: 'animalA', slot: 1, day: new Date(), givenBy });
    await assertSucceeds(as('carerA').doc('animals/animalA/medicationDoses/d1').set(dose('carerA')));
    await assertFails(as('carerA').doc('animals/animalA/medicationDoses/d2').set(dose('ownerA')));
  });

  test('staff may record doses for the org; strangers may not', async () => {
    await assertSucceeds(as('staffA').doc('animals/animalA/medicationDoses/d3').set({ planId: 'p1', givenBy: 'carerA' }));
    await assertFails(as('stranger').doc('animals/animalA/medicationDoses/d4').set({ planId: 'p1', givenBy: 'stranger' }));
  });

  test('carers cannot plan medication or edit animal records', async () => {
    await assertFails(as('carerA').doc('animals/animalA/medications/p1').set({ drug: 'X', animalId: 'animalA' }));
    await assertFails(as('carerA').doc('animals/animalA').update({ name: 'Renamed' }));
    await assertSucceeds(as('staffA').doc('animals/animalA/medications/p1').set({ drug: 'X', animalId: 'animalA' }));
  });

  test("a carer cannot overwrite another carer's dose record", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('animals/animalA/medicationDoses/taken').set({ planId: 'p1', givenBy: 'otherCarer' }));
    await assertFails(as('carerA').doc('animals/animalA/medicationDoses/taken').set({ planId: 'p1', givenBy: 'carerA' }));
  });

  test('carers cannot invite anyone', async () => {
    await assertFails(as('carerA').collection('organizationInvitations').add({
      organizationId: 'orgA', normalizedEmail: 'x@example.com', email: 'x@example.com', status: 'pending', role: 'admin',
    }));
  });

  test('carers are not staff: no case stamping or org changes', async () => {
    await assertFails(as('carerA').doc('cases/ownedA').update({ status: 'completed' }));
    await assertFails(as('carerA').doc('cases/pending1').update({ status: 'accepted_pending_clinic', organizationId: 'orgA' }));
    await assertFails(as('carerA').doc('organizations/orgA').update({ shelterName: 'Hijacked' }));
  });
});

describe('volunteer applications', () => {
  const app = (uid, extra = {}) => ({ uid, name: 'R', phone: '0917', categories: ['event'], availability: 'weekends', status: 'pending', ...extra });

  test('applicants submit their own, always pending, never self-approved', async () => {
    await assertSucceeds(as('stranger').doc('volunteerApplications/stranger').set(app('stranger')));
    await assertFails(as('stranger').doc('volunteerApplications/reporter').set(app('reporter')));
    await assertFails(as('stranger').doc('volunteerApplications/stranger').set(app('stranger', { status: 'approved' })));
    await assertFails(as('stranger').doc('volunteerApplications/stranger').set(app('stranger', { reviewedBy: 'stranger' })));
  });

  test('approved staff review; carers and strangers cannot read or review', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('volunteerApplications/stranger').set(app('stranger')));
    await assertFails(as('reporter').doc('volunteerApplications/stranger').get());
    await assertFails(as('carerA').doc('volunteerApplications/stranger').get());
    await assertSucceeds(as('staffA').doc('volunteerApplications/stranger').get());
    await assertFails(as('carerA').doc('volunteerApplications/stranger').update({ status: 'approved', reviewedBy: 'carerA' }));
    await assertFails(as('staffA').doc('volunteerApplications/stranger').update({ status: 'approved', reviewedBy: 'someoneElse' }));
    await assertSucceeds(as('staffA').doc('volunteerApplications/stranger').update({ status: 'approved', reviewedBy: 'staffA' }));
  });
});

describe('collection-group queries', () => {
  test('transporters list their own offers', async () => {
    await assertSucceeds(as('rider').collectionGroup('transportAssignments')
      .where('riderId', '==', 'rider').where('status', '==', 'pending').get());
    await assertFails(as('rider').collectionGroup('transportAssignments').get());
  });

  test('staff dashboards read across cases; others cannot', async () => {
    await assertSucceeds(as('staffA').collectionGroup('expenses').get());
    await assertFails(as('stranger').collectionGroup('expenses').get());
  });
});
