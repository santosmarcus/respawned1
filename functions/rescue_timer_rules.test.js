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

test('per-animal paths are not whole-case completions', () => {
  const c = {status: 'intake', intakeReceivedAt: received, animals: [{postTreatmentAction: 'intake'}]};
  assert.strictEqual(intakeCompletionDue(c, [0]), false);
});

const {animalsDueForIntakeCompletion, stageSummary, derivedCaseStatus} = require('./rescue_timer_rules');

test('per-animal intake: received animals sent to Intake with a record', () => {
  const c = {
    status: 'in_treatment',
    animals: [
      {postTreatmentAction: 'intake', receivedAt: received}, // due
      {postTreatmentAction: 'intake'}, // not received yet
      {}, // still in treatment
      {postTreatmentAction: 'intake', receivedAt: received, intakeCompletedAt: received}, // done
      {postTreatmentAction: 'transfer', receivedAt: received},
    ],
  };
  assert.deepStrictEqual(animalsDueForIntakeCompletion(c, [0, 1, 2, 3, 4]), [0]);
  // No record for animal 0 yet.
  assert.deepStrictEqual(animalsDueForIntakeCompletion(c, [1]), []);
  // Admitted from an existing record: no linked record needed.
  assert.deepStrictEqual(animalsDueForIntakeCompletion({...c, sourceAnimalRecordId: 'a1'}, []), [0]);
  assert.deepStrictEqual(animalsDueForIntakeCompletion({status: 'intake', intakeReceivedAt: received}, [0]), []);
});

test('stage counts and case status follow the animals', () => {
  const done = {postTreatmentAction: 'intake', intakeCompletedAt: received};
  const treating = {};
  const intake = {postTreatmentAction: 'intake'};
  assert.deepStrictEqual(stageSummary([treating, intake]),
    {activeAnimalStages: ['in_treatment', 'intake'], animalStageCounts: {in_treatment: 1, intake: 1}});
  assert.strictEqual(derivedCaseStatus([treating, done]), 'in_treatment');
  assert.strictEqual(derivedCaseStatus([intake, done]), 'intake');
  assert.strictEqual(derivedCaseStatus([done, {postTreatmentAction: 'transfer'}, {outcome: 'deceased'}]), 'completed');
  // Waiting for the adopter to collect it still counts as Treatment.
  assert.strictEqual(derivedCaseStatus([done, {postTreatmentAction: 'release'}]), 'in_treatment');
  assert.deepStrictEqual(stageSummary([done]), {activeAnimalStages: [], animalStageCounts: {}});
});
