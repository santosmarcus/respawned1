// Shareable referral links.
//
// Staff refer a report to someone outside the app (a barangay or LGU office,
// another rescuer) and send them a link to a web page
// (public/referral/index.html, served at /referral/<token>). The page reads
// nothing from Firestore itself: these callables hand it a copy of the
// report built by buildReferralSnapshot (functions/referral_share_rules.js)
// and record the recipient's answer.
//
// Stored at referralShares/{token} (firestore.rules: no client access). The
// token is random and unguessable, the link expires after SHARE_TTL_DAYS, and
// staff can stop sharing at any time. The referral doc carries `share` (link
// state) and `lastResponse` (the latest answer) for Referral History.

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {
  SHARE_TTL_DAYS,
  SHARE_RESPONSES,
  MAX_RESPONSES_PER_SHARE,
  isValidToken,
  shareState,
  publicStatusLabel,
  buildReferralSnapshot,
  validateResponse,
  linkReferralUpdate,
} = require('./referral_share_rules');
const {loadOrgAccess} = require('./org_access');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const PLATFORM_ROLES = ['admin', 'ngo_staff'];
const BASE_URL = (process.env.SHARE_BASE_URL || process.env.PAYMENT_RETURN_BASE_URL ||
  'https://respawnd1-45021.web.app').replace(/\/+$/, '');

const shareUrl = (token) => `${BASE_URL}/referral/${token}`;
const newToken = () => crypto.randomBytes(18).toString('base64url');

function displayName(u) {
  const full = `${u.firstName || ''} ${u.lastName || ''}`.trim();
  return full || u.name || u.email || 'Staff';
}

// Staff who may share a case: platform staff, or active non-carer staff of
// the approved organization that owns it (any approved organization's staff
// for an unowned report in the review pool), as firestore.rules allows.
async function loadCaseStaff(request, caseOrgId) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const userSnap = await db.collection('users').doc(uid).get();
  const u = userSnap.exists ? userSnap.data() : {};
  const orgId = typeof u.organizationId === 'string' ? u.organizationId : '';
  // orgId: the caller's own organization, linked to a share of a case no
  // organization owns yet.
  const actor = {uid, name: displayName(u), orgId};
  if (PLATFORM_ROLES.includes(u.role)) return actor;
  const denied = () => new HttpsError('permission-denied', 'Only staff of the organization handling this case can share it.');
  if (!orgId || (caseOrgId && caseOrgId !== orgId)) throw denied();
  // Staff who handle rescues there (functions/org_access.js).
  const access = await loadOrgAccess(db, uid, orgId, u);
  if (!access.active || !access.has('rescue')) throw denied();
  return actor;
}

function requireId(v, what) {
  if (typeof v !== 'string' || !ID_PATTERN.test(v)) throw new HttpsError('invalid-argument', `A valid ${what} is required.`);
  return v;
}

async function loadReferral(caseId, referralId) {
  const caseRef = db.collection('cases').doc(caseId);
  const refRef = caseRef.collection('referrals').doc(referralId);
  const [caseSnap, refSnap] = await Promise.all([caseRef.get(), refRef.get()]);
  if (!caseSnap.exists || !refSnap.exists) throw new HttpsError('not-found', 'Referral not found.');
  return {caseRef, refRef, c: caseSnap.data(), referral: refSnap.data()};
}

function activityLog(tx, caseRef, action, actor, details) {
  tx.set(caseRef.collection('activityLogs').doc(), {
    action,
    actorUid: actor.uid || null,
    actorName: actor.name || null,
    actorRole: actor.role || null,
    details,
    timestamp: FieldValue.serverTimestamp(),
  });
}

module.exports = ({notifyStaff, orgStaffUids}) => {
  // Creates (or returns the open) link for one referral. A new choice about
  // the reporter's contact replaces the old link.
  const createReferralShare = onCall(async (request) => {
    // Signed-in first, so no one can probe which cases exist.
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
    const d = request.data || {};
    const caseId = requireId(d.caseId, 'caseId');
    const referralId = requireId(d.referralId, 'referralId');
    const includeReporter = d.includeReporter === true;
    const {caseRef, refRef, c, referral} = await loadReferral(caseId, referralId);
    const actor = await loadCaseStaff(request, c.organizationId || '');
    if (referral.type === 'rescueVolunteer') {
      throw new HttpsError('failed-precondition', 'Volunteer referrals can\'t be shared yet.');
    }

    const nowMs = Date.now();
    const existing = referral.share || null;
    if (existing && isValidToken(existing.token) && existing.includeReporter === includeReporter) {
      const snap = await db.collection('referralShares').doc(existing.token).get();
      if (snap.exists && shareState({
        revoked: snap.get('revoked'), expiresAtMs: snap.get('expiresAt').toMillis(), nowMs,
      }) === 'active') {
        return {token: existing.token, url: shareUrl(existing.token), reused: true};
      }
    }

    // A case no organization owns yet is shared under the organization
    // sharing it: its contact details go on the page and it is linked to
    // the link (and to a Facebook post of it).
    const caseOrgId = c.organizationId || '';
    const orgId = caseOrgId || actor.orgId || '';
    const org = orgId ? await db.collection('organizations').doc(orgId).get() : null;
    const snapshot = buildReferralSnapshot({
      caseId, c, referral, org: org && org.exists ? org.data() : {}, includeReporter,
    });
    const token = newToken();
    const expiresAt = Timestamp.fromMillis(nowMs + SHARE_TTL_DAYS * 24 * 60 * 60 * 1000);
    await db.runTransaction(async (tx) => {
      if (existing && isValidToken(existing.token)) {
        tx.set(db.collection('referralShares').doc(existing.token), {revoked: true, revokedAt: FieldValue.serverTimestamp()},
          {merge: true});
      }
      tx.set(db.collection('referralShares').doc(token), {
        caseId,
        referralId,
        organizationId: orgId,
        ...(caseOrgId ? {} : {linkedBySharer: orgId !== ''}),
        snapshot,
        includeReporter,
        revoked: false,
        responseCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        createdByUid: actor.uid,
        createdByName: actor.name,
        expiresAt,
      });
      tx.update(refRef, {
        share: {token, url: shareUrl(token), includeReporter, expiresAt, createdAt: FieldValue.serverTimestamp(),
          createdByName: actor.name, revoked: false},
      });
      activityLog(tx, caseRef, 'referral_link_created', actor, {referralId, includeReporter});
    });
    return {token, url: shareUrl(token), reused: false};
  });

  const revokeReferralShare = onCall(async (request) => {
    // Signed-in first, so no one can probe which cases exist.
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
    const d = request.data || {};
    const caseId = requireId(d.caseId, 'caseId');
    const referralId = requireId(d.referralId, 'referralId');
    const {caseRef, refRef, c, referral} = await loadReferral(caseId, referralId);
    const actor = await loadCaseStaff(request, c.organizationId || '');
    const token = referral.share && referral.share.token;
    if (!isValidToken(token)) return {revoked: false};
    await db.runTransaction(async (tx) => {
      tx.set(db.collection('referralShares').doc(token), {revoked: true, revokedAt: FieldValue.serverTimestamp(),
        revokedByUid: actor.uid}, {merge: true});
      tx.update(refRef, {'share.revoked': true, 'share.revokedAt': FieldValue.serverTimestamp()});
      activityLog(tx, caseRef, 'referral_link_revoked', actor, {referralId});
    });
    return {revoked: true};
  });

  // The page's only data source. No sign-in: the token is the key.
  const getReferralShare = onCall(async (request) => {
    const token = (request.data || {}).token;
    if (!isValidToken(token)) throw new HttpsError('not-found', 'This link is not valid.');
    const snap = await db.collection('referralShares').doc(token).get();
    if (!snap.exists) throw new HttpsError('not-found', 'This link is not valid.');
    const s = snap.data();
    const state = shareState({revoked: s.revoked, expiresAtMs: s.expiresAt.toMillis(), nowMs: Date.now()});
    if (state !== 'active') {
      return {state, organization: (s.snapshot && s.snapshot.organization) || {}};
    }
    const [caseSnap, responses] = await Promise.all([
      db.collection('cases').doc(s.caseId).get(),
      snap.ref.collection('responses').orderBy('createdAt', 'desc').limit(5).get(),
    ]);
    return {
      state,
      snapshot: s.snapshot,
      statusLabel: publicStatusLabel(caseSnap.exists ? caseSnap.get('status') : 'closed'),
      expiresAtMs: s.expiresAt.toMillis(),
      responses: responses.docs.map((r) => ({
        response: r.get('response'),
        label: SHARE_RESPONSES[r.get('response')] || '',
        name: r.get('name'),
        note: r.get('note') || null,
        atMs: r.get('createdAt') ? r.get('createdAt').toMillis() : null,
      })),
      responseOptions: SHARE_RESPONSES,
    };
  });

  // The recipient's answer: kept with the link, shown in Referral History,
  // logged on the case and pushed to staff. On an LGU referral, "Will handle
  // it" marks it Accepted and "Can't take it" Declined with the note.
  const respondToReferralShare = onCall(async (request) => {
    const d = request.data || {};
    if (!isValidToken(d.token)) throw new HttpsError('not-found', 'This link is not valid.');
    const checked = validateResponse(d);
    if (checked.error) throw new HttpsError('invalid-argument', checked.error);
    const answer = checked.value;
    const shareRef = db.collection('referralShares').doc(d.token);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(shareRef);
      if (!snap.exists) throw new HttpsError('not-found', 'This link is not valid.');
      const s = snap.data();
      if (shareState({revoked: s.revoked, expiresAtMs: s.expiresAt.toMillis(), nowMs: Date.now()}) !== 'active') {
        throw new HttpsError('failed-precondition', 'This link is no longer open.');
      }
      if ((s.responseCount || 0) >= MAX_RESPONSES_PER_SHARE) {
        throw new HttpsError('resource-exhausted', 'This link has taken all the answers it can. Please contact the organization directly.');
      }
      const caseRef = db.collection('cases').doc(s.caseId);
      const refRef = caseRef.collection('referrals').doc(s.referralId);
      const [refSnap, caseSnap] = await Promise.all([tx.get(refRef), tx.get(caseRef)]);
      const now = Timestamp.now();
      const link = linkReferralUpdate(caseSnap.get('linkReferral'), s.referralId, answer, now);
      tx.set(shareRef.collection('responses').doc(), {...answer, createdAt: now});
      tx.update(shareRef, {responseCount: FieldValue.increment(1), lastResponseAt: now});
      if (refSnap.exists) {
        const update = {lastResponse: {...answer, at: now}};
        if (refSnap.get('type') === 'localGovernmentUnit') {
          if (answer.response === 'will_handle') {
            Object.assign(update, {status: 'accepted', respondedAt: now, respondedByName: answer.name});
          } else if (answer.response === 'cannot_handle') {
            Object.assign(update, {status: 'declined', respondedAt: now, respondedByName: answer.name,
              declineReason: answer.note});
          }
        }
        tx.update(refRef, update);
      }
      const label = SHARE_RESPONSES[answer.response];
      tx.update(caseRef, {
        statusHistory: FieldValue.arrayUnion({
          status: `Referral answer from ${answer.name}: ${label}.`, timestamp: now,
        }),
        // Shared-link referral: "Will handle it" ends the wait (Closed in
        // the app); the other answers keep the case pending in Review.
        ...(link ? {linkReferral: link} : {}),
      });
      activityLog(tx, caseRef, 'referral_response', {name: answer.name, role: 'referral_recipient'},
        {referralId: s.referralId, ...answer});
      return {s, label};
    });

    const {s, label} = result;
    try {
      const uids = s.organizationId ? await orgStaffUids(s.organizationId, {anyOf: ['rescue']}) : [s.createdByUid];
      await notifyStaff(uids, {
        title: 'Referral answered',
        body: `${answer.name}: ${label}${answer.note ? ` — ${answer.note}` : ''}`.slice(0, 180),
        data: {type: 'referral_response', caseId: s.caseId},
      });
    } catch (e) {
      console.warn('[respondToReferralShare] notify failed', e.message);
    }
    return {ok: true};
  });

  return {createReferralShare, revokeReferralShare, getReferralShare, respondToReferralShare};
};
