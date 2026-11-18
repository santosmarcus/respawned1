// Account removal and suspension.
//
// deleteMyAccount: the signed-in user deletes their own account.
// adminDeleteUser / adminSetUserDisabled: a system admin (users/{uid}.role
// 'system_admin') removes or disables another account from the console's
// Users directory.
//
// Removing an account deletes its profile data from Firestore and its
// Firebase Auth account, server-side (a client can't delete its own
// membership docs or another collection's records, and user.delete() needs a
// fresh sign-in). Removed: users/{uid} (with its subcollections, e.g. saved
// clinics), the account's organization membership, its volunteer/transporter
// applications, its pending organization invitations, any draft
// organization it owns, and the Auth account.
//
// Kept, de-identified: rescue reports the user filed (the animal's case
// history belongs to the rescue), donations and adoption records (finance and
// audit trails). Their name/phone on reported cases is replaced.
//
// Blocked (see account_deletion_rules.js): owners of a submitted or approved
// organization, an organization's only Admin, and transporters with an
// active offer.
//
// Disabling blocks sign-in (Auth `disabled`, refresh tokens revoked) and
// marks users/{uid}.disabled so an open app signs the person out at once.
// Nothing is deleted; enabling restores access.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {deletionBlocker} = require('./account_deletion_rules');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue} = admin.firestore;

const UID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
// Accounts the console can't disable or remove (set in the Firebase console).
const PROTECTED_ROLES = ['system_admin', 'admin', 'ngo_staff'];

async function deleteQuery(query) {
  const snap = await query.get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    for (const d of snap.docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}

async function requireSystemAdmin(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in again.');
  const me = await db.collection('users').doc(uid).get();
  if (!me.exists || me.get('role') !== 'system_admin') {
    throw new HttpsError('permission-denied', 'Only a system admin can do this.');
  }
  return uid;
}

async function targetFor(request, actorUid) {
  const uid = typeof (request.data || {}).uid === 'string' ? request.data.uid : '';
  if (!UID_PATTERN.test(uid)) throw new HttpsError('invalid-argument', 'A user is required.');
  if (uid === actorUid) throw new HttpsError('failed-precondition', 'You can\'t do this to your own account.');
  const snap = await db.collection('users').doc(uid).get();
  const role = snap.exists ? snap.get('role') : '';
  if (PROTECTED_ROLES.includes(role)) {
    throw new HttpsError('failed-precondition', 'Admin accounts are managed in the Firebase console.');
  }
  return {uid, snap};
}

/** Why [uid] can't be removed yet, or null. */
async function blockerFor(uid, user, subject) {
  const orgId = typeof user.organizationId === 'string' ? user.organizationId : '';
  const owned = await db.collection('organizations').where('ownerId', '==', uid).get();
  const ownedOrgs = owned.docs.map((d) => ({
    id: d.id, name: d.get('name') || '', status: d.get('verificationStatus') || 'draft',
  }));
  let isOrgAdmin = false;
  let activeAdminCount = 0;
  if (orgId) {
    const members = await db.collection('organizations').doc(orgId).collection('members').get();
    const active = members.docs.filter((m) => (m.get('status') || 'active') === 'active');
    const me = active.find((m) => m.id === uid);
    isOrgAdmin = !!me && me.get('role') === 'admin';
    activeAdminCount = active.filter((m) => m.get('role') === 'admin').length;
  }
  const transportStatus = user.transportStatus && typeof user.transportStatus.status === 'string' ?
    user.transportStatus.status : null;
  return {
    blocker: deletionBlocker({ownedOrgs, isOrgAdmin, activeAdminCount, transportStatus, subject}),
    orgId,
    ownedOrgs,
  };
}

/** Removes [uid]'s data and Auth account (see the file comment). */
async function removeAccount(uid, {subject, actorUid}) {
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};
  const {blocker, orgId, ownedOrgs} = await blockerFor(uid, user, subject);
  if (blocker) throw new HttpsError('failed-precondition', blocker);

  let authUser = null;
  try {
    authUser = await admin.auth().getUser(uid);
  } catch (_) {
    // Already gone from Auth; still clean up Firestore.
  }

  if (orgId) {
    await db.collection('organizations').doc(orgId).collection('members').doc(uid).delete();
    await db.collection('auditLogs').add({
      category: 'organizationStaff',
      action: actorUid === uid ? 'Account deleted' : 'Account removed by a system admin',
      actorId: actorUid,
      organizationId: orgId,
      targetType: 'OrgMember',
      targetId: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  for (const o of ownedOrgs.filter((x) => x.status === 'draft')) {
    await db.recursiveDelete(db.collection('organizations').doc(o.id));
  }
  for (const col of ['volunteerApplications', 'transporterApplications']) {
    await db.collection(col).doc(uid).delete();
  }
  const email = ((authUser && authUser.email) || user.email || '').toLowerCase();
  const phone = (authUser && authUser.phoneNumber) || '';
  if (email) {
    await deleteQuery(db.collection('organizationInvitations')
        .where('normalizedEmail', '==', email).where('status', '==', 'pending'));
  }
  if (phone) {
    await deleteQuery(db.collection('organizationInvitations')
        .where('normalizedPhone', '==', phone).where('status', '==', 'pending'));
  }

  // De-identify reports they filed; the rescue record stays.
  const reported = await db.collection('cases').where('reporterId', '==', uid).get();
  for (let i = 0; i < reported.docs.length; i += 400) {
    const batch = db.batch();
    for (const d of reported.docs.slice(i, i + 400)) {
      batch.update(d.ref, {
        reporterName: 'Deleted user',
        reporterPhone: FieldValue.delete(),
        reporterDeleted: true,
      });
    }
    await batch.commit();
  }

  await db.recursiveDelete(userRef);
  if (authUser) await admin.auth().deleteUser(uid);
}

exports.deleteMyAccount = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in again.');
  if ((request.data || {}).confirm !== 'DELETE') {
    throw new HttpsError('invalid-argument', 'Confirm by typing DELETE.');
  }
  await removeAccount(uid, {subject: 'self', actorUid: uid});
  return {deleted: true};
});

exports.adminDeleteUser = onCall(async (request) => {
  const actorUid = await requireSystemAdmin(request);
  const {uid} = await targetFor(request, actorUid);
  await removeAccount(uid, {subject: 'other', actorUid});
  return {deleted: true};
});

exports.adminSetUserDisabled = onCall(async (request) => {
  const actorUid = await requireSystemAdmin(request);
  const {uid, snap} = await targetFor(request, actorUid);
  const disabled = (request.data || {}).disabled === true;
  const reason = typeof request.data.reason === 'string' ? request.data.reason.trim().slice(0, 300) : '';
  try {
    await admin.auth().updateUser(uid, {disabled});
    if (disabled) await admin.auth().revokeRefreshTokens(uid);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'This account no longer exists.');
    }
    throw e;
  }
  if (snap.exists) {
    await snap.ref.update(disabled ? {
      disabled: true,
      disabledAt: FieldValue.serverTimestamp(),
      disabledBy: actorUid,
      disabledReason: reason || FieldValue.delete(),
    } : {
      disabled: FieldValue.delete(),
      disabledAt: FieldValue.delete(),
      disabledBy: FieldValue.delete(),
      disabledReason: FieldValue.delete(),
    });
  }
  return {disabled};
});
