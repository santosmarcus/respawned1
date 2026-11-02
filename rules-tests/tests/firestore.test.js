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

  test('follow-up check-ins: adopter and staff only', async () => {
    await assertSucceeds(as('adopter').doc('adoptions/appA/checkins/c1').set({ howIsPetDoing: 'great' }));
    await assertFails(as('stranger').doc('adoptions/appA/checkins/c1').set({ howIsPetDoing: 'bad' }));
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
