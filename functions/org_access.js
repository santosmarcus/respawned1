// Organization access: who may do what in an organization.
//
// Two roles. Admins (and the organization's owner) can do everything. Staff
// can do what their `permissions` allow (organizations/{orgId}/members/{uid}),
// set by an Admin through setMemberAccess (functions/org_members.js) from a
// preset or ticked one by one. The permission and preset lists live in
// org_permissions.json, shared with the app and copied into firestore.rules.
//
// Members docs written before permissions existed still work (legacy
// fallback, the same in firestore.rules and the app):
//   role 'admin'                → every permission
//   `permissions` present       → that list
//   role 'carer'                → Animal care
//   any other staff / no doc    → Full staff (+ facebookPublish when the old
//                                 facebookPublisher flag is set)
// An account acts for the organization its users/{uid}.organizationId points
// at, as firestore.rules does; a membership elsewhere grants nothing.

const {HttpsError} = require('firebase-functions/v2/https');
const DEF = require('./org_permissions.json');

const PERMISSIONS = Object.freeze([...DEF.permissions]);
const PRESETS = Object.freeze(Object.fromEntries(
    Object.entries(DEF.presets).map(([name, list]) => [name, Object.freeze([...list])])));
const LEGACY = DEF.legacy;
const INACTIVE_STATUSES = ['inactive', 'removed', 'disabled'];

function isActiveStatus(status) {
  return !INACTIVE_STATUSES.includes(status || 'active');
}

/// Known keys only, sorted, without duplicates; financeManage brings
/// financeView with it. Throws on an unknown key.
function normalizePerms(list) {
  if (!Array.isArray(list)) throw new Error('permissions must be a list.');
  const out = new Set();
  for (const key of list) {
    if (typeof key !== 'string' || !PERMISSIONS.includes(key)) throw new Error(`Unknown permission: ${key}`);
    out.add(key);
  }
  if (out.has('financeManage')) out.add('financeView');
  return PERMISSIONS.filter((k) => out.has(k));
}

/// The preset whose list matches exactly, or 'custom'.
function presetFor(perms) {
  const set = new Set(perms);
  for (const [name, list] of Object.entries(PRESETS)) {
    if (list.length === set.size && list.every((k) => set.has(k))) return name;
  }
  return 'custom';
}

/// A Staff member's permissions from their members doc, with the legacy
/// fallback. Unknown keys are ignored.
function memberPermissions(member) {
  const m = member || {};
  if (Array.isArray(m.permissions)) {
    const known = m.permissions.filter((k) => PERMISSIONS.includes(k));
    if (known.includes('financeManage') && !known.includes('financeView')) known.push('financeView');
    return PERMISSIONS.filter((k) => known.includes(k));
  }
  if (m.role === 'carer') return [...PRESETS[LEGACY.carer]];
  const base = [...PRESETS[LEGACY.staff]];
  if (m.facebookPublisher === true) base.push('facebookPublish');
  return PERMISSIONS.filter((k) => base.includes(k));
}

/// What an account may do in an organization. Pure: give it the docs.
///   org: organizations/{orgId} data (null if missing)
///   member: members/{uid} data (null if missing)
///   userOrgId: users/{uid}.organizationId
function effectiveAccess({uid, orgId, org, member, userOrgId}) {
  const none = {active: false, isOwner: false, isAdmin: false, role: null, preset: null, permissions: [],
    has: () => false};
  if (!uid || !orgId || !org) return none;
  const approved = (org.verificationStatus || 'approved') === 'approved';
  const isOwner = org.ownerId === uid;
  if (userOrgId !== orgId || !approved) return {...none, isOwner};
  if (!isOwner && member && !isActiveStatus(member.status)) return {...none};
  const isAdmin = isOwner || Boolean(member && member.role === 'admin');
  const permissions = isAdmin ? [...PERMISSIONS] : memberPermissions(member);
  const set = new Set(permissions);
  return {
    active: true,
    isOwner,
    isAdmin,
    role: isAdmin ? 'admin' : 'staff',
    preset: isAdmin ? null : presetFor(permissions),
    permissions,
    has: (key) => set.has(key),
  };
}

/// Who should hear about something: the owner, active Admins, and active
/// Staff holding any of [anyOf] (every active member when [anyOf] is empty),
/// among members docs and accounts linked to the organization. Pure.
///   members: Map uid → members doc data
///   linkedUids: users whose organizationId is this organization
function selectAudience({ownerId, members, linkedUids = [], anyOf = [], adminsOnly = false}) {
  const out = new Set();
  if (ownerId) out.add(ownerId);
  const consider = (uid, member) => {
    if (member && !isActiveStatus(member.status)) return;
    const isAdmin = member && member.role === 'admin';
    if (adminsOnly) {
      if (isAdmin) out.add(uid);
      return;
    }
    if (isAdmin || !anyOf.length) {
      out.add(uid);
      return;
    }
    const perms = memberPermissions(member);
    if (anyOf.some((k) => perms.includes(k))) out.add(uid);
  };
  for (const [uid, member] of members) consider(uid, member);
  // Linked accounts with no members doc count as Full staff (the fallback).
  for (const uid of linkedUids) if (!members.has(uid)) consider(uid, null);
  return [...out];
}

/// Checks an Admin's change to a member's access and works out what to
/// store. Pure (tested); setMemberAccess (functions/org_members.js) runs it
/// inside a transaction. Returns {error} or {before, after}.
///   ownerId: the organization's owner
///   memberUid, member: the members doc being changed (null if missing)
///   members: Map uid → members doc data of the whole organization
///   role: 'admin' | 'staff'; permissions: list (Staff only)
function planAccessChange({ownerId, memberUid, member, members, role, permissions}) {
  if (!member) return {error: 'That person is not a member of this organization.'};
  if (role !== 'admin' && role !== 'staff') return {error: 'Role must be Admin or Staff.'};
  if (memberUid === ownerId && role !== 'admin') return {error: 'The owner is always an Admin.'};
  let perms = [];
  if (role === 'staff') {
    try {
      perms = normalizePerms(permissions || []);
    } catch (e) {
      return {error: e.message};
    }
  }
  const wasAdmin = member.role === 'admin';
  if (wasAdmin && role === 'staff') {
    // Someone must still be able to manage the organization.
    let admins = ownerId && ownerId !== memberUid ? 1 : 0;
    for (const [uid, m] of members) {
      if (uid !== memberUid && uid !== ownerId && m.role === 'admin' && isActiveStatus(m.status)) admins++;
    }
    if (!admins) return {error: 'At least one active Admin has to remain.'};
  }
  const beforePerms = wasAdmin ? [] : memberPermissions(member);
  return {
    before: {role: wasAdmin ? 'admin' : 'staff', preset: wasAdmin ? null : presetFor(beforePerms), permissions: beforePerms},
    after: {role, preset: role === 'admin' ? null : presetFor(perms), permissions: perms},
  };
}

// ---- Firestore-backed helpers ---------------------------------------------

function displayName(u) {
  const full = `${u.firstName || ''} ${u.lastName || ''}`.trim();
  return full || u.name || u.email || 'Staff';
}

async function loadOrgAccess(db, uid, orgId, userData) {
  const orgRef = db.collection('organizations').doc(orgId);
  const [user, org, member] = await Promise.all([
    userData ? Promise.resolve(null) : db.collection('users').doc(uid).get(),
    orgRef.get(),
    orgRef.collection('members').doc(uid).get(),
  ]);
  const u = userData || (user && user.exists ? user.data() : {});
  return effectiveAccess({
    uid,
    orgId,
    org: org.exists ? org.data() : null,
    member: member.exists ? member.data() : null,
    userOrgId: typeof u.organizationId === 'string' ? u.organizationId : '',
  });
}

/// The caller, acting for [organizationId] (default: their own), if they are
/// an active member there with any of [anyOf] (or an Admin when [adminOnly]).
/// Throws permission-denied otherwise. Platform roles grant nothing here.
async function requireOrgPermission(db, request, {organizationId, anyOf = [], adminOnly = false, message} = {}) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const userSnap = await db.collection('users').doc(uid).get();
  const u = userSnap.exists ? userSnap.data() : {};
  const orgId = organizationId || (typeof u.organizationId === 'string' ? u.organizationId : '');
  const denied = () => new HttpsError('permission-denied',
      message || (adminOnly ? 'Only an organization Admin can do this.' : 'You don\'t have permission to do this.'));
  if (!orgId) throw denied();
  const access = await loadOrgAccess(db, uid, orgId, u);
  if (!access.active) throw denied();
  if (adminOnly && !access.isAdmin) throw denied();
  if (anyOf.length && !anyOf.some((k) => access.has(k))) throw denied();
  return {uid, name: displayName(u), role: typeof u.role === 'string' ? u.role : '', organizationId: orgId, access};
}

/// UIDs to notify in an organization (see selectAudience).
async function orgMemberUids(db, orgId, {anyOf = [], adminsOnly = false} = {}) {
  if (!orgId) return [];
  const orgRef = db.collection('organizations').doc(orgId);
  const [org, members, linked] = await Promise.all([
    orgRef.get(),
    orgRef.collection('members').get(),
    db.collection('users').where('organizationId', '==', orgId).get(),
  ]);
  return selectAudience({
    ownerId: org.exists ? org.get('ownerId') : null,
    members: new Map(members.docs.map((m) => [m.id, m.data()])),
    linkedUids: linked.docs.map((d) => d.id),
    anyOf,
    adminsOnly,
  });
}

/// Best-effort organization audit entry (never blocks the action it records).
async function writeOrgAuditLog(db, FieldValue, {action, actorId, actorName, actorEmail, organizationId,
  targetType, targetId, oldValues, newValues, category = 'organizationStaff'}) {
  try {
    await db.collection('auditLogs').add({
      category,
      action,
      actorId: actorId || null,
      actorName: actorName || null,
      actorEmail: actorEmail || null,
      organizationId,
      targetType: targetType || 'Organization',
      targetId: targetId || organizationId,
      ...(oldValues ? {oldValues} : {}),
      newValues: newValues || {},
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error('[org_access] audit log write failed', e);
  }
}

module.exports = {
  PERMISSIONS,
  PRESETS,
  isActiveStatus,
  normalizePerms,
  presetFor,
  memberPermissions,
  effectiveAccess,
  selectAudience,
  planAccessChange,
  displayName,
  loadOrgAccess,
  requireOrgPermission,
  orgMemberUids,
  writeOrgAuditLog,
};
