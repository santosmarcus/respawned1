// Pure decisions for the morning dashboard digest (Dashboard gap 6) and
// alert claims (Dashboard gap 7). Used by functions/dashboard_ops.js; no
// Firebase here, so `node --test` checks them.

/// Keep equal to kAlertClaimTtl in
/// lib/features/adminhome/dashboard/alert_claims.dart.
const ALERT_CLAIM_TTL_HOURS = 24;
/// Lapsed claims are deleted after this long (they already read as lapsed).
const ALERT_CLAIM_DELETE_HOURS = 48;

const CRITICAL = 'Critical';

// Firestore status values (RescueStatus in rescue_status.dart).
const REVIEW = ['pending', 'verifying'];
const NEEDS_CLINIC = ['accepted_pending_clinic'];
const NEEDS_TRANSPORT = ['accepted'];
const FIELD_ISSUES = ['unable_to_locate', 'awaiting_reporter_response', 'pickup_attempt_unsuccessful'];
const SPECIALIZED = ['needs_specialized_assistance'];
const TRANSIT_ENDED = ['transit_ended', 'ended'];
const TREATMENT = ['in_treatment'];
const INTAKE = ['intake'];

/// Every case status the digest looks at (one `in` query per organization;
/// Firestore allows up to 30 values).
const DIGEST_CASE_STATUSES = [
  ...REVIEW, ...NEEDS_CLINIC, ...NEEDS_TRANSPORT, ...FIELD_ISSUES,
  ...SPECIALIZED, ...TRANSIT_ENDED, ...TREATMENT, ...INTAKE,
];

function ms(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v._seconds === 'number') return v._seconds * 1000;
  return null;
}

/// Counts for one organization, from its active cases, adoption
/// applications, open follow-ups and payments needing review. The same
/// groups as the dashboard's Priority actions (dashboard_alerts.dart).
function digestCounts({cases = [], adoptions = [], followUps = [], payments = [], nowMs}) {
  const c = {
    criticalReview: 0, review: 0, needsClinic: 0, needsTransport: 0,
    fieldIssues: 0, specialized: 0, transitEnded: 0,
    readyForDischarge: 0, intake: 0,
    applications: 0, awaitingRelease: 0, returns: 0, followUpsOverdue: 0,
    paymentsToVerify: 0,
  };
  for (const k of cases) {
    const s = k.status;
    if (REVIEW.includes(s)) {
      if (k.urgency === CRITICAL) c.criticalReview++; else c.review++;
    } else if (NEEDS_CLINIC.includes(s)) c.needsClinic++;
    else if (NEEDS_TRANSPORT.includes(s)) c.needsTransport++;
    else if (FIELD_ISSUES.includes(s)) c.fieldIssues++;
    else if (SPECIALIZED.includes(s)) c.specialized++;
    else if (TRANSIT_ENDED.includes(s)) c.transitEnded++;
    else if (TREATMENT.includes(s) && k.readyForDischarge === true) c.readyForDischarge++;
    else if (INTAKE.includes(s)) c.intake++;
  }
  for (const a of adoptions) {
    if (a.status === 'pending') c.applications++;
    else if (a.status === 'approved') c.awaitingRelease++;
    const r = a.returnRequest;
    if (a.status === 'adopted' && r && r.status && !['declined', 'intake', 'cancelled'].includes(r.status)) c.returns++;
  }
  for (const f of followUps) {
    const due = ms(f.scheduledDate);
    if (due != null && due < nowMs) c.followUpsOverdue++;
  }
  c.paymentsToVerify = payments.filter((p) => p.status === 'needs_review').length;
  return c;
}

function plural(n, one, many) {
  return `${n} ${n === 1 ? one : (many || `${one}s`)}`;
}

/// The push for [counts], or null when there is nothing to act on.
function digestMessage(counts) {
  const areas = [];
  const rescue = [
    counts.criticalReview && plural(counts.criticalReview, 'critical report') + ' to assess',
    counts.specialized && plural(counts.specialized, 'rescue') + ' needing specialized help',
    counts.transitEnded && plural(counts.transitEnded, 'stopped trip'),
    counts.needsTransport && plural(counts.needsTransport, 'case') + ' waiting for a transporter',
    counts.needsClinic && plural(counts.needsClinic, 'case') + ' without a clinic',
    counts.fieldIssues && plural(counts.fieldIssues, 'pickup') + ' stalled',
    counts.review && plural(counts.review, 'report') + ' to review',
  ].filter(Boolean);
  if (rescue.length) areas.push(`Rescue: ${rescue.join(', ')}`);
  const care = [
    counts.readyForDischarge && plural(counts.readyForDischarge, 'case') + ' ready for discharge',
    counts.intake && plural(counts.intake, 'case') + ' awaiting intake',
  ].filter(Boolean);
  if (care.length) areas.push(`Care: ${care.join(', ')}`);
  const adoption = [
    counts.returns && plural(counts.returns, 'return request'),
    counts.followUpsOverdue && plural(counts.followUpsOverdue, 'follow-up') + ' overdue',
    counts.applications && plural(counts.applications, 'application') + ' to screen',
    counts.awaitingRelease && plural(counts.awaitingRelease, 'adoption') + ' awaiting release',
  ].filter(Boolean);
  if (adoption.length) areas.push(`Adoption: ${adoption.join(', ')}`);
  if (counts.paymentsToVerify) areas.push(`Funds: ${plural(counts.paymentsToVerify, 'donation')} to verify`);
  if (!areas.length) return null;
  const urgent = counts.criticalReview + counts.specialized + counts.transitEnded;
  return {
    title: urgent > 0 ? `Today: ${plural(urgent, 'urgent item')} first` : 'Today on the dashboard',
    body: areas.join(' · '),
  };
}

/// Claims older than ALERT_CLAIM_DELETE_HOURS can be deleted.
function claimDeletable(claim, nowMs) {
  const at = ms(claim && claim.at);
  return at == null || nowMs - at >= ALERT_CLAIM_DELETE_HOURS * 60 * 60 * 1000;
}

module.exports = {
  ALERT_CLAIM_TTL_HOURS,
  ALERT_CLAIM_DELETE_HOURS,
  DIGEST_CASE_STATUSES,
  ms,
  digestCounts,
  digestMessage,
  claimDeletable,
};
