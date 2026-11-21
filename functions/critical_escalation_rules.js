
const {countsAsOrgWorkload} = require('./org_involvement');

/// Pending the organization's confirmation. An organization can set its
/// own: organizations/{orgId}/settings/shelter.criticalEscalationMinutes.
const DEFAULT_ESCALATION_MINUTES = 30;

/// Statuses that mean "still waiting for someone to review it".
const REVIEW_STATUSES = ['pending', 'verifying'];

/// The threshold an organization asked for, or the default.
function escalationMinutes(setting) {
  return typeof setting === 'number' && Number.isFinite(setting) && setting > 0 ? setting : DEFAULT_ESCALATION_MINUTES;
}

/// Whether case [c] should be escalated now. [thresholdMinutes] is the
/// smallest threshold among the organizations covering it.
function escalationDue(c, {createdAtMs, nowMs, thresholdMinutes}) {
  if (!c || c.urgency !== 'Critical') return false;
  // A reporter-led neglect/abuse report is not organization workload while
  // it waits in review, so it is never escalated (org_involvement.js).
  if (!countsAsOrgWorkload(c)) return false;
  if (!REVIEW_STATUSES.includes(c.status)) return false;
  if (c.criticalEscalatedAt) return false;
  if (typeof createdAtMs !== 'number' || createdAtMs <= 0) return false;
  return nowMs - createdAtMs >= escalationMinutes(thresholdMinutes) * 60 * 1000;
}

/// The organizations to alert: the owner if the case has one, otherwise
/// every organization whose coverage area contains it.
function escalationOrgIds(c) {
  if (c && typeof c.organizationId === 'string' && c.organizationId) return [c.organizationId];
  return Array.isArray(c && c.areaOrgIds) ? c.areaOrgIds.filter((x) => typeof x === 'string' && x) : [];
}

module.exports = {DEFAULT_ESCALATION_MINUTES, REVIEW_STATUSES, escalationMinutes, escalationDue, escalationOrgIds};
