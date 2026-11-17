// Pure decisions for unanswered organization referrals
// (followUpCaseReferrals in functions/index.js). No Firebase here, so
// `node --test` can check them directly.

// Proposed timings, pending the organization's confirmation. Keep equal to
// kReferralReminderHours / kReferralReturnHours in
// lib/core/models/rescue/referral_type.dart.
const REFERRAL_REMINDER_HOURS = 24;
const REFERRAL_RETURN_HOURS = 48;

const HOUR_MS = 60 * 60 * 1000;

/// What to do now with a referral still waiting for an answer.
/// [referredAtMs] when it was sent; [reminded] whether the receiving
/// organization was already reminded for this referral.
///   -> 'return' (give the case back to the referring organization),
///      'remind' (remind the receiving organization once), or null.
function referralStepDue({referredAtMs, nowMs, reminded}) {
  if (typeof referredAtMs !== 'number' || !Number.isFinite(referredAtMs)) return null;
  const waited = nowMs - referredAtMs;
  if (waited >= REFERRAL_RETURN_HOURS * HOUR_MS) return 'return';
  if (waited >= REFERRAL_REMINDER_HOURS * HOUR_MS && !reminded) return 'remind';
  return null;
}

module.exports = {
  REFERRAL_REMINDER_HOURS,
  REFERRAL_RETURN_HOURS,
  referralStepDue,
};
