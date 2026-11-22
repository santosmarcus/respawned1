// Independent rescuers: pure rules (tested in independent_rescuer_rules.test.js).
//
// An independent rescuer is an organizations/{id} doc with kind
// 'independent': one person or a small team with fewer modules, a member
// cap, case and animal capacity, and a small coverage geofence. Shelters see
// a new non-critical report alone for a head start; after that it opens to
// the independents whose geofence covers it. Limits come from
// org_permissions.json `independent`.

const DEF = require('./org_permissions.json');
const {isIndependent, independentLimits, independentCaseRefusal, PERMISSIONS} = require('./org_access');

const INDEPENDENT = DEF.independent;

// Case statuses that no longer count against a rescuer's capacity.
const CLOSED_CASE_STATUSES = Object.freeze(['rejected', 'merged', 'completed', 'closed', 'cancelled']);

function isOpenCaseStatus(status) {
  return !CLOSED_CASE_STATUSES.includes(status || 'pending');
}

/// An animal record still in the rescuer's care (not adopted, deceased or
/// transferred out).
function isAnimalInCare(a) {
  const d = a || {};
  if (d.adoptionStatus === 'adopted' || d.adoptionStatus === 'deceased' || d.status === 'deceased') return false;
  // A transfer to another organization only ever reaches 'pending' (the
  // record has left: AnimalRecord.isTransferredOut).
  if (d.transferStatus) return false;
  return true;
}

function toRad(v) {
  return (v * Math.PI) / 180;
}

function distanceKm(aLat, aLng, bLat, bLng) {
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/// An independent's geofence radius, kept inside the allowed range whatever
/// was saved.
function clampRadiusKm(r) {
  const {min, max} = INDEPENDENT.radiusKm;
  const v = typeof r === 'number' && Number.isFinite(r) ? r : INDEPENDENT.radiusKm.default;
  return Math.min(max, Math.max(min, v));
}

/// The distance from (lat, lng) to the nearest of an independent's
/// geofences that contains it, or null if none does.
function coverageDistanceKm(org, lat, lng) {
  let best = null;
  for (const area of Array.isArray(org.serviceAreas) ? org.serviceAreas : []) {
    if (!area || typeof area.lat !== 'number' || typeof area.lng !== 'number') continue;
    const d = distanceKm(area.lat, area.lng, lat, lng);
    if (d <= clampRadiusKm(area.radiusKm) && (best === null || d < best)) best = d;
  }
  return best;
}

/// The independents a new report at (lat, lng) opens to: approved, taking
/// cases, under capacity, and covering the point. Nearest first.
///   orgs: [{id, data}]
function nearbyIndependents(orgs, lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') return [];
  const hits = [];
  for (const {id, data} of orgs) {
    if (!isIndependent(data)) continue;
    if ((data.verificationStatus || 'approved') !== 'approved') continue;
    if (independentCaseRefusal(data)) continue;
    const d = coverageDistanceKm(data, lat, lng);
    if (d !== null) hits.push({id, distanceKm: d});
  }
  hits.sort((a, b) => a.distanceKm - b.distanceKm);
  return hits;
}

/// When a new report opens to nearby independents: at once for a Critical
/// report, else after the shelters' head start.
function independentsOpenAtMs(createdAtMs, urgency) {
  if (String(urgency || '').toLowerCase() === 'critical') return createdAtMs;
  return createdAtMs + INDEPENDENT.headStartMinutes * 60 * 1000;
}

/// Checks a system admin's change to an independent's modules and limits.
/// Returns {error} or {update}.
function planLimitsChange(input) {
  const d = input || {};
  const update = {};
  if (d.enabledPermissions !== undefined) {
    if (!Array.isArray(d.enabledPermissions)) return {error: 'enabledPermissions must be a list.'};
    const bad = d.enabledPermissions.filter((k) => !INDEPENDENT.allowed.includes(k));
    if (bad.length) return {error: `Not available to rescue volunteers: ${bad.join(', ')}.`};
    for (const required of ['rescue']) {
      if (!d.enabledPermissions.includes(required)) return {error: 'Rescue cases can\'t be turned off.'};
    }
    update.enabledPermissions = PERMISSIONS.filter((k) => d.enabledPermissions.includes(k));
  }
  const ints = {memberCap: [1, 10], maxActiveCases: [1, 20], maxAnimalsInCare: [0, 50]};
  for (const [key, [lo, hi]] of Object.entries(ints)) {
    if (d[key] === undefined) continue;
    if (!Number.isInteger(d[key]) || d[key] < lo || d[key] > hi) {
      return {error: `${key} must be a whole number from ${lo} to ${hi}.`};
    }
    update[key] = d[key];
  }
  if (!Object.keys(update).length) return {error: 'Nothing to change.'};
  return {update};
}

module.exports = {
  INDEPENDENT,
  CLOSED_CASE_STATUSES,
  isOpenCaseStatus,
  isAnimalInCare,
  distanceKm,
  clampRadiusKm,
  coverageDistanceKm,
  nearbyIndependents,
  independentsOpenAtMs,
  planLimitsChange,
  independentLimits,
  independentCaseRefusal,
};
