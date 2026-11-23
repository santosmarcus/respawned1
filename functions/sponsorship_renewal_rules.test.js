// Run with: cd functions && npm test   (node --test, no Firebase needed)
const test = require('node:test');
const assert = require('node:assert');
const {
  DAY_MS, renewalSettings, parseRenewalSettings, reminderDue, lapseDue, continuesSponsorship,
} = require('./sponsorship_renewal_rules');

test('listings saved before the settings auto-renew with the defaults', () => {
  assert.deepStrictEqual(renewalSettings({}), {autoRenew: true, noticeDays: 3, graceDays: 3});
  assert.deepStrictEqual(renewalSettings(null), {autoRenew: true, noticeDays: 3, graceDays: 3});
  assert.deepStrictEqual(renewalSettings({renewalNoticeDays: 7, renewalGraceDays: 5}),
      {autoRenew: true, noticeDays: 7, graceDays: 5});
  // Unknown values fall back to the defaults.
  assert.deepStrictEqual(renewalSettings({renewalNoticeDays: 30, renewalGraceDays: -1}),
      {autoRenew: true, noticeDays: 3, graceDays: 3});
});

test('a listing that does not auto-renew has no grace period', () => {
  assert.deepStrictEqual(renewalSettings({autoRenew: false, renewalGraceDays: 7}),
      {autoRenew: false, noticeDays: 3, graceDays: 0});
});

test('the admin form settings are checked', () => {
  assert.deepStrictEqual(parseRenewalSettings({}).value,
      {autoRenew: true, renewalNoticeDays: 3, renewalGraceDays: 3});
  assert.deepStrictEqual(parseRenewalSettings({autoRenew: true, renewalNoticeDays: 5, renewalGraceDays: 7}).value,
      {autoRenew: true, renewalNoticeDays: 5, renewalGraceDays: 7});
  assert.deepStrictEqual(parseRenewalSettings({autoRenew: false, renewalNoticeDays: 1, renewalGraceDays: 7}).value,
      {autoRenew: false, renewalNoticeDays: 1, renewalGraceDays: 0});
  assert.ok(parseRenewalSettings({autoRenew: 'yes'}).error);
  assert.ok(parseRenewalSettings({renewalNoticeDays: 10}).error);
  assert.ok(parseRenewalSettings({renewalGraceDays: 2}).error);
});

test('reminder, lapse and late payment follow the listing settings', () => {
  const now = 1_000 * DAY_MS;
  const s = renewalSettings({renewalNoticeDays: 3, renewalGraceDays: 3});
  assert.strictEqual(reminderDue({dueMs: now + 3 * DAY_MS, nowMs: now, settings: s}), true);
  assert.strictEqual(reminderDue({dueMs: now + 4 * DAY_MS, nowMs: now, settings: s}), false);
  assert.strictEqual(reminderDue({dueMs: now - 1, nowMs: now, settings: s}), false);

  // Two days past the end: still in the grace period, a payment continues it.
  const due = now - 2 * DAY_MS;
  assert.strictEqual(lapseDue({dueMs: due, nowMs: now, settings: s}), false);
  assert.strictEqual(continuesSponsorship({dueMs: due, nowMs: now, settings: s}), true);
  // Past the grace period it lapses and a payment starts a new one.
  assert.strictEqual(lapseDue({dueMs: now - 3 * DAY_MS, nowMs: now, settings: s}), true);
  assert.strictEqual(continuesSponsorship({dueMs: now - 3 * DAY_MS, nowMs: now, settings: s}), false);

  // Without auto-renewal it ends with the month.
  const off = renewalSettings({autoRenew: false});
  assert.strictEqual(lapseDue({dueMs: now, nowMs: now, settings: off}), true);
  assert.strictEqual(continuesSponsorship({dueMs: now + 1, nowMs: now, settings: off}), true);
});
