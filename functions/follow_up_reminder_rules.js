// Pure decisions for the daily adoption follow-up reminders
// (sendFollowUpReminders in functions/follow_up_reminders.js). No Firebase
// here, so `node --test` can check them directly.

// Proposed timings, pending the organization's confirmation.
const ADOPTER_REMINDER_DAYS = {due: 0, overdue: 3};
const STAFF_ALERT_DAYS = 7;

// Days are counted on the Philippine calendar (UTC+8, no daylight saving),
// so "due today" means the adopter's today, not UTC's.
const DAY_MS = 24 * 60 * 60 * 1000;
const PH_OFFSET_MS = 8 * 60 * 60 * 1000;

function phDay(ms) {
  return Math.floor((ms + PH_OFFSET_MS) / DAY_MS);
}

/// Whole Philippine days between the follow-up's due date and now
/// (0 = due today, negative = not due yet).
function daysOverdue(scheduledMs, nowMs) {
  return phDay(nowMs) - phDay(scheduledMs);
}

/// Which reminders are due now and not yet sent for this follow-up.
/// [sent] is the follow-up's `autoReminders` map: {forDate, due, overdue,
/// staff} (each a timestamp in ms, or absent). Flags written for a
/// different due date (the follow-up was rescheduled since) don't count,
/// so a rescheduled follow-up gets its reminders again.
///   -> array of 'due' | 'overdue' | 'staff', in that order.
function remindersDue({scheduledMs, nowMs, sent}) {
  const days = daysOverdue(scheduledMs, nowMs);
  if (days < 0) return [];
  const flags = sent && sent.forDate === scheduledMs ? sent : {};
  const out = [];
  // A follow-up first seen when already 3+ days late gets only the
  // overdue reminder, not two pushes on the same morning.
  if (days >= ADOPTER_REMINDER_DAYS.overdue) {
    if (!flags.overdue) out.push('overdue');
  } else if (!flags.due) {
    out.push('due');
  }
  if (days >= STAFF_ALERT_DAYS && !flags.staff) out.push('staff');
  return out;
}

module.exports = {
  ADOPTER_REMINDER_DAYS,
  STAFF_ALERT_DAYS,
  daysOverdue,
  remindersDue,
};
