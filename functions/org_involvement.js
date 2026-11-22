// How much the organization is expected to do for a report
// (cases/{id}.orgInvolvement). Mirrors
// lib/core/models/rescue/org_involvement.dart; keep the two in step.
//
//   org_assist            the reporter asked the organization to act
//                         (also every report saved before the field existed)
//   independent_report    Neglect or Abuse the reporter takes to the
//                         authorities themselves
//   not_org_facilitated   Pet Surrender: the organization does not
//                         facilitate surrenders
//
// No Firebase here, so `node --test` checks it.

const ORG_ASSIST = 'org_assist';
const INDEPENDENT_REPORT = 'independent_report';
const NOT_ORG_FACILITATED = 'not_org_facilitated';
const VALUES = [ORG_ASSIST, INDEPENDENT_REPORT, NOT_ORG_FACILITATED];

/// The case's involvement; unknown or missing reads as org_assist.
function involvementOf(c) {
  const v = c && c.orgInvolvement;
  return VALUES.includes(v) ? v : ORG_ASSIST;
}

/// Statuses that mean the report is still waiting for review.
const REVIEW_STATUSES = ['pending', 'verifying'];

/// Whether the case is organization workload (digest counts, critical
/// escalation). Reporter-led and not-facilitated reports become workload
/// only once staff take them on.
function countsAsOrgWorkload(c) {
  if (involvementOf(c) === ORG_ASSIST) return true;
  return !REVIEW_STATUSES.includes(c && c.status);
}

/// Whether nearby responders and the public should be asked to help.
/// Never for a surrender, and never for a reporter-led neglect/abuse
/// report: a crowd at the location could put the reporter or the animal at
/// risk, or get in the way of the authorities.
function broadcastsForHelp(c) {
  return involvementOf(c) === ORG_ASSIST;
}

module.exports = {
  ORG_ASSIST, INDEPENDENT_REPORT, NOT_ORG_FACILITATED, REVIEW_STATUSES,
  involvementOf, countsAsOrgWorkload, broadcastsForHelp,
};
