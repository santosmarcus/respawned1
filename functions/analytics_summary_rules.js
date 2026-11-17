// Pure monthly analytics summaries (Analytics gap 6). writeAnalyticsSummaries
// in functions/dashboard_ops.js reads one organization's cases, animal
// records, adoption applications and donations and stores one summary per
// calendar month (Asia/Manila) at
// organizations/{orgId}/analyticsSummaries/{yyyy-MM}. The app's
// "Month by month" card and the monthly report read those, and compute only
// the current month live. No Firebase here, so `node --test` checks it.
//
// Keep the outcome rules in step with computeOutcomes in
// lib/features/adminhome/dashboard/analytics_view.dart.

const {ms} = require('./dashboard_digest_rules');

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const REUNITED = ['reunited', 'reunitedWithOwner'];
/// Summary layout version; bump when a field's meaning changes.
const SUMMARY_VERSION = 1;

/// 'yyyy-MM' for the Manila calendar month containing [atMs].
function monthKeyOf(atMs) {
  const d = new Date(atMs + MANILA_OFFSET_MS);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

/// [startMs, endMs) of the Manila calendar month [key] ('yyyy-MM').
function monthRange(key) {
  const [y, m] = key.split('-').map(Number);
  return {
    startMs: Date.UTC(y, m - 1, 1) - MANILA_OFFSET_MS,
    endMs: Date.UTC(y, m, 1) - MANILA_OFFSET_MS,
  };
}

/// The [count] month keys before the month containing [nowMs], newest first.
function previousMonthKeys(nowMs, count) {
  const d = new Date(nowMs + MANILA_OFFSET_MS);
  const keys = [];
  for (let i = 1; i <= count; i++) {
    const t = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - i, 1);
    const x = new Date(t);
    keys.push(`${x.getUTCFullYear()}-${String(x.getUTCMonth() + 1).padStart(2, '0')}`);
  }
  return keys;
}

function isEuthanasia(cause) {
  return typeof cause === 'string' && cause.toLowerCase().includes('euthan');
}

function summarizeMonth({key, cases = [], animals = [], adoptions = [], donations = []}) {
  const {startMs, endMs} = monthRange(key);
  const inMonth = (v) => {
    const t = ms(v);
    return t != null && t >= startMs && t < endMs;
  };
  const s = {
    month: key,
    version: SUMMARY_VERSION,
    reports: 0,
    criticalReports: 0,
    reportsByType: {},
    communityCatReports: 0,
    rescuesCompleted: 0,
    intake: 0,
    adopted: 0,
    returnedToOwner: 0,
    transferStarted: 0,
    releasedToReporter: 0,
    diedInCare: 0,
    euthanasia: 0,
    applications: 0,
    applicationsApproved: 0,
    applicationsRejected: 0,
    returnRequests: 0,
    donationsCount: 0,
    donationsTotal: 0,
  };

  for (const c of cases) {
    if (inMonth(c.createdAt)) {
      s.reports++;
      if (c.urgency === 'Critical') s.criticalReports++;
      const type = typeof c.rescueType === 'string' && c.rescueType ? c.rescueType : 'Unspecified';
      s.reportsByType[type] = (s.reportsByType[type] || 0) + 1;
      if (c.communityCat === true) s.communityCatReports++;
    }
    if (['completed', 'closed'].includes(c.status) && inMonth(c.completedAt || c.updatedAt)) s.rescuesCompleted++;
    if (inMonth(c.deceasedAt) && c.sourceType !== 'animalRecordAdmission') {
      if (isEuthanasia(c.causeOfDeath)) s.euthanasia++; else s.diedInCare++;
    }
    if (REUNITED.includes(c.closureReason) && inMonth(c.closedAt)) {
      s.returnedToOwner += Array.isArray(c.animals) && c.animals.length ? c.animals.length : 1;
    }
    for (const a of Array.isArray(c.animals) ? c.animals : []) {
      if (a && a.postTreatmentAction === 'release' && inMonth(a.releaseCompletedAt)) s.releasedToReporter++;
      if (a && a.postTreatmentAction === 'transfer' && inMonth(a.postTreatmentStartedAt)) s.transferStarted++;
    }
  }

  for (const a of animals) {
    if (inMonth(a.createdAt)) s.intake++;
    if (inMonth(a.adoptedAt)) s.adopted++;
    else if (a.transferStatus != null && inMonth(a.transferredAt)) s.transferStarted++;
    else if (inMonth(a.deceasedAt)) {
      if (isEuthanasia(a.deceasedCause)) s.euthanasia++; else s.diedInCare++;
    }
  }

  for (const a of adoptions) {
    if (inMonth(a.createdAt)) s.applications++;
    if (inMonth(a.approvedAt)) s.applicationsApproved++;
    if (inMonth(a.rejectedAt)) s.applicationsRejected++;
    if (a.returnRequest && inMonth(a.returnRequest.requestedAt)) s.returnRequests++;
  }

  for (const d of donations) {
    if (!inMonth(d.createdAt)) continue;
    if (['reversed', 'voided', 'void', 'cancelled'].includes(d.status)) continue;
    if (typeof d.type === 'string' && d.type.toLowerCase().includes('kind')) continue;
    if (typeof d.amount !== 'number' || !Number.isFinite(d.amount)) continue;
    s.donationsCount++;
    s.donationsTotal += d.amount;
  }
  s.donationsTotal = Math.round(s.donationsTotal * 100) / 100;

  const live = s.adopted + s.returnedToOwner + s.transferStarted + s.releasedToReporter;
  const nonLive = s.diedInCare + s.euthanasia;
  s.liveOutcomes = live;
  s.nonLiveOutcomes = nonLive;
  s.liveRate = live + nonLive === 0 ? null : Math.round((live / (live + nonLive)) * 1000) / 1000;
  return s;
}

module.exports = {SUMMARY_VERSION, monthKeyOf, monthRange, previousMonthKeys, summarizeMonth};
