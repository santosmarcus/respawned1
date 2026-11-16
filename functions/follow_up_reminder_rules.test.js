// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {remindersDue, daysOverdue, STAFF_ALERT_DAYS} = require('./follow_up_reminder_rules');

const DAY = 24 * 60 * 60 * 1000;
// 2026-11-17 09:00 in the Philippines (01:00 UTC).
const due = Date.UTC(2026, 10, 17, 1, 0);

test('nothing before the due date', () => {
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due - DAY, sent: null}), []);
});

test('days follow the Philippine calendar', () => {
  // 23:30 the same Philippine day is still day 0.
  assert.strictEqual(daysOverdue(due, Date.UTC(2026, 10, 17, 15, 30)), 0);
  // 00:30 the next Philippine day (16:30 UTC) is day 1.
  assert.strictEqual(daysOverdue(due, Date.UTC(2026, 10, 17, 16, 30)), 1);
});

test('reminder on the due date, once', () => {
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due, sent: null}), ['due']);
  const sent = {forDate: due, due: due};
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due + DAY, sent}), []);
});

test('second reminder 3 days later, once', () => {
  const sent = {forDate: due, due: due};
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due + 3 * DAY, sent}), ['overdue']);
  const both = {...sent, overdue: due + 3 * DAY};
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due + 4 * DAY, sent: both}), []);
});

test('staff alert after 7 days overdue, once', () => {
  const sent = {forDate: due, due: due, overdue: due + 3 * DAY};
  const at = due + STAFF_ALERT_DAYS * DAY;
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: at, sent}), ['staff']);
  assert.deepStrictEqual(
      remindersDue({scheduledMs: due, nowMs: at + DAY, sent: {...sent, staff: at}}),
      [],
  );
});

test('a follow-up first seen late gets one adopter reminder, not two', () => {
  assert.deepStrictEqual(remindersDue({scheduledMs: due, nowMs: due + 5 * DAY, sent: null}), ['overdue']);
  assert.deepStrictEqual(
      remindersDue({scheduledMs: due, nowMs: due + 8 * DAY, sent: null}),
      ['overdue', 'staff'],
  );
});

test('rescheduling resets the reminders', () => {
  const later = due + 10 * DAY;
  const sentForOldDate = {forDate: due, due: due, overdue: due + 3 * DAY, staff: due + 7 * DAY};
  assert.deepStrictEqual(remindersDue({scheduledMs: later, nowMs: later, sent: sentForOldDate}), ['due']);
});
