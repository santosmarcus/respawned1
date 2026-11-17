// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {quarantineDue, intakeCompletionDue} = require('./rescue_timer_rules');

const end = Date.UTC(2026, 10, 20, 0, 0);

test('an active quarantine ends at its scheduled end', () => {
  assert.strictEqual(quarantineDue({status: 'active', scheduledEndMs: end, nowMs: end - 1}), false);
  assert.strictEqual(quarantineDue({status: 'active', scheduledEndMs: end, nowMs: end}), true);
});

test('only active quarantines with an end date', () => {
  assert.strictEqual(quarantineDue({status: 'completed', scheduledEndMs: end, nowMs: end + 1}), false);
  assert.strictEqual(quarantineDue({status: 'active', scheduledEndMs: null, nowMs: end + 1}), false);
});

const received = {seconds: 1};

test('intake completes once every animal has its record', () => {
  const c = {status: 'intake', intakeReceivedAt: received, animals: [{}, {}]};
  assert.strictEqual(intakeCompletionDue(c, [0]), false);
  assert.strictEqual(intakeCompletionDue(c, [0, 1]), true);
  // Duplicates and out-of-range indexes don't count.
  assert.strictEqual(intakeCompletionDue(c, [0, 0, 5]), false);
});

test('a legacy single-animal case needs one record', () => {
  const c = {status: 'intake', intakeReceivedAt: received};
  assert.strictEqual(intakeCompletionDue(c, []), false);
  assert.strictEqual(intakeCompletionDue(c, [0]), true);
});

test('not before the animal is received, or outside Intake', () => {
  assert.strictEqual(intakeCompletionDue({status: 'intake', animals: [{}]}, [0]), false);
  assert.strictEqual(intakeCompletionDue({status: 'completed', intakeReceivedAt: received}, [0]), false);
});

test('a case admitted from an existing record already has it', () => {
  const c = {status: 'intake', intakeReceivedAt: received, sourceAnimalRecordId: 'a1'};
  assert.strictEqual(intakeCompletionDue(c, []), true);
});

test('per-animal paths are left to the app', () => {
  const c = {status: 'intake', intakeReceivedAt: received, animals: [{postTreatmentAction: 'intake'}]};
  assert.strictEqual(intakeCompletionDue(c, [0]), false);
});
