// Dashboard and Analytics backend (Dashboard gaps 6 and 7, Analytics gap 6).
//
//  - sendDashboardDigest (every day 07:00 Manila): one push to each approved
//    organization's admins with the Priority actions counts by area, and
//    deletes lapsed alert claims.
//  - notifyStaffOfSpecializedAssistance: an immediate push to the
//    organization's staff when a rescue can't continue without specialized
//    handling (a critical dashboard alert). The other critical alerts
//    already push: new reports (notifyNewCaseReported), unreviewed critical
//    reports (escalateCriticalReports), expired offers
//    (notifyStaffOfOfferOutcome), stopped trips (notifyStaffOfTransitEnd).
//  - writeAnalyticsSummaries (1st of the month, 02:00 Manila): one summary
//    per organization for the month that just ended, filling in any of the
//    last 12 months that are missing (so the first run backfills).
//    rebuildAnalyticsSummaries lets an organization admin rebuild them.
//
// index.js passes in its helpers: orgStaffUids, notifyStaff and the open
// follow-up statuses.

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const digest = require('./dashboard_digest_rules');
const summaries = require('./analytics_summary_rules');

const SUMMARY_BACKFILL_MONTHS = 12;

module.exports = function dashboardOps({db, orgStaffUids, notifyStaff, openFollowUpStatuses}) {
  async function approvedOrgIds() {
    const snap = await db.collection('organizations').get();
    return snap.docs
      .filter((d) => (d.get('verificationStatus') || 'approved') === 'approved')
      .map((d) => d.id);
  }

  async function digestFor(orgId, nowMs) {
    const [cases, adoptions, followUps, payments] = await Promise.all([
      db.collection('cases')
        .where('organizationId', '==', orgId)
        .where('status', 'in', digest.DIGEST_CASE_STATUSES)
        .get(),
      db.collection('adoptions').where('organizationId', '==', orgId).get(),
      db.collectionGroup('followUps')
        .where('organizationId', '==', orgId)
        .where('status', 'in', openFollowUpStatuses)
        .get(),
      db.collection('donationPayments').where('organizationId', '==', orgId).get(),
    ]);
    return digest.digestCounts({
      cases: cases.docs.map((d) => d.data()),
      adoptions: adoptions.docs.map((d) => d.data()),
      followUps: followUps.docs.map((d) => d.data()),
      payments: payments.docs.map((d) => d.data()),
      nowMs,
    });
  }

  async function deleteLapsedClaims(orgId, nowMs) {
    const snap = await db.collection('organizations').doc(orgId).collection('alertClaims').get();
    const stale = snap.docs.filter((d) => digest.claimDeletable(d.data(), nowMs));
    for (let i = 0; i < stale.length; i += 400) {
      const batch = db.batch();
      stale.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
  }

  const sendDashboardDigest = onSchedule(
    {schedule: 'every day 07:00', timeZone: 'Asia/Manila'},
    async () => {
      const nowMs = Date.now();
      for (const orgId of await approvedOrgIds()) {
        try {
          await deleteLapsedClaims(orgId, nowMs);
          const message = digest.digestMessage(await digestFor(orgId, nowMs));
          if (!message) continue;
          const admins = await orgStaffUids(orgId, {adminsOnly: true});
          await notifyStaff(admins, {...message, data: {type: 'dashboard_digest'}});
        } catch (e) {
          console.error('[sendDashboardDigest] failed for org', orgId, e);
        }
      }
    },
  );

  const notifyStaffOfSpecializedAssistance = onDocumentUpdated('cases/{caseId}', async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after || before.status === after.status || after.status !== 'needs_specialized_assistance') return;
    const orgId = after.organizationId;
    if (!orgId) return;
    const reason = after.endReason ? ` (${after.endReason})` : '';
    await notifyStaff(await orgStaffUids(orgId), {
      title: 'Rescue needs specialized assistance',
      body: `The transporter could not safely handle the animal${reason}. ` +
        'Arrange a specialized handler, re-assign or refer the case.',
      data: {type: 'needs_specialized_assistance', caseId: event.params.caseId},
    });
  });

  async function loadOrgData(orgId) {
    const [cases, animals, adoptions, donations] = await Promise.all([
      db.collection('cases').where('organizationId', '==', orgId).get(),
      db.collection('animals').where('organizationId', '==', orgId).get(),
      db.collection('adoptions').where('organizationId', '==', orgId).get(),
      db.collection('donations').where('organizationId', '==', orgId).get(),
    ]);
    return {
      cases: cases.docs.map((d) => d.data()),
      animals: animals.docs.map((d) => d.data()),
      adoptions: adoptions.docs.map((d) => d.data()),
      donations: donations.docs.map((d) => d.data()),
    };
  }

  /// Writes the summaries for [keys] ('yyyy-MM'), or only the missing ones
  /// unless [overwrite].
  async function writeSummaries(orgId, keys, {overwrite = false} = {}) {
    const col = db.collection('organizations').doc(orgId).collection('analyticsSummaries');
    let todo = keys;
    if (!overwrite) {
      const existing = await Promise.all(keys.map((k) => col.doc(k).get()));
      todo = keys.filter((k, i) => !existing[i].exists || existing[i].get('version') !== summaries.SUMMARY_VERSION);
    }
    if (!todo.length) return 0;
    const data = await loadOrgData(orgId);
    const batch = db.batch();
    for (const key of todo) {
      batch.set(col.doc(key), {
        ...summaries.summarizeMonth({key, ...data}),
        organizationId: orgId,
        computedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return todo.length;
  }

  const writeAnalyticsSummaries = onSchedule(
    {schedule: '0 2 1 * *', timeZone: 'Asia/Manila', timeoutSeconds: 540},
    async () => {
      const keys = summaries.previousMonthKeys(Date.now(), SUMMARY_BACKFILL_MONTHS);
      for (const orgId of await approvedOrgIds()) {
        try {
          // The month that just ended is always rewritten; older ones only
          // when missing.
          await writeSummaries(orgId, keys.slice(0, 1), {overwrite: true});
          await writeSummaries(orgId, keys.slice(1));
        } catch (e) {
          console.error('[writeAnalyticsSummaries] failed for org', orgId, e);
        }
      }
    },
  );

  const rebuildAnalyticsSummaries = onCall({timeoutSeconds: 300}, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
    const user = (await db.collection('users').doc(uid).get()).data() || {};
    const orgId = (request.data && request.data.organizationId) || user.organizationId;
    if (!orgId) throw new HttpsError('failed-precondition', 'Your account is not linked to an organization.');
    const isPlatformAdmin = user.role === 'admin';
    const admins = await orgStaffUids(orgId, {adminsOnly: true});
    if (!isPlatformAdmin && !admins.includes(uid)) {
      throw new HttpsError('permission-denied', 'Only the organization\'s admins can rebuild its summaries.');
    }
    const keys = summaries.previousMonthKeys(Date.now(), SUMMARY_BACKFILL_MONTHS);
    const written = await writeSummaries(orgId, keys, {overwrite: true});
    return {written};
  });

  return {
    sendDashboardDigest,
    notifyStaffOfSpecializedAssistance,
    writeAnalyticsSummaries,
    rebuildAnalyticsSummaries,
  };
};
