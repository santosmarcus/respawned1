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
    await assertFails(as('rider2').doc('users/rider2').update({ isVerified: true }));
    await assertFails(as('rider2').doc('users/rider2').update({ transporterVerificationStatus: 'approved' }));
    await assertSucceeds(as('rider2').doc('users/rider2').update({ transporterVerificationStatus: 'pending' }));
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

  test('review decisions go through the callable only, platform staff included', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('organizations/orgD').update({ verificationStatus: 'pending' }));
    await assertFails(as('admin').doc('organizations/orgD').update({ verificationStatus: 'approved' }));
    await assertFails(as('admin').doc('organizations/orgD').update({ verificationRejectionReason: 'Blurry permit' }));
    await assertFails(as('draftOwner').doc('organizations/orgD').update({ verificationReviewedBy: 'draftOwner' }));
    // Platform staff can still edit other fields.
    await assertSucceeds(as('admin').doc('organizations/orgD').update({ name: 'Org D (renamed)' }));
  });

  test('the owner can resubmit after a rejection or a request for changes', async () => {
    for (const status of ['rejected', 'requiresChanges']) {
      await env.withSecurityRulesDisabled((ctx) =>
        ctx.firestore().doc('organizations/orgD').update({ verificationStatus: status, verificationRejectionReason: 'Fix it' }));
      await assertSucceeds(as('draftOwner').doc('organizations/orgD').update({ verificationStatus: 'pending' }));
    }
    await assertFails(as('draftOwner').doc('organizations/orgD').update({ verificationStatus: 'requiresChanges' }));
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

  test("only the organization's admins edit its profile", async () => {
    await assertFails(as('stranger').doc('organizations/orgA').update({ name: 'Hijacked' }));
    await assertFails(as('staffB').doc('organizations/orgA').update({ name: 'Hijacked' }));
    await assertFails(as('staffA').doc('organizations/orgA').update({ shelterName: 'Main shelter' }));
    await assertSucceeds(as('ownerA').doc('organizations/orgA').update({ shelterName: 'Main shelter' }));
  });

  test("shelter settings: the organization's staff read, its admins write", async () => {
    const doc = 'organizations/orgA/settings/shelter';
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(doc).set({ maxCapacity: 20 }));
    await assertSucceeds(as('staffA').doc(doc).get());
    await assertSucceeds(as('admin').doc(doc).get());
    await assertFails(as('staffB').doc(doc).get());
    await assertFails(as('stranger').doc(doc).get());
    await assertSucceeds(as('ownerA').doc(doc).set({ maxCapacity: 25 }, { merge: true }));
    await assertFails(as('staffA').doc(doc).set({ maxCapacity: 99 }, { merge: true }));
    await assertFails(as('staffB').doc(doc).set({ maxCapacity: 99 }, { merge: true }));
  });
});

describe('who reads full rescue reports', () => {
  test('the people working a case read it; others read the public copy', async () => {
    // Reporter, staff, the assigned rider and the offered rider.
    await assertSucceeds(as('reporter').doc('cases/pending1').get());
    await assertSucceeds(as('staffA').doc('cases/pending1').get());
    await assertSucceeds(as('admin').doc('cases/ownedA').get());
    await assertSucceeds(as('rider').doc('cases/assigned').get());
    await assertSucceeds(as('rider').doc('cases/offered').get());
    await assertSucceeds(as('rider').doc('cases/verifying1').get());
    // Everyone else.
    await assertFails(as('stranger').doc('cases/pending1').get());
    await assertFails(as('rider2').doc('cases/assigned').get());
    await assertFails(as('carerA').doc('cases/ownedA').get());
    await assertFails(as('stranger').collection('cases').get());
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('publicCases/pending1').set({ status: 'pending', lat: 14.5 }));
    await assertSucceeds(as('stranger').doc('publicCases/pending1').get());
    await assertSucceeds(as('stranger').collection('publicCases').get());
    await assertFails(as('staffA').doc('publicCases/pending1').set({ status: 'closed' }));
  });

  test('their own lists can be queried', async () => {
    await assertSucceeds(as('reporter').collection('cases').where('reporterId', '==', 'reporter').get());
    await assertSucceeds(as('rider').collection('cases').where('assignedVolunteerId', '==', 'rider').get());
    await assertSucceeds(as('rider').collection('cases').where('verification.riderId', '==', 'rider').get());
    // Staff: the unowned pool, their own organization's, and referrals.
    await assertSucceeds(as('staffB').collection('cases').where('organizationId', '==', '').where('status', 'in', ['pending', 'verifying']).get());
    await assertSucceeds(as('staffA').collection('cases').where('organizationId', '==', 'orgA').where('status', 'in', ['accepted', 'assigned']).get());
    await assertSucceeds(as('staffB').collection('cases').where('referredToOrgId', '==', 'orgB').get());
    await assertFails(as('staffB').collection('cases').where('referredToOrgId', '==', 'orgA').get());
    await assertFails(as('staffB').collection('cases').where('status', '==', 'referred').get());
    await assertFails(as('staffB').collection('cases').where('organizationId', '==', 'orgA').get());
    await assertFails(as('reporter').collection('cases').where('status', '==', 'pending').get());
  });

  test('verified transporters and approved volunteers see the job board', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('users/rider2').update({ isVerified: true, transporterVerificationStatus: 'approved' });
      await db.doc('users/vol').set({ role: 'rescue_volunteer' });
      await db.doc('volunteerApplications/vol').set({ uid: 'vol', status: 'approved' });
      await db.doc('users/vol2').set({ role: 'rescue_volunteer' });
      await db.doc('volunteerApplications/vol2').set({ uid: 'vol2', status: 'pending' });
    });
    await assertSucceeds(as('rider2').collection('cases').where('status', '==', 'pending').get());
    await assertSucceeds(as('vol').doc('cases/pending1').get());
    await assertFails(as('vol2').doc('cases/pending1').get());
  });

  test('a report open to Community Adoption is public, and only those can be claimed', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/adoptable').set({
      reporterId: 'reporter', status: 'rejected', rejectionReason: 'healthyAnimalLowUrgency', rescueType: 'Stray',
    }));
    await assertSucceeds(as('stranger').doc('cases/adoptable').get());
    const claim = { communityAdoptionIds: FieldValue.arrayUnion('c1'), status: 'closed' };
    await assertFails(as('stranger').doc('cases/pending1').update(claim));
    await assertSucceeds(as('stranger').doc('cases/adoptable').update(claim));
  });

  test("a case's timeline is for the people working it", async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/ownedA/activityLogs/t1').set({ action: 'accepted' }));
    await assertSucceeds(as('reporter').doc('cases/ownedA/activityLogs/t1').get());
    await assertSucceeds(as('staffA').doc('cases/ownedA/activityLogs/t1').get());
    await assertFails(as('stranger').doc('cases/ownedA/activityLogs/t1').get());
  });
});

describe('staff stay inside their own organization', () => {
  test("another organization's case, offers and follow-ups are off limits", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('cases/offered/transportAssignments/as1').update({ organizationId: 'orgA' });
      await db.doc('adoptions/appA/followUps/f1').set({ organizationId: 'orgA', status: 'scheduled' });
      await db.doc('cases/referredA').set({ reporterId: 'reporter', status: 'referred', organizationId: 'orgA', referredToOrgId: 'orgB' });
      await db.doc('cases/referredElsewhere').set({ reporterId: 'reporter', status: 'referred', organizationId: 'orgA', referredToOrgId: 'orgC' });
    });
    // Owned case.
    await assertSucceeds(as('staffA').doc('cases/ownedA').get());
    await assertFails(as('staffB').doc('cases/ownedA').get());
    // A referred case: the organization it is referred to, and nobody else.
    await assertSucceeds(as('staffB').doc('cases/referredA').get());
    await assertFails(as('staffB').doc('cases/referredElsewhere').get());
    // The target accepts it (takes ownership) or declines it.
    await assertSucceeds(as('staffB').doc('cases/referredA').update({
      status: 'pending', organizationId: 'orgB', referredToOrgId: FieldValue.delete(),
    }));
    await assertFails(as('staffB').doc('cases/referredElsewhere').update({ status: 'pending' }));
    // The unowned pool is shared.
    await assertSucceeds(as('staffB').doc('cases/pending1').get());
    // Offers.
    await assertSucceeds(as('staffA').doc('cases/offered/transportAssignments/as1').get());
    await assertFails(as('staffB').doc('cases/offered/transportAssignments/as1').get());
    await assertSucceeds(as('staffA').collectionGroup('transportAssignments').where('organizationId', '==', 'orgA').where('status', '==', 'pending').get());
    await assertFails(as('staffA').collectionGroup('transportAssignments').where('status', '==', 'pending').get());
    await assertFails(as('staffB').collectionGroup('transportAssignments').where('organizationId', '==', 'orgA').get());
    await assertSucceeds(as('rider').collectionGroup('transportAssignments').where('riderId', '==', 'rider').get());
    // Follow-ups.
    await assertSucceeds(as('staffA').collectionGroup('followUps').where('organizationId', '==', 'orgA').where('status', 'in', ['scheduled', 'reminderSent']).get());
    await assertFails(as('staffA').collectionGroup('followUps').where('status', 'in', ['scheduled', 'reminderSent']).get());
    await assertFails(as('staffB').doc('adoptions/appA/followUps/f1').get());
    // Platform staff see everything.
    await assertSucceeds(as('admin').collection('cases').get());
    await assertSucceeds(as('admin').collectionGroup('transportAssignments').get());
    await assertSucceeds(as('admin').collectionGroup('followUps').get());
  });

  test("a rider's availability is kept by the server", async () => {
    await assertFails(as('rider').doc('users/rider').update({ transportStatus: { status: 'completed' } }));
    await assertSucceeds(as('staffB').collection('users').where('role', 'in', ['pet_transporter', 'rescue_volunteer']).get());
  });
});

describe('who reads user profiles', () => {
  test('yourself, organization staff, and your own organization', async () => {
    await assertSucceeds(as('reporter').doc('users/reporter').get());
    await assertSucceeds(as('staffA').doc('users/reporter').get());
    await assertSucceeds(as('admin').doc('users/reporter').get());
    await assertSucceeds(as('carerA').doc('users/staffA').get());
    await assertSucceeds(as('staffA').collection('users').where('role', '==', 'pet_transporter').get());
    await assertFails(as('stranger').doc('users/reporter').get());
    await assertFails(as('rider').doc('users/reporter').get());
    await assertFails(as('carerA').doc('users/reporter').get());
    await assertFails(as('stranger').collection('users').where('role', '==', 'pet_transporter').get());
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

  test('an unverified transporter cannot claim or accept a transit', async () => {
    // rider2 is a pet transporter whose application isn't approved yet.
    await assertFails(as('rider2').doc('cases/pending1').update({
      status: 'accepted', assignedVolunteerId: 'rider2', assignedVolunteerName: 'R2',
    }));
    await assertFails(as('rider2').doc('cases/pending1').update({ riderId: 'rider2' }));
    // Declining still works.
    await assertSucceeds(as('rider2').doc('cases/pending1').update({ declinedBy: FieldValue.arrayUnion('rider2') }));
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

describe('withdrawing a referral (CaseReferralRepository.withdraw)', () => {
  // The writes withdraw makes, in one batch.
  const withdraw = (uid, caseId, referralId) => {
    const db = as(uid);
    const batch = db.batch();
    batch.update(db.doc(`cases/${caseId}`), {
      status: 'pending',
      referredToOrgId: FieldValue.delete(),
      referralOutcome: { status: 'withdrawn', referralId, reason: 'Handling it ourselves', byUid: uid },
      statusHistory: FieldValue.arrayUnion({ status: 'Referral withdrawn. The case is open again.' }),
    });
    batch.update(db.doc(`cases/${caseId}/referrals/${referralId}`), {
      status: 'withdrawn', respondedByUid: uid, withdrawReason: 'Handling it ourselves',
    });
    batch.set(db.collection(`cases/${caseId}/activityLogs`).doc(), {
      action: 'referral_withdrawn', actorUid: uid, details: { referralId },
    });
    return batch.commit();
  };

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('cases/refOrg').set({
        reporterId: 'reporter', status: 'referred', organizationId: 'orgA', referredToOrgId: 'orgB',
        referral: { referralId: 'r1', targetOrgId: 'orgB', fromOrgId: 'orgA', previousStatus: 'pending' },
      });
      await db.doc('cases/refOrg/referrals/r1').set({ type: 'anotherOrganization', status: 'referredPending', fromOrgId: 'orgA', targetOrgId: 'orgB' });
      await db.doc('cases/refLgu').set({ reporterId: 'reporter', status: 'referred', organizationId: 'orgA' });
      await db.doc('cases/refLgu/referrals/l1').set({ type: 'localGovernmentUnit', status: 'notified', barangay: 'San Isidro' });
    });
  });

  test("the referring organization's rescue staff reopen an organization referral", async () => {
    await assertSucceeds(withdraw('rescueA', 'refOrg', 'r1'));
  });

  test('an LGU referral can be withdrawn too', async () => {
    await assertSucceeds(withdraw('staffA', 'refLgu', 'l1'));
  });

  test('staff without rescue, other organizations and the reporter cannot', async () => {
    await assertFails(withdraw('careA', 'refOrg', 'r1'));
    await assertFails(withdraw('stranger', 'refOrg', 'r1'));
    await assertFails(withdraw('reporter', 'refOrg', 'r1'));
  });

  test('the organization it was referred to declines instead of withdrawing', async () => {
    await assertFails(withdraw('staffB', 'refOrg', 'r1'));
    await assertSucceeds(as('staffB').doc('cases/refOrg').update({
      status: 'pending', referredToOrgId: FieldValue.delete(),
      referralOutcome: { status: 'declined', reason: 'No space' },
    }));
  });
});

describe('report verification', () => {
  test('a report can carry its evidence, which the reporter cannot rewrite', async () => {
    await assertSucceeds(as('reporter').collection('cases').add({
      reporterId: 'reporter', status: 'pending', reportEvidence: { cameraMediaCount: 2, galleryMediaCount: 0 },
    }));
    await assertFails(as('reporter').doc('cases/pending1').update({ reportEvidence: { cameraMediaCount: 4 } }));
  });

  test('staff ask for live proof and record the desk result on an unowned report', async () => {
    await assertSucceeds(as('staffA').doc('cases/pending1').update({
      liveProofRequest: { requestedBy: 'staffA', requestedAt: FieldValue.serverTimestamp() },
      statusHistory: FieldValue.arrayUnion({ status: 'asked' }),
    }));
    await assertSucceeds(as('staffA').doc('cases/pending1').update({
      'verification.deskOutcome': 'needsRider', 'verification.deskBy': 'staffA',
      'verification.riderId': 'rider', 'verification.riderName': 'Rider One',
      status: 'verifying', verifyingOrganizationId: 'orgA',
    }));
    await assertFails(as('stranger').doc('cases/pending1').update({ 'verification.deskOutcome': 'confirmedRemotely' }));
    await assertFails(as('draftOwner').doc('cases/pending1').update({ 'verification.deskOutcome': 'confirmedRemotely' }));
  });

  test('the reporter sends live proof but cannot write the request or the result', async () => {
    await assertSucceeds(as('reporter').doc('cases/pending1').update({
      liveProof: { mediaUrls: ['u'], mediaTypes: ['image'], submittedAt: FieldValue.serverTimestamp(), lat: 14.5, lng: 121 },
      statusHistory: FieldValue.arrayUnion({ status: 'sent' }),
    }));
    await assertFails(as('stranger').doc('cases/pending1').update({ liveProof: { mediaUrls: ['u'] } }));
    await assertFails(as('reporter').doc('cases/pending1').update({ liveProofRequest: { requestedBy: 'reporter' } }));
    await assertFails(as('reporter').doc('cases/pending1').update({ verification: { deskOutcome: 'confirmedRemotely' } }));
    await assertFails(as('reporter').doc('cases/verifying1').update({ 'verification.riderOutcome': 'found' }));
  });

  test('the rider sent to verify records the result of their own visit only', async () => {
    const result = (uid) => as(uid).doc('cases/verifying1').update({
      'verification.riderOutcome': 'found', 'verification.riderNote': 'under the bridge',
      'verification.riderMediaUrls': ['u'], 'verification.riderMediaTypes': ['image'],
      'verification.riderRecordedAt': FieldValue.serverTimestamp(),
      'verification.riderRecordedBy': uid, 'verification.riderRecordedByName': uid,
      'verification.riderLat': 14.5, 'verification.riderLng': 121,
      status: 'pending',
      statusHistory: FieldValue.arrayUnion({ status: 'found' }),
    });
    await assertFails(result('rider2'));
    await assertFails(result('stranger'));
    // Not the desk decision, not who was sent, not acceptance.
    await assertFails(as('rider').doc('cases/verifying1').update({ 'verification.deskOutcome': 'confirmedRemotely' }));
    await assertFails(as('rider').doc('cases/verifying1').update({ 'verification.riderId': 'rider2' }));
    await assertFails(as('rider').doc('cases/verifying1').update({
      'verification.riderOutcome': 'found', status: 'accepted_pending_clinic', organizationId: 'orgA',
    }));
    await assertFails(as('rider').doc('cases/verifying1').update({
      'verification.riderOutcome': 'found', status: 'accepted_pending_clinic',
    }));
    await assertSucceeds(result('rider'));
    // Staff can record it for a rider who phoned it in.
    await assertSucceeds(as('staffA').doc('cases/verifying1').update({ 'verification.riderOutcome': 'notFound' }));
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

  // Animal Management > Add QR Tag / New Code / Remove
  // (AnimalRecordRepository.ensureQrTag, regenerateQrTag, removeQrTag).
  test("the owning organization's records staff add, replace and remove QR tags", async () => {
    const log = (eventType) => ({ animalId: 'animalA', eventType, action: eventType, timestamp: FieldValue.serverTimestamp() });
    await assertSucceeds(as('staffA').doc('animals/animalA').update({ qrTagId: 'ABCD2345', updatedAt: FieldValue.serverTimestamp() }));
    await assertSucceeds(as('staffA').collection('animals/animalA/managementLogs').add(log('qrAssigned')));
    await assertSucceeds(as('staffA').doc('animals/animalA').update({ qrTagId: 'WXYZ6789', updatedAt: FieldValue.serverTimestamp() }));
    await assertSucceeds(as('staffA').collection('animals/animalA/managementLogs').add(log('qrRegenerated')));
    await assertSucceeds(as('staffA').doc('animals/animalA').update({ qrTagId: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }));
    await assertSucceeds(as('staffA').collection('animals/animalA/managementLogs').add(log('qrRemoved')));
    for (const uid of ['carerA', 'staffB', 'stranger']) {
      await assertFails(as(uid).doc('animals/animalA').update({ qrTagId: 'ABCD2345' }));
      await assertFails(as(uid).collection('animals/animalA/managementLogs').add(log('qrAssigned')));
    }
  });
});

describe('animal records and public profiles', () => {
  test('the full record is readable only by its staff, carers, platform staff and its adopter', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/reservedA').set({ organizationId: 'orgA', adoptionStatus: 'reserved', reservedForUserId: 'adopter' });
      await db.doc('animals/adoptedA').set({ organizationId: 'orgA', adoptionStatus: 'adopted', adoptedByUserId: 'adopter' });
    });
    await assertSucceeds(as('staffA').doc('animals/animalA').get());
    await assertSucceeds(as('carerA').doc('animals/animalA').get());
    await assertSucceeds(as('admin').doc('animals/animalA').get());
    await assertFails(as('staffB').doc('animals/animalA').get());
    await assertFails(as('stranger').doc('animals/animalA').get());
    await assertFails(as('adopter').doc('animals/animalA').get());
    await assertSucceeds(as('adopter').doc('animals/reservedA').get());
    await assertSucceeds(as('adopter').doc('animals/adoptedA').get());
    await assertFails(as('stranger').doc('animals/reservedA').get());
  });

  test('staff list queries must filter on their organization', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('animals/animalB').set({ name: 'B', organizationId: 'orgB' });
      await db.doc('animals/legacy').set({ name: 'L', organizationId: '' });
    });
    // Records with no organization yet: any organization's staff, not carers.
    await assertSucceeds(as('staffA').collection('animals').where('organizationId', '==', '').get());
    await assertFails(as('carerA').collection('animals').where('organizationId', '==', '').get());
    await assertSucceeds(as('staffA').collection('animals').where('organizationId', '==', 'orgA').get());
    await assertSucceeds(as('carerA').collection('animals').where('organizationId', '==', 'orgA').get());
    await assertSucceeds(as('admin').collection('animals').get());
    await assertFails(as('staffA').collection('animals').get());
    await assertFails(as('staffB').collection('animals').where('organizationId', '==', 'orgA').get());
    await assertFails(as('stranger').collection('animals').where('adoptionStatus', '==', 'adoptable').get());
  });

  test('nobody suspends or un-suspends an account from the client', async () => {
    // Only adminSetUserDisabled (Admin SDK) writes these.
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('users/stranger').update({ disabled: true }));
    await assertFails(as('stranger').doc('users/stranger').update({ disabled: false }));
    await assertFails(as('reporter').doc('users/reporter').update({ disabled: true }));
    await assertFails(as('reporter').doc('users/reporter').update({ disabledReason: 'x' }));
    await assertSucceeds(as('reporter').doc('users/reporter').update({ firstName: 'Rey' }));
  });

    test('records for one case: allowed when scoped to the organization', async () => {
    // AnimalRecordRepository.streamRecordsForCase (Create Animal Records
    // from intake) — the unscoped form was permission-denied.
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('animals/fromCase').set({ name: 'C', organizationId: 'orgA', linkedCaseId: 'ownedA' }));
    await assertFails(as('staffA').collection('animals').where('linkedCaseId', '==', 'ownedA').get());
    await assertSucceeds(as('staffA').collection('animals')
      .where('organizationId', '==', 'orgA').where('linkedCaseId', '==', 'ownedA').get());
  });

  test('public profiles are readable by any signed-in user and written by no client', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('publicAnimals/animalA').set({ name: 'Mochi', organizationId: 'orgA', adoptionStatus: 'adoptable' }));
    await assertSucceeds(as('stranger').doc('publicAnimals/animalA').get());
    await assertSucceeds(as('stranger').collection('publicAnimals').where('organizationId', '==', 'orgA').get());
    await assertFails(env.unauthenticatedContext().firestore().doc('publicAnimals/animalA').get());
    await assertFails(as('staffA').doc('publicAnimals/animalA').update({ name: 'Renamed' }));
    await assertFails(as('admin').doc('publicAnimals/new').set({ name: 'X' }));
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

describe('rescue adoption requests (Rescue gaps 6/10)', () => {
  const agreement = {
    vetFees: true, obligations: true, pickupWindow: true, care: true, noAbandon: true, infoAccurate: true,
  };
  const request = (uid, data) => as(uid).collection('adoptions').add({
    status: 'pending', source: 'rescue_case', caseId: 'ownedA', organizationId: 'orgA',
    personal: { adopterId: uid }, agreement, ...data,
  });

  test('only the interested reporter or the willing adopter may ask, with every agreement', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/ownedA').update({
      interestedToAdopt: 'yes', willingAdopterId: 'adopter',
    }));
    await assertSucceeds(request('reporter'));
    await assertSucceeds(request('adopter'));
    await assertFails(request('stranger'));
    // Every agreement must be accepted.
    await assertFails(request('reporter', { agreement: { ...agreement, vetFees: false } }));
    await assertFails(request('reporter', { agreement: { vetFees: true, obligations: true } }));
    // The adoption form's agreements are required too.
    await assertFails(request('reporter', { agreement: { ...agreement, noAbandon: false } }));
    await assertFails(request('reporter', { agreement: { vetFees: true, obligations: true, pickupWindow: true } }));
    // It belongs to the case's organization, and can't be pre-approved.
    await assertFails(request('reporter', { organizationId: 'orgB' }));
    await assertFails(request('reporter', { status: 'approved' }));
    // The reporter must have said yes to adopting.
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/ownedA').update({ interestedToAdopt: 'no' }));
    await assertFails(request('reporter'));
  });

  test('an unowned report gets a request with no organization yet', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/pending1').update({ interestedToAdopt: 'yes' }));
    await assertSucceeds(as('reporter').collection('adoptions').add({
      status: 'pending', source: 'rescue_case', caseId: 'pending1',
      personal: { adopterId: 'reporter' }, agreement,
    }));
    // Claiming an organization for an unowned report is refused.
    await assertFails(request('reporter', { caseId: 'pending1', organizationId: 'orgA' }));
  });

  test('the adopter cannot rewrite the agreement; the reporter cannot fake a confirmation', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('adoptions/r1').set({
        status: 'pending', source: 'rescue_case', caseId: 'ownedA', organizationId: 'orgA',
        personal: { adopterId: 'adopter' }, agreement,
      });
    });
    await assertFails(as('adopter').doc('adoptions/r1').update({ agreement: { vetFees: false } }));
    await assertSucceeds(as('adopter').doc('adoptions/r1').update({ status: 'withdrawn' }));
    await assertFails(as('reporter').doc('cases/ownedA').update({
      adoptionRequest: { applicationId: 'r1', status: 'approved' },
    }));
    await assertFails(as('reporter').doc('cases/ownedA').update({ adopterPickup: { collectedAt: 1 } }));
    await assertSucceeds(as('staffA').doc('adoptions/r1').update({ status: 'approved' }));
  });
});

describe('community adoption check-ins (Adoption gap 10)', () => {
  test('staff in the area read them; the adopter answers once when asked', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('communityAdoptionCheckIns/c1').set({
      adopterId: 'adopter', status: 'scheduled', organizationIds: ['orgA'],
    }));
    await assertSucceeds(as('staffA').doc('communityAdoptionCheckIns/c1').get());
    await assertSucceeds(as('staffA').collection('communityAdoptionCheckIns').where('organizationIds', 'array-contains', 'orgA').get());
    await assertFails(as('staffB').doc('communityAdoptionCheckIns/c1').get());
    await assertFails(as('stranger').doc('communityAdoptionCheckIns/c1').get());
    // Not asked yet.
    await assertFails(as('adopter').doc('communityAdoptionCheckIns/c1').update({ status: 'submitted', note: 'Fine' }));
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('communityAdoptionCheckIns/c1').update({ status: 'requested' }));
    await assertFails(as('stranger').doc('communityAdoptionCheckIns/c1').update({ status: 'submitted', note: 'x' }));
    await assertFails(as('adopter').doc('communityAdoptionCheckIns/c1').update({ status: 'submitted', organizationIds: [] }));
    await assertSucceeds(as('adopter').doc('communityAdoptionCheckIns/c1').update({ status: 'submitted', note: 'Doing well' }));
    await assertFails(as('adopter').collection('communityAdoptionCheckIns').add({ adopterId: 'adopter', status: 'scheduled' }));
  });
});

describe('community adoption requests', () => {
  test("the reporter can't request their own report; only the two people involved read it", async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/ca1').set({
      reporterId: 'reporter', status: 'rejected', rejectionReason: 'healthyAnimalLowUrgency', organizationId: '',
    }));
    const request = (uid, data) => as(uid).collection('communityAdoptionRequests').doc('r1').set({
      caseId: 'ca1', listerId: 'reporter', adopterId: uid, status: 'pending', animalIndexes: [0], ...data,
    });
    await assertFails(request('reporter'));
    await assertFails(request('adopter', { listerId: 'stranger' }));
    await assertFails(request('adopter', { status: 'selected' }));
    await assertSucceeds(request('adopter'));

    const doc = (uid) => as(uid).doc('communityAdoptionRequests/r1');
    await assertSucceeds(doc('reporter').get());
    await assertSucceeds(doc('adopter').get());
    await assertFails(doc('stranger').get());

    const msg = (uid, senderId) => doc(uid).collection('messages').add({ senderId, text: 'Hi' });
    await assertSucceeds(msg('adopter', 'adopter'));
    await assertSucceeds(msg('reporter', 'reporter'));
    await assertFails(msg('adopter', 'reporter'));
    await assertFails(msg('stranger', 'stranger'));
    await assertFails(doc('stranger').collection('messages').get());
  });

  test('the reporter chooses, each side signs their own part, then it completes', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('communityAdoptionRequests/r2').set({
      caseId: 'ca1', listerId: 'reporter', adopterId: 'adopter', status: 'pending', animalIndexes: [0],
    }));
    const doc = (uid) => as(uid).doc('communityAdoptionRequests/r2');
    const sig = { name: 'Full Name', signedAt: firebase.firestore.FieldValue.serverTimestamp() };
    await assertFails(doc('adopter').update({ status: 'selected' }));
    await assertFails(doc('adopter').update({ adopterSignature: sig }));
    await assertSucceeds(doc('reporter').update({ status: 'selected' }));
    await assertFails(doc('adopter').update({ listerSignature: sig }));
    await assertFails(doc('adopter').update({ status: 'completed' }));
    await assertSucceeds(doc('adopter').update({ adopterSignature: sig }));
    await assertSucceeds(doc('reporter').update({ listerSignature: sig }));
    await assertFails(doc('adopter').update({ adopterId: 'stranger' }));
    await assertSucceeds(doc('adopter').update({ status: 'completed' }));
  });
});

describe('adoption audit entries (Adoption gap 7)', () => {
  test("an entry carries the application's organization so its staff see it", async () => {
    const entry = (uid, data) => as(uid).collection('auditLogs').add({
      category: 'adoptions', action: 'Application withdrawn by the adopter', actorId: uid,
      organizationId: 'orgA', targetType: 'AdoptionApplication', targetId: 'appA',
      createdAt: firebase.firestore.FieldValue.serverTimestamp(), ...data,
    });
    await assertSucceeds(entry('adopter'));
    await assertSucceeds(entry('staffA', { action: 'Interview confirmed' }));
    await assertFails(entry('adopter', { actorId: 'staffA' }));
    await assertSucceeds(as('staffA').collection('auditLogs')
      .where('category', '==', 'adoptions').where('organizationId', '==', 'orgA').get());
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
    // The fit score saved with the staff decision is staff-only.
    await assertFails(as('adopter').doc('adoptions/appA').update({ fitAtDecision: { decision: 'approved' } }));
    // Nor reset their missed-interview count.
    await assertFails(as('adopter').doc('adoptions/appA').update({ noShowCount: 0 }));
    await assertSucceeds(as('staffA').doc('adoptions/appA').update({ fitAtDecision: { decision: 'approved' } }));
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

describe('transporter applications', () => {
  const app = (uid, extra = {}) => ({
    uid, name: 'R', mobileNumber: '0917', vehicleType: 'Motorcycle', licensePlate: 'ABC123',
    licenseFrontUrl: 'https://x/front', licenseBackUrl: 'https://x/back', portraitUrl: 'https://x/p',
    status: 'pending', ...extra,
  });
  const seedApp = (uid) => env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`transporterApplications/${uid}`).set(app(uid)));

  test('applicants submit their own, always pending, never self-approved', async () => {
    await assertSucceeds(as('rider').doc('transporterApplications/rider').set(app('rider')));
    await assertFails(as('rider').doc('transporterApplications/rider2').set(app('rider2')));
    await assertFails(as('rider').doc('transporterApplications/rider').set(app('rider', { status: 'approved' })));
    await assertFails(as('rider').doc('transporterApplications/rider').set(app('rider', { reviewedBy: 'rider' })));
  });

  test('a rejected applicant can resubmit, which goes back to pending', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('transporterApplications/rider')
      .set(app('rider', { status: 'rejected', reviewedBy: 'staffA', reviewNote: 'blurry' })));
    await assertSucceeds(as('rider').doc('transporterApplications/rider').set(app('rider')));
  });

  test('ID documents are private: only the applicant and approved staff read them', async () => {
    await seedApp('rider');
    await assertSucceeds(as('rider').doc('transporterApplications/rider').get());
    await assertSucceeds(as('staffA').doc('transporterApplications/rider').get());
    await assertFails(as('rider2').doc('transporterApplications/rider').get());
    await assertFails(as('stranger').doc('transporterApplications/rider').get());
    await assertFails(as('carerA').doc('transporterApplications/rider').get());
    await assertFails(as('draftOwner').doc('transporterApplications/rider').get());
    await assertFails(as('stranger').doc('transporterApplications/rider').set(app('rider', { name: 'Hijacked' })));
  });

  test('approved staff review the application; carers and others cannot', async () => {
    await seedApp('rider');
    await assertFails(as('carerA').doc('transporterApplications/rider').update({ status: 'approved', reviewedBy: 'carerA' }));
    await assertFails(as('staffA').doc('transporterApplications/rider').update({ status: 'approved', reviewedBy: 'someoneElse' }));
    await assertFails(as('staffA').doc('transporterApplications/rider').update({ status: 'approved', reviewedBy: 'staffA', name: 'X' }));
    await assertSucceeds(as('staffA').doc('transporterApplications/rider').update({ status: 'approved', reviewedBy: 'staffA' }));
  });

  test('staff can verify an applicant transporter, and nothing else on the profile', async () => {
    await seedApp('rider');
    await assertSucceeds(as('staffA').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
    await assertSucceeds(as('staffA').doc('users/rider').update({ isVerified: false, transporterVerificationStatus: 'rejected' }));
    // Mismatched pairs and extra fields are refused.
    await assertFails(as('staffA').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'rejected' }));
    await assertFails(as('staffA').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'approved', role: 'admin' }));
  });

  test('cannot verify someone who never applied, or who is not a transporter', async () => {
    await assertFails(as('staffA').doc('users/rider2').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
    await seedApp('stranger');
    await assertFails(as('staffA').doc('users/stranger').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
  });

  test('an applicant who is no longer a transporter can still be rejected (application only)', async () => {
    await seedApp('stranger');
    // TransporterApplicationRepository.review writes only the application then.
    await assertSucceeds(as('staffA').doc('transporterApplications/stranger')
      .update({ status: 'rejected', reviewedBy: 'staffA' }));
  });

  test('carers, draft-org staff and transporters cannot verify', async () => {
    await seedApp('rider');
    await assertFails(as('carerA').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
    await assertFails(as('draftOwner').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
    await assertFails(as('rider2').doc('users/rider').update({ isVerified: true, transporterVerificationStatus: 'approved' }));
  });
});

describe('collection-group queries', () => {
  test('transporters list their own offers', async () => {
    await assertSucceeds(as('rider').collectionGroup('transportAssignments')
      .where('riderId', '==', 'rider').where('status', '==', 'pending').get());
    await assertFails(as('rider').collectionGroup('transportAssignments').get());
  });

  test("staff dashboards read their organization's records across cases; others cannot", async () => {
    await assertSucceeds(as('staffA').collectionGroup('expenses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffA').collectionGroup('expenses').get());
    await assertFails(as('stranger').collectionGroup('expenses').where('organizationId', '==', 'orgA').get());
  });
});

describe('audit log', () => {
  const entry = (actorId, extra = {}) => ({
    category: 'expenses', action: 'Expense added', actorId, organizationId: 'orgA',
    createdAt: FieldValue.serverTimestamp(), ...extra,
  });

  test('anyone signed in adds an entry about their own action only', async () => {
    await assertSucceeds(as('staffA').collection('auditLogs').add(entry('staffA')));
    await assertSucceeds(as('adopter').collection('auditLogs').add(entry('adopter', { category: 'adoptions' })));
    await assertFails(as('staffA').collection('auditLogs').add(entry('ownerA')));
    await assertFails(as('staffA').collection('auditLogs').add(entry('staffA', { createdAt: new Date(2020, 0, 1) })));
    await assertFails(as('staffA').collection('auditLogs').add(entry('staffA', { unexpected: true })));
  });

  test('entries cannot be edited or deleted, even by staff', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('auditLogs/a1').set(entry('staffA')));
    await assertFails(as('staffA').doc('auditLogs/a1').update({ action: 'Nothing happened' }));
    await assertFails(as('ownerA').doc('auditLogs/a1').delete());
    await assertFails(as('admin').doc('auditLogs/a1').delete());
  });

  test("only the organization's staff read its entries", async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('auditLogs/a2').set(entry('staffA')));
    await assertSucceeds(as('staffA').doc('auditLogs/a2').get());
    await assertSucceeds(as('admin').doc('auditLogs/a2').get());
    await assertFails(as('staffB').doc('auditLogs/a2').get());
    await assertFails(as('carerA').doc('auditLogs/a2').get());
    await assertFails(as('stranger').doc('auditLogs/a2').get());
    await assertSucceeds(as('staffA').collection('auditLogs').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffA').collection('auditLogs').get());
  });
});

describe('care updates', () => {
  const update = (authorId, extra = {}) => ({
    type: 'observation', note: 'Eating well', authorId, mediaUrls: [], mediaTypes: [],
    createdAt: FieldValue.serverTimestamp(), ...extra,
  });

  test("carers and staff of the animal's org add their own updates", async () => {
    await assertSucceeds(as('carerA').collection('animals/animalA/careUpdates').add(update('carerA')));
    await assertSucceeds(as('staffA').collection('animals/animalA/careUpdates').add(update('staffA')));
    await assertFails(as('carerA').collection('animals/animalA/careUpdates').add(update('staffA')));
    await assertFails(as('carerA').collection('animals/animalA/careUpdates').add(update('carerA', { note: '' })));
    await assertFails(as('staffB').collection('animals/animalA/careUpdates').add(update('staffB')));
    await assertFails(as('stranger').collection('animals/animalA/careUpdates').add(update('stranger')));
  });

  test('nobody rewrites an update; staff may remove one', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('animals/animalA/careUpdates/u1').set(update('carerA')));
    await assertFails(as('carerA').doc('animals/animalA/careUpdates/u1').update({ note: 'Changed' }));
    await assertFails(as('staffA').doc('animals/animalA/careUpdates/u1').update({ note: 'Changed' }));
    await assertFails(as('carerA').doc('animals/animalA/careUpdates/u1').delete());
    await assertSucceeds(as('staffA').doc('animals/animalA/careUpdates/u1').delete());
  });

  test('staff read medication orders and doses across animals for missed-dose alerts', async () => {
    await assertSucceeds(as('staffA').collectionGroup('medications')
      .where('organizationId', '==', 'orgA').where('active', '==', true).get());
    await assertSucceeds(as('staffA').collectionGroup('medicationDoses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffA').collectionGroup('medicationDoses').get());
    await assertFails(as('stranger').collectionGroup('medicationDoses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('carerA').collectionGroup('medications').where('organizationId', '==', 'orgB').get());
  });
});

describe('general expenses', () => {
  const expense = (orgId, extra = {}) => ({
    organizationId: orgId, title: 'Electricity', category: 'Bills and Utilities', amount: 1500, fundings: [], ...extra,
  });

  test("only the organization's financial admins add and read them", async () => {
    await assertSucceeds(as('ownerA').collection('orgExpenses').add(expense('orgA')));
    await assertFails(as('staffA').collection('orgExpenses').add(expense('orgA')));
    await assertFails(as('carerA').collection('orgExpenses').add(expense('orgA')));
    await assertFails(as('ownerA').collection('orgExpenses').add(expense('orgB')));
    await assertFails(as('ownerA').collection('orgExpenses').add(expense('orgA', { amount: 0 })));
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('orgExpenses/x1').set(expense('orgA')));
    await assertSucceeds(as('ownerA').doc('orgExpenses/x1').get());
    await assertFails(as('staffA').doc('orgExpenses/x1').get());
    await assertFails(as('staffB').doc('orgExpenses/x1').get());
  });

  test('an expense cannot be moved to another organization', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('orgExpenses/x2').set(expense('orgA')));
    await assertSucceeds(as('ownerA').doc('orgExpenses/x2').update({ amount: 1800 }));
    await assertFails(as('ownerA').doc('orgExpenses/x2').update({ organizationId: 'orgB' }));
  });
});

describe('donation gaps: approvals, stock and backend-only pledges', () => {
  const pending = (extra = {}) => ({
    organizationId: 'orgA', title: 'Surgery', category: 'Procedure', amount: 25000, fundings: [],
    approvalStatus: 'pending', approvalRequestedBy: 'ownerA', ...extra,
  });
  const line = { source: 'Fundraiser', amount: 1000 };

  async function secondAdmin() {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('users/admin2A').set({ role: 'organization_member', organizationId: 'orgA' });
      await db.doc('organizations/orgA/members/admin2A').set({ role: 'admin', status: 'active' });
    });
  }

  test('an expense needing approval is saved pending with no funding', async () => {
    await assertSucceeds(as('ownerA').collection('orgExpenses').add(pending()));
    await assertFails(as('ownerA').collection('orgExpenses').add(pending({ fundings: [line] })));
    await assertFails(as('ownerA').collection('orgExpenses').add(pending({ approvalStatus: 'approved' })));
    await assertSucceeds(as('ownerA').doc('cases/ownedA/expenses/p1').set(pending()));
    await assertFails(as('ownerA').doc('cases/ownedA/expenses/p2').set(pending({ approvalStatus: 'approved' })));
  });

  test('a different financial admin approves; then it can be funded', async () => {
    await secondAdmin();
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('orgExpenses/ap1').set(pending()));
    const approve = (uid) => ({ approvalStatus: 'approved', approvedBy: uid, approvedAmount: 25000 });
    // No funding and no un-flagging while it waits.
    await assertFails(as('ownerA').doc('orgExpenses/ap1').update({ fundings: [line] }));
    await assertFails(as('ownerA').doc('orgExpenses/ap1').update({ approvalStatus: null }));
    // The requester can't approve their own; a staff member can't approve at all.
    await assertFails(as('ownerA').doc('orgExpenses/ap1').update(approve('ownerA')));
    await assertFails(as('staffA').doc('orgExpenses/ap1').update(approve('staffA')));
    // Approval must name the approver and not change the money.
    await assertFails(as('admin2A').doc('orgExpenses/ap1').update(approve('ownerA')));
    await assertFails(as('admin2A').doc('orgExpenses/ap1').update({ ...approve('admin2A'), amount: 30000 }));
    await assertSucceeds(as('admin2A').doc('orgExpenses/ap1').update(approve('admin2A')));
    await assertSucceeds(as('ownerA').doc('orgExpenses/ap1').update({ fundings: [line] }));
  });

  test('case expenses follow the same approval rule', async () => {
    await secondAdmin();
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('cases/ownedA/expenses/ap2').set(pending()));
    await assertFails(as('ownerA').doc('cases/ownedA/expenses/ap2').update({ fundings: [line] }));
    await assertSucceeds(as('admin2A').doc('cases/ownedA/expenses/ap2')
        .update({ approvalStatus: 'approved', approvedBy: 'admin2A' }));
    // Ordinary expenses are unaffected.
    await assertSucceeds(as('ownerA').doc('cases/ownedA/expenses/e1').update({ amount: 600, fundings: [line] }));
  });

  test("stock belongs to the organization's staff and carers; movements are append-only", async () => {
    const item = { name: 'Dry food', category: 'Food & Water', unit: 'kg', quantity: 10 };
    await assertSucceeds(as('staffA').doc('organizations/orgA/stock/s1').set(item));
    await assertSucceeds(as('carerA').doc('organizations/orgA/stock/s1').update({ quantity: 8 }));
    await assertFails(as('carerA').doc('organizations/orgA/stock/s1').update({ quantity: -1 }));
    await assertFails(as('staffB').doc('organizations/orgA/stock/s1').get());
    await assertFails(as('stranger').doc('organizations/orgA/stock/s2').set(item));
    await assertFails(as('staffA').doc('organizations/orgA/stock/s1').delete());
    const move = { itemId: 's1', change: -2, kind: 'used', byUid: 'carerA' };
    await assertSucceeds(as('carerA').doc('organizations/orgA/stockMovements/m1').set(move));
    await assertFails(as('staffA').doc('organizations/orgA/stockMovements/m2').set(move));
    await assertFails(as('carerA').doc('organizations/orgA/stockMovements/m1').update({ change: -1 }));
    await assertFails(as('stranger').doc('organizations/orgA/stockMovements/m1').get());
  });

  test('in-kind pledges are created only by the backend', async () => {
    const pledge = { userId: 'adopter', type: 'inkind', amount: 0, status: 'inprogress', campaignId: 'c1' };
    await assertFails(as('adopter').collection('donations').add(pledge));
    await assertFails(as('adopter').doc('users/adopter/history/h1').set(pledge));
    // The donor can still cancel their own pledge.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('donations/p1').set(pledge);
    });
    await assertSucceeds(as('adopter').doc('donations/p1').update({ status: 'cancelled' }));
  });
});

describe('refund requests', () => {
  const ask = (extra = {}) => ({
    refundRequest: {
      status: 'requested', reason: 'duplicate', details: 'Paid twice', termsVersion: '2026-11-18',
      requestedAt: FieldValue.serverTimestamp(), termsAcceptedAt: FieldValue.serverTimestamp(), ...extra,
    },
  });
  async function seedDonation(id, data) {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`donations/${id}`).set({
      userId: 'adopter', type: 'donation', amount: 500, status: 'paid', organizationId: 'orgA',
      timestamp: firebase.firestore.Timestamp.now(), ...data,
    }));
  }

  test('the donor asks once, with a listed reason, after accepting the terms', async () => {
    await seedDonation('d1', {});
    await assertFails(as('stranger').doc('donations/d1').update(ask()));
    await assertFails(as('adopter').doc('donations/d1').update(ask({ reason: 'changed_mind' })));
    await assertFails(as('adopter').doc('donations/d1').update(ask({ termsVersion: '' })));
    await assertFails(as('adopter').doc('donations/d1').update(ask({ status: 'approved' })));
    await assertFails(as('adopter').doc('donations/d1').update({ ...ask(), amount: 1 }));
    await assertSucceeds(as('adopter').doc('donations/d1').update(ask()));
    // Only once, and the donor can't change the decision.
    await assertFails(as('adopter').doc('donations/d1').update(ask({ reason: 'wrong_amount' })));
    await assertFails(as('adopter').doc('donations/d1').update({ 'refundRequest.status': 'refunded' }));
  });

  test('only within the time allowed, and not for in-kind or refunded records', async () => {
    const old = firebase.firestore.Timestamp.fromMillis(Date.now() - 10 * 86400000);
    await seedDonation('d2', { timestamp: old });
    await assertFails(as('adopter').doc('donations/d2').update(ask()));
    await assertSucceeds(as('adopter').doc('donations/d2').update(ask({ reason: 'unauthorized' })));
    await seedDonation('d3', { type: 'inkind', amount: 0 });
    await assertFails(as('adopter').doc('donations/d3').update(ask()));
    await seedDonation('d4', { status: 'reversed' });
    await assertFails(as('adopter').doc('donations/d4').update(ask()));
  });
});

describe('event attendance', () => {
  const seedEvent = (startAt) => env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('events/ev1').set({ organizationId: 'orgA', status: 'published', goingCount: 1, startAt });
    await db.doc('events/ev1/registrations/stranger').set({ uid: 'stranger', eventId: 'ev1', participantName: 'S' });
  });
  const mark = (by) => ({ attended: true, attendanceMarkedAt: FieldValue.serverTimestamp(), attendanceMarkedBy: by });

  test('organization staff mark attendance once the event has started', async () => {
    await seedEvent(new Date(Date.now() - 3600 * 1000));
    await assertSucceeds(as('staffA').doc('events/ev1/registrations/stranger').update(mark('staffA')));
    await assertFails(as('staffA').doc('events/ev1/registrations/stranger').update(mark('ownerA')));
    await assertFails(as('stranger').doc('events/ev1/registrations/stranger').update(mark('stranger')));
    await assertFails(as('staffB').doc('events/ev1/registrations/stranger').update(mark('staffB')));
    await assertFails(as('staffA').doc('events/ev1/registrations/stranger').update({ participantName: 'Changed' }));
  });

  test('attendance cannot be taken before the event starts', async () => {
    await seedEvent(new Date(Date.now() + 24 * 3600 * 1000));
    await assertFails(as('staffA').doc('events/ev1/registrations/stranger').update(mark('staffA')));
  });

  test('a new sign-up cannot arrive already marked attended', async () => {
    await seedEvent(new Date(Date.now() + 24 * 3600 * 1000));
    const signUp = (extra) => {
      const db = as('adopter');
      return db.batch()
        .update(db.doc('events/ev1'), { goingCount: 2 })
        .set(db.doc('events/ev1/registrations/adopter'), { uid: 'adopter', eventId: 'ev1', ...extra })
        .commit();
    };
    await assertFails(signUp({ attended: true }));
    await assertSucceeds(signUp({}));
  });
});

describe('user subcollections', () => {
  test("a user's own subcollections are theirs alone", async () => {
    await assertSucceeds(as('adopter').doc('users/adopter/favorites/a1').set({ animalId: 'a1' }));
    await assertSucceeds(as('adopter').doc('users/adopter/favorites/a1').get());
    await assertFails(as('stranger').doc('users/adopter/favorites/a1').get());
    await assertFails(as('stranger').doc('users/adopter/favorites/x').set({ animalId: 'x' }));
    await assertFails(as('stranger').doc('users/adopter/fcmTokens/t').set({ token: 'x' }));
  });

  test('notifications come from the backend; the user marks them read', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('users/adopter/notifications/n1').set({ title: 'Hi', isRead: false }));
    await assertFails(as('stranger').doc('users/adopter/notifications/n2').set({ title: 'Phish' }));
    await assertFails(as('adopter').doc('users/adopter/notifications/n2').set({ title: 'Self' }));
    await assertFails(as('stranger').doc('users/adopter/notifications/n1').get());
    await assertSucceeds(as('adopter').doc('users/adopter/notifications/n1').update({ isRead: true }));
    await assertFails(as('adopter').doc('users/adopter/notifications/n1').update({ title: 'Changed' }));
  });

  test("the event's staff mark attendance on the volunteer's copy", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('events/ev2').set({ organizationId: 'orgA', status: 'published', goingCount: 1 });
      await db.doc('users/adopter/volunteerRegistrations/ev2').set({ uid: 'adopter', title: 'Clean-up' });
    });
    const mark = { attended: true, attendanceMarkedAt: FieldValue.serverTimestamp(), attendanceMarkedBy: 'staffA' };
    await assertSucceeds(as('staffA').doc('users/adopter/volunteerRegistrations/ev2').set(mark, { merge: true }));
    await assertFails(as('staffB').doc('users/adopter/volunteerRegistrations/ev2').set(mark, { merge: true }));
    await assertFails(as('staffA').doc('users/adopter/volunteerRegistrations/ev2').update({ title: 'Changed' }));
    await assertFails(as('stranger').doc('users/adopter/volunteerRegistrations/ev2').get());
  });

  test('collar tag copies: the owner and staff', async () => {
    await assertSucceeds(as('adopter').doc('users/adopter/collarTags/t1').set({ status: 'active' }));
    await assertSucceeds(as('staffA').doc('users/adopter/collarTags/t1').set({ qrEnabled: false }, { merge: true }));
    await assertFails(as('stranger').doc('users/adopter/collarTags/t1').get());
  });
});

describe('volunteer stats', () => {
  test('only the server writes volunteer badges', async () => {
    const stats = { attendedCount: 25, badges: ['champion'] };
    await assertFails(as('stranger').doc('users/stranger').update({ volunteerStats: stats }));
    await assertFails(as('newbie').doc('users/newbie').set({ role: 'general', volunteerStats: stats }));
    await assertSucceeds(as('newbie').doc('users/newbie').set({ role: 'general' }));
  });
});

describe('dashboard and analytics gaps: care rounds, alert claims, summaries, illnesses', () => {
  test("care setup: the org's admins write it; staff and carers read it", async () => {
    const setup = { areas: [{ id: 'main', label: 'Main' }], tasks: [], shifts: [], roster: {} };
    await assertSucceeds(as('ownerA').doc('organizations/orgA/settings/care').set(setup));
    await assertFails(as('staffA').doc('organizations/orgA/settings/care').set(setup));
    await assertFails(as('carerA').doc('organizations/orgA/settings/care').set(setup));
    await assertSucceeds(as('staffA').doc('organizations/orgA/settings/care').get());
    await assertSucceeds(as('carerA').doc('organizations/orgA/settings/care').get());
    // Carers still can't read the other settings (budget, approvals).
    await assertFails(as('carerA').doc('organizations/orgA/settings/shelter').get());
    await assertFails(as('staffB').doc('organizations/orgA/settings/care').get());
  });

  test('care rounds: staff and carers of the org tick; others cannot', async () => {
    const tick = { organizationId: 'orgA', done: { main__water: { byUid: 'carerA', byName: 'C' } } };
    await assertSucceeds(as('carerA').doc('organizations/orgA/careRounds/2026-11-17').set(tick));
    await assertSucceeds(as('staffA').doc('organizations/orgA/careRounds/2026-11-17').update({ 'done.main__clean': { byUid: 'staffA' } }));
    await assertSucceeds(as('carerA').doc('organizations/orgA/careRounds/2026-11-17').get());
    await assertFails(as('staffB').doc('organizations/orgA/careRounds/2026-11-17').get());
    await assertFails(as('staffB').doc('organizations/orgA/careRounds/2026-11-18').set({ ...tick }));
    await assertFails(as('carerA').doc('organizations/orgA/careRounds/2026-11-18').set({ ...tick, organizationId: 'orgB' }));
    await assertFails(as('stranger').doc('organizations/orgA/careRounds/2026-11-18').set(tick));
    await assertFails(as('staffA').doc('organizations/orgA/careRounds/2026-11-17').delete());
  });

  test('alert claims: staff claim for themselves; only the claimer or an admin releases', async () => {
    const claim = (uid) => ({ byUid: uid, byName: uid, organizationId: 'orgA' });
    await assertSucceeds(as('staffA').doc('organizations/orgA/alertClaims/rescue:review').set(claim('staffA')));
    await assertFails(as('staffA').doc('organizations/orgA/alertClaims/x').set(claim('ownerA')));
    await assertFails(as('carerA').doc('organizations/orgA/alertClaims/x').set(claim('carerA')));
    await assertFails(as('staffB').doc('organizations/orgA/alertClaims/x').set({ ...claim('staffB') }));
    await assertFails(as('staffB').doc('organizations/orgA/alertClaims/rescue:review').get());
    await assertSucceeds(as('ownerA').doc('organizations/orgA/alertClaims/rescue:review').get());
    // Taking over is allowed (claims can go stale); releasing someone else's is admins only.
    await assertSucceeds(as('ownerA').doc('organizations/orgA/alertClaims/rescue:review').set(claim('ownerA')));
    await assertFails(as('staffA').doc('organizations/orgA/alertClaims/rescue:review').delete());
    await assertSucceeds(as('ownerA').doc('organizations/orgA/alertClaims/rescue:review').delete());
    await assertSucceeds(as('staffA').doc('organizations/orgA/alertClaims/mine').set(claim('staffA')));
    await assertSucceeds(as('staffA').doc('organizations/orgA/alertClaims/mine').delete());
  });

  test('monthly summaries are read by the org staff and written by the backend only', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('organizations/orgA/analyticsSummaries/2026-10').set({ month: '2026-10', reports: 3 }));
    await assertSucceeds(as('staffA').doc('organizations/orgA/analyticsSummaries/2026-10').get());
    await assertSucceeds(as('staffA').collection('organizations/orgA/analyticsSummaries').orderBy('month', 'desc').limit(12).get());
    await assertFails(as('staffB').doc('organizations/orgA/analyticsSummaries/2026-10').get());
    await assertFails(as('carerA').doc('organizations/orgA/analyticsSummaries/2026-10').get());
    await assertFails(as('ownerA').doc('organizations/orgA/analyticsSummaries/2026-11').set({ month: '2026-11' }));
  });

  test("illness log: the animal's staff write it; reads stay inside the org", async () => {
    const illness = { condition: 'Kennel cough', contagious: true, organizationId: 'orgA' };
    await assertSucceeds(as('staffA').doc('animals/animalA/illnesses/i1').set(illness));
    await assertFails(as('carerA').doc('animals/animalA/illnesses/i2').set(illness));
    await assertFails(as('staffB').doc('animals/animalA/illnesses/i2').set(illness));
    await assertSucceeds(as('carerA').doc('animals/animalA/illnesses/i1').get());
    await assertSucceeds(as('staffA').collectionGroup('illnesses').where('organizationId', '==', 'orgA').get());
    await assertFails(as('staffB').collectionGroup('illnesses').where('organizationId', '==', 'orgA').get());
  });

  test('a euthanasia second review is saved on the record by its staff', async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('animals/animalA').update({
      adoptionStatus: 'deceased', deceasedCause: 'Euthanasia', deceasedByUid: 'staffA',
    }));
    const review = { euthanasiaReview: { reviewerUid: 'ownerA', alternativesConsidered: 'Referral', agrees: true } };
    await assertSucceeds(as('ownerA').doc('animals/animalA').update(review));
    await assertFails(as('staffB').doc('animals/animalA').update(review));
  });
});

// Collar tags and their scan chats: a tag opens for anyone with its id, but
// only its owner lists or edits it; staff approve QR codes. Each finder of
// a lost pet gets a private chat with the owner.
describe('collar tags and scan chats', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('collarTags/tag1').set({ ownerId: 'reporter', name: 'Bantay', ownerMobile: '0917', status: 'lost', qrEnabled: true });
      await db.doc('collarTags/tag2').set({ ownerId: 'stranger', name: 'Mingming', status: 'active' });
      await db.doc('rescueSessions/s1').set({ tagId: 'tag1', ownerId: 'reporter', finderId: 'adopter', status: 'active', chatEnabledByOwner: true });
      await db.doc('rescueSessions/s2').set({ tagId: 'tag1', ownerId: 'reporter', finderId: 'adopter', status: 'active', chatEnabledByOwner: false });
      await db.doc('rescueSessions/legacy').set({ tagId: 'tag1', status: 'active', chatEnabledByOwner: true });
    });
  });

  test('anyone signed in opens a tag by its id, but only owners list theirs', async () => {
    await assertSucceeds(as('adopter').doc('collarTags/tag1').get());
    await assertSucceeds(as('reporter').collection('collarTags').where('ownerId', '==', 'reporter').get());
    await assertFails(as('adopter').collection('collarTags').where('ownerId', '==', 'reporter').get());
    await assertFails(as('adopter').collection('collarTags').get());
    await assertSucceeds(as('admin').collection('collarTags').get());
  });

  test("nobody edits or deletes someone else's tag", async () => {
    await assertFails(as('adopter').doc('collarTags/tag1').update({ ownerMobile: '000' }));
    await assertFails(as('adopter').doc('collarTags/tag1').update({ ownerId: 'adopter' }));
    await assertFails(as('adopter').doc('collarTags/tag1').delete());
  });

  test('owners edit and mark their own tag lost or found, but not approve its QR', async () => {
    await assertSucceeds(as('reporter').doc('collarTags/tag1').update({ status: 'active', linkedAlertId: FieldValue.delete() }));
    await assertFails(as('reporter').doc('collarTags/tag1').update({ qrEnabled: false }));
    await assertFails(as('reporter').doc('collarTags/tag1').update({ ownerId: 'adopter' }));
    await assertSucceeds(as('reporter').doc('collarTags/tag1').delete());
  });

  test('a new tag is created by its owner, without staff fields', async () => {
    await assertSucceeds(as('adopter').doc('collarTags/new1').set({ ownerId: 'adopter', name: 'Brownie' }));
    await assertFails(as('adopter').doc('collarTags/new2').set({ ownerId: 'reporter', name: 'Brownie' }));
    await assertFails(as('adopter').doc('collarTags/new3').set({ ownerId: 'adopter', qrEnabled: true }));
  });

  test('staff approve QR codes and nothing else', async () => {
    await assertSucceeds(as('admin').doc('collarTags/tag2').update({ qrEnabled: true }));
    await assertFails(as('admin').doc('collarTags/tag2').update({ ownerMobile: '000' }));
  });

  test("only the chat's owner and finder read it", async () => {
    await assertSucceeds(as('reporter').doc('rescueSessions/s1').get());
    await assertSucceeds(as('adopter').doc('rescueSessions/s1').get());
    await assertFails(as('stranger').doc('rescueSessions/s1').get());
    await assertSucceeds(as('adopter').collection('rescueSessions/s1/messages').get());
    await assertFails(as('stranger').collection('rescueSessions/s1/messages').get());
    await assertSucceeds(as('reporter').collection('rescueSessions').where('tagId', '==', 'tag1').where('ownerId', '==', 'reporter').get());
    await assertFails(as('stranger').collection('rescueSessions').where('tagId', '==', 'tag1').get());
  });

  test('the owner enables or closes the chat; the finder cannot', async () => {
    await assertSucceeds(as('reporter').doc('rescueSessions/s2').update({ chatEnabledByOwner: true }));
    await assertFails(as('adopter').doc('rescueSessions/s2').update({ chatEnabledByOwner: true }));
    await assertFails(as('adopter').doc('rescueSessions/s1').update({ status: 'resolved' }));
    await assertSucceeds(as('reporter').doc('rescueSessions/s1').update({ status: 'resolved' }));
  });

  test('each side posts as itself, only once the owner enabled the chat', async () => {
    const msg = (uid, sender, over = {}) => ({ sender, senderId: uid, text: 'Hi', sentAt: new Date(), ...over });
    await assertSucceeds(as('adopter').collection('rescueSessions/s1/messages').add(msg('adopter', 'finder')));
    await assertSucceeds(as('reporter').collection('rescueSessions/s1/messages').add(msg('reporter', 'owner')));
    await assertFails(as('adopter').collection('rescueSessions/s1/messages').add(msg('adopter', 'owner')));
    await assertFails(as('stranger').collection('rescueSessions/s1/messages').add(msg('stranger', 'finder')));
    await assertFails(as('adopter').collection('rescueSessions/s1/messages').add(msg('reporter', 'finder')));
    await assertFails(as('adopter').collection('rescueSessions/s2/messages').add(msg('adopter', 'finder')));
  });

  test('chats from before they were per finder keep working', async () => {
    await assertSucceeds(as('stranger').doc('rescueSessions/legacy').get());
    await assertSucceeds(as('stranger').collection('rescueSessions/legacy/messages').add({ sender: 'finder', text: 'Found him', sentAt: new Date() }));
    await assertSucceeds(as('reporter').doc('rescueSessions/legacy').update({ status: 'resolved' }));
    await assertFails(as('stranger').doc('rescueSessions/legacy').update({ status: 'resolved' }));
  });
});
