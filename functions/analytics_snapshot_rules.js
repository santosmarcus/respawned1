// Pure daily analytics snapshot (RESPAWND_ANALYTICS_PLAN 2.4). How many
// animals are in treatment and in the shelter right now can't be rebuilt
// later, so snapshotDailyAnalytics (functions/dashboard_ops.js) stores one
// per organization per Manila day at
// organizations/{orgId}/analyticsSnapshots/{yyyy-MM-dd}; the Analytics
// treatment-load and occupancy trends read them. No Firebase here, so
// `node --test` checks it.
//
// Keep in step with lib/core/utils/shelter_occupancy.dart (housed) and
// lib/features/adminhome/dashboard/metrics/rescue_metrics.dart
// (animalsInTreatment).

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const SNAPSHOT_VERSION = 1;

/// Raw case statuses meaning the animals are at the clinic.
const AT_CLINIC = ['in_treatment', 'awaiting_adopter_pickup'];
/// Raw case statuses of finished or non-organization cases.
const NOT_ACTIVE = ['rejected', 'merged', 'completed', 'closed', 'cancelled', 'withdrawn', 'community_adoption'];

/// 'yyyy-MM-dd' for the Manila day containing [atMs].
function dayKeyOf(atMs) {
  const d = new Date(atMs + MANILA_OFFSET_MS);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`;
}

function animalsOf(c) {
  return Array.isArray(c.animals) && c.animals.length ? c.animals : [c];
}

function leftTreatment(a) {
  return a.dischargedAt != null || a.deceasedAt != null || a.outcome === 'deceased';
}

function isHoused(a) {
  return !a.archived && a.status !== 'deceased' && a.adoptionStatus !== 'adopted' && a.adoptionStatus !== 'deceased';
}

function toMs(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return typeof v === 'number' ? v : null;
}

/// Counts for one organization at [nowMs].
function dailySnapshot({cases = [], animals = [], followUps = [], maxCapacity = null, nowMs}) {
  let inTreatment = 0;
  let activeCases = 0;
  for (const c of cases) {
    if (c.isDemo === true) continue;
    if (!NOT_ACTIVE.includes(c.status)) activeCases++;
    if (AT_CLINIC.includes(c.status)) inTreatment += animalsOf(c).filter((a) => !leftTreatment(a)).length;
  }
  const housed = animals.filter(isHoused);
  const overdue = followUps.filter((f) => {
    const due = toMs(f.scheduledDate);
    return (f.status === 'scheduled' || f.status === 'reminderSent') && due != null && due < nowMs;
  }).length;
  const cap = Number.isInteger(maxCapacity) && maxCapacity > 0 ? maxCapacity : null;
  return {
    version: SNAPSHOT_VERSION,
    day: dayKeyOf(nowMs),
    inTreatment,
    inShelter: housed.length,
    inIsolation: housed.filter((a) => a.careStatus === 'isolation').length,
    readyForAdoption: housed.filter((a) => a.adoptionStatus === 'adoptable').length,
    shelterCapacity: cap,
    activeCases,
    followUpsOverdue: overdue,
  };
}

module.exports = {dayKeyOf, dailySnapshot, SNAPSHOT_VERSION, AT_CLINIC};
