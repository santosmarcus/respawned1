// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {referralStepDue, REFERRAL_REMINDER_HOURS, REFERRAL_RETURN_HOURS} = require('./referral_rules');

const HOUR = 60 * 60 * 1000;
const sent = Date.UTC(2026, 10, 17, 1, 0);

test('nothing before the reminder time', () => {
  const nowMs = sent + (REFERRAL_REMINDER_HOURS - 1) * HOUR;
  assert.strictEqual(referralStepDue({referredAtMs: sent, nowMs, reminded: false}), null);
});

test('one reminder at 24 hours', () => {
  const nowMs = sent + REFERRAL_REMINDER_HOURS * HOUR;
  assert.strictEqual(referralStepDue({referredAtMs: sent, nowMs, reminded: false}), 'remind');
  assert.strictEqual(referralStepDue({referredAtMs: sent, nowMs: nowMs + HOUR, reminded: true}), null);
});

test('returned at 48 hours, reminded or not', () => {
  const nowMs = sent + REFERRAL_RETURN_HOURS * HOUR;
  assert.strictEqual(referralStepDue({referredAtMs: sent, nowMs, reminded: true}), 'return');
  assert.strictEqual(referralStepDue({referredAtMs: sent, nowMs, reminded: false}), 'return');
});

test('a referral without a sent time is left alone', () => {
  assert.strictEqual(referralStepDue({referredAtMs: undefined, nowMs: sent, reminded: false}), null);
});
