// Adoption gap 10: Community Adoption stays light (no interview, agreement
// or schedule), but each claim gets one check-in two weeks later, and the
// organizations in the area can see their community adoptions. Used by
// scheduleCommunityAdoptionCheckIn and sendCommunityAdoptionCheckIns in
// functions/index.js. No Firebase here, so `node --test` checks it.

/// Pending the organization's confirmation.
const COMMUNITY_CHECKIN_DAYS = 14;
const DAY_MS = 24 * 60 * 60 * 1000;

/// When the check-in is due for a claim made at [claimedAtMs].
function checkInDueAtMs(claimedAtMs) {
  return claimedAtMs + COMMUNITY_CHECKIN_DAYS * DAY_MS;
}

/// Whether the adopter should be asked now. Asked once only.
function checkInRequestDue(checkIn, nowMs) {
  if (!checkIn || checkIn.status !== 'scheduled') return false;
  return typeof checkIn.dueAtMs === 'number' && nowMs >= checkIn.dueAtMs;
}

/// The organizations that see it: the case's owner, else every organization
/// covering the case's area.
function checkInOrgIds(caseData, adoption) {
  if (adoption && typeof adoption.organizationId === 'string' && adoption.organizationId) return [adoption.organizationId];
  if (caseData && typeof caseData.organizationId === 'string' && caseData.organizationId) return [caseData.organizationId];
  return Array.isArray(caseData && caseData.areaOrgIds) ? caseData.areaOrgIds.filter((x) => typeof x === 'string' && x) : [];
}

module.exports = {COMMUNITY_CHECKIN_DAYS, checkInDueAtMs, checkInRequestDue, checkInOrgIds};
