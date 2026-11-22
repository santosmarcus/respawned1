// Member access: an organization Admin sets whether a member is an Admin or
// Staff, and which permissions a Staff member has (a preset, or ticked one
// by one). The only writer of members/{uid}.role, .permissions and .preset
// for existing members: firestore.rules lets no client write the last two,
// so the last-Admin check and the audit entry can't be skipped.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {requireOrgPermission, planAccessChange} = require('./org_access');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue} = admin.firestore;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

exports.setMemberAccess = onCall(async (request) => {
  const d = request.data || {};
  const organizationId = typeof d.organizationId === 'string' ? d.organizationId : '';
  const memberUid = typeof d.memberUid === 'string' ? d.memberUid : '';
  if (!ID_PATTERN.test(organizationId) || !ID_PATTERN.test(memberUid)) {
    throw new HttpsError('invalid-argument', 'organizationId and memberUid are required.');
  }
  const actor = await requireOrgPermission(db, request, {
    organizationId,
    adminOnly: true,
    message: 'Only an organization Admin can change what members can do.',
  });

  const orgRef = db.collection('organizations').doc(organizationId);
  const memberRef = orgRef.collection('members').doc(memberUid);
  const result = await db.runTransaction(async (tx) => {
    const [org, member, members] = await Promise.all([
      tx.get(orgRef),
      tx.get(memberRef),
      tx.get(orgRef.collection('members')),
    ]);
    const plan = planAccessChange({
      ownerId: org.exists ? org.get('ownerId') : null,
      memberUid,
      member: member.exists ? member.data() : null,
      members: new Map(members.docs.map((m) => [m.id, m.data()])),
      role: d.role,
      permissions: d.permissions,
      org: org.exists ? org.data() : null,
    });
    if (plan.error) throw new HttpsError('failed-precondition', plan.error);
    const {before, after} = plan;
    const now = FieldValue.serverTimestamp();
    tx.update(memberRef, {
      role: after.role,
      permissions: after.role === 'admin' ? FieldValue.delete() : after.permissions,
      preset: after.role === 'admin' ? FieldValue.delete() : after.preset,
      accessUpdatedBy: actor.uid,
      accessUpdatedAt: now,
      updatedAt: now,
      // Replaced by the facebookPublish permission.
      facebookPublisher: FieldValue.delete(),
      facebookPublisherGrantedBy: FieldValue.delete(),
      facebookPublisherGrantedAt: FieldValue.delete(),
    });
    tx.set(db.collection('auditLogs').doc(), {
      category: 'organizationStaff',
      action: 'Staff access changed',
      actorId: actor.uid,
      actorName: actor.name,
      actorRole: 'admin',
      organizationId,
      targetType: 'Member',
      targetId: memberUid,
      oldValues: before,
      newValues: after,
      metadata: {memberName: (member.get('displayName') || member.get('email') || null)},
      createdAt: now,
    });
    return after;
  });
  return result;
});
