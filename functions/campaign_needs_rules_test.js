const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./campaign_needs_rules');

const day = (d) => ({toMillis: () => Date.UTC(2026, 10, d)});
const caseData = {
  rescueType: 'Injury',
  condition: 'Hit by a car',
  animals: [{name: 'Bantay', species: 'Dog', condition: 'Hind leg fractured'}, {name: 'Puti', species: 'Dog'}, {species: 'Dog'}],
};
const expenses = [
  {title: 'Leg surgery', category: 'Procedure', amount: 8000, animalIndexes: [0], incurredAt: day(3)},
  {title: 'Clinic confinement', category: 'Confinement', amount: 1000, incurredAt: day(2)}, // shared by 3
  {title: 'Puti vaccine', category: 'Vaccination', amount: 500, animalIndexes: [1], incurredAt: day(4)},
];
const logs = [
  {type: 'Procedure', procedurePerformed: 'Femur pinning', animalIndexes: [0], treatmentDate: day(3), notes: 'Went well'},
  {type: 'Assessment', condition: 'Stable', timestamp: day(2)},
  {type: 'Medication', medicationName: 'Amoxicillin', animalIndexes: [1], timestamp: day(4)},
];

test('expenses for the animal, with an equal share of shared ones; total is the target', () => {
  const {expenseTotal, animalNeeds: n} = r.buildAnimalNeeds({caseData, animalIndex: 0, expenses, logs});
  assert.deepEqual(n.expenses.map((e) => [e.title, e.amount, e.shared]), [
    ['Clinic confinement', 333.34, true],
    ['Leg surgery', 8000, false],
  ]);
  assert.equal(expenseTotal, 8333.34);
  assert.equal(n.expenseTotal, 8333.34);
  // The three shares of the shared ₱1,000 add up exactly.
  const shares = [0, 1, 2].map((i) => r.buildAnimalNeeds({caseData, animalIndex: i, expenses}).animalNeeds
    .expenses.find((e) => e.title === 'Clinic confinement').amount);
  assert.equal(Math.round(shares.reduce((a, b) => a + b, 0) * 100), 100000);
});

test('rescue reason, condition and this animal\'s treatment log, oldest first', () => {
  const {animalNeeds: n} = r.buildAnimalNeeds({caseData, animalIndex: 0, expenses, logs});
  assert.equal(n.rescueType, 'Injury');
  assert.equal(n.reportedCondition, 'Hind leg fractured');
  assert.equal(n.currentCondition, 'Stable');
  assert.deepEqual(n.treatmentLog.map((l) => l.type), ['Assessment', 'Procedure']);
  assert.equal(n.treatmentLog[1].procedure, 'Femur pinning');
  assert.equal(n.animalName, 'Bantay');
});

test('intake: an animal record made from it, or intake marked complete', () => {
  assert.equal(r.intakeComplete({caseData, animalIndex: 0, records: []}), false);
  assert.equal(r.intakeComplete({caseData, animalIndex: 0, records: [{sourceAnimalIndex: 0}]}), true);
  assert.equal(r.intakeComplete({caseData, animalIndex: 1, records: [{sourceAnimalIndex: 0}]}), false);
  const marked = {animals: [{}, {intakeCompletedAt: day(5)}]};
  assert.equal(r.intakeComplete({caseData: marked, animalIndex: 1}), true);
  assert.equal(r.intakeComplete({caseData: {intakeCompletedAt: day(5)}, animalIndex: 0}), true);
});

test('an older single-animal case reads its fields from the case itself', () => {
  const single = {rescueType: 'Illness', condition: 'Mange', name: 'Kulot'};
  const {expenseTotal, animalNeeds: n} = r.buildAnimalNeeds({
    caseData: single, animalIndex: 0, expenses: [{title: 'Meds', amount: 450.5}, {title: 'Bad', amount: 0}],
  });
  assert.equal(expenseTotal, 450.5);
  assert.equal(n.reportedCondition, 'Mange');
  assert.equal(n.animalName, 'Kulot');
  assert.equal(n.expenses[0].shared, false);
});
