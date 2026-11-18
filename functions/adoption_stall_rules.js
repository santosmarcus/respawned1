// Pure decisions for stalled adoption applications: interview no-shows and
// pending applications with no interview booked (followUpStalledApplications
// and notifyAdopterOfNoShow in functions/adoptions.js). No Firebase here, so
// `node --test` can check them directly.

// Proposed numbers, pending the organization's confirmation.
// The first missed interview lets the applicant book once more; the second
// closes the application. Keep equal to kMaxInterviewNoShows in
// lib/core/models/adoption/adoption_no_show_rules.dart.
const MAX_INTERVIEW_NO_SHOWS = 2;
// A pending application with no interview booked: remind the applicant
// after this many days, withdraw it after this many.
const BOOKING_REMINDER_DAYS = 3;
const BOOKING_WITHDRAW_DAYS = 14;

const DAY_MS = 24 * 60 * 60 * 1000;

/// After a no-show is recorded, with [noShowCount] counting it:
///   'rebook' (they may book one more interview) or 'close'.
function noShowOutcome(noShowCount) {
  return noShowCount >= MAX_INTERVIEW_NO_SHOWS ? 'close' : 'rebook';
}

/// When the booking clock started: the application was submitted, or the
/// applicant last missed an interview (they need to book again). Null when
/// neither is known.
function bookingClockStart({createdMs, lastNoShowMs}) {
  const times = [createdMs, lastNoShowMs].filter((t) => typeof t === 'number' && Number.isFinite(t) && t > 0);
  return times.length ? Math.max(...times) : null;
}

/// What to do now with a pending application that has no interview booked.
/// [sent] is the application's `bookingReminders` map ({forStart, remind,
/// withdraw}, ms). Stamps for an earlier clock start (the applicant booked
/// and then missed it since) don't count.
///   -> 'withdraw', 'remind', or null.
function bookingStepDue({clockStartMs, nowMs, sent}) {
  if (typeof clockStartMs !== 'number') return null;
  const flags = sent && sent.forStart === clockStartMs ? sent : {};
  const waited = nowMs - clockStartMs;
  if (waited >= BOOKING_WITHDRAW_DAYS * DAY_MS) return flags.withdraw ? null : 'withdraw';
  if (waited >= BOOKING_REMINDER_DAYS * DAY_MS && !flags.remind) return 'remind';
  return null;
}

/// True when staff just confirmed the booked interview: the application
/// moved from Pending (canonical or legacy value) into Interview
/// (AdoptionApplicationRepository.confirmInterview).
function isInterviewConfirmed(beforeStatus, afterStatus) {
  return (beforeStatus === 'pending' || beforeStatus === 'pending_appointment') && afterStatus === 'interview';
}

module.exports = {
  MAX_INTERVIEW_NO_SHOWS,
  isInterviewConfirmed,
  BOOKING_REMINDER_DAYS,
  BOOKING_WITHDRAW_DAYS,
  noShowOutcome,
  bookingClockStart,
  bookingStepDue,
};
