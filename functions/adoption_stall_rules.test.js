// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {
  noShowOutcome, bookingClockStart, bookingStepDue,
  BOOKING_REMINDER_DAYS, BOOKING_WITHDRAW_DAYS,
} = require('./adoption_stall_rules');

const DAY = 24 * 60 * 60 * 1000;
const submitted = Date.UTC(2026, 10, 1, 2, 0);

test('first no-show lets them rebook, the second closes', () => {
  assert.strictEqual(noShowOutcome(1), 'rebook');
  assert.strictEqual(noShowOutcome(2), 'close');
  assert.strictEqual(noShowOutcome(3), 'close');
});

test('the booking clock restarts at the last no-show', () => {
  assert.strictEqual(bookingClockStart({createdMs: submitted, lastNoShowMs: null}), submitted);
  assert.strictEqual(bookingClockStart({createdMs: submitted, lastNoShowMs: submitted + 5 * DAY}), submitted + 5 * DAY);
  assert.strictEqual(bookingClockStart({createdMs: null, lastNoShowMs: undefined}), null);
});

test('nothing before 3 days', () => {
  const nowMs = submitted + (BOOKING_REMINDER_DAYS * DAY) - 1;
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs, sent: null}), null);
});

test('one reminder after 3 days', () => {
  const nowMs = submitted + BOOKING_REMINDER_DAYS * DAY;
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs, sent: null}), 'remind');
  const sent = {forStart: submitted, remind: nowMs};
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs: nowMs + DAY, sent}), null);
});

test('withdrawn after 14 days, once', () => {
  const nowMs = submitted + BOOKING_WITHDRAW_DAYS * DAY;
  const reminded = {forStart: submitted, remind: submitted + 3 * DAY};
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs, sent: reminded}), 'withdraw');
  // First seen that late: withdrawn without a reminder first.
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs, sent: null}), 'withdraw');
  const done = {...reminded, withdraw: nowMs};
  assert.strictEqual(bookingStepDue({clockStartMs: submitted, nowMs: nowMs + DAY, sent: done}), null);
});

test('a new clock start (missed interview) resets the reminders', () => {
  const restart = submitted + 10 * DAY;
  const oldSent = {forStart: submitted, remind: submitted + 3 * DAY};
  const nowMs = restart + BOOKING_REMINDER_DAYS * DAY;
  assert.strictEqual(bookingStepDue({clockStartMs: restart, nowMs, sent: oldSent}), 'remind');
});
