const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./rescue_adoption_rules');

const H = 60 * 60 * 1000;

test('pickup: reminder once, a day before the deadline; missed after it', () => {
  const deadlineMs = 100 * H;
  assert.equal(r.pickupStep({deadlineMs}, 70 * H), 'none');
  assert.equal(r.pickupStep({deadlineMs}, 77 * H), 'remind');
  assert.equal(r.pickupStep({deadlineMs, reminderSentAt: 1}, 77 * H), 'none');
  assert.equal(r.pickupStep({deadlineMs, reminderSentAt: 1}, 100 * H), 'missed');
  assert.equal(r.pickupStep({deadlineMs, collectedAt: 1}, 200 * H), 'none');
  assert.equal(r.pickupStep({deadlineMs, missedAt: 1}, 200 * H), 'none');
  assert.equal(r.pickupStep(null, 0), 'none');
  assert.equal(r.pickupStep({}, 0), 'none');
});

test('missed pickup goes to the shelter when it has room, else to referral', () => {
  assert.equal(r.missedPickupOutcome({capacity: 10, housed: 5}), 'shelter');
  assert.equal(r.missedPickupOutcome({capacity: 10, housed: 9}), 'shelter');
  assert.equal(r.missedPickupOutcome({capacity: 10, housed: 10}), 'refer');
  assert.equal(r.missedPickupOutcome({capacity: 10, housed: 9, incoming: 2}), 'refer');
  // No capacity set: nothing says the shelter is full.
  assert.equal(r.missedPickupOutcome({capacity: null, housed: 50}), 'shelter');
});

test('housed animals match the app classifier', () => {
  assert.equal(r.isCurrentlyHoused({adoptionStatus: 'adoptable'}), true);
  assert.equal(r.isCurrentlyHoused({adoptionStatus: 'reserved'}), true);
  assert.equal(r.isCurrentlyHoused({adoptionStatus: 'adopted'}), false);
  assert.equal(r.isCurrentlyHoused({archived: true}), false);
  assert.equal(r.isCurrentlyHoused({status: 'deceased'}), false);
});

test('animals waiting for the adopter move to intake or back to no action', () => {
  const animals = [
    {postTreatmentAction: 'release', releaseAdopterId: 'u1'},
    {postTreatmentAction: 'transfer'},
    {postTreatmentAction: 'release', releaseCompletedAt: 'done'},
  ];
  const shelter = r.animalsAfterMissedPickup(animals, null, 'shelter', 'now');
  assert.equal(shelter[0].postTreatmentAction, 'intake');
  assert.equal(shelter[0].pickupMissedAt, 'now');
  assert.equal(shelter[0].releaseAdopterId, undefined);
  assert.equal(shelter[1].postTreatmentAction, 'transfer');
  assert.equal(shelter[2].postTreatmentAction, 'release');
  assert.equal(r.caseStatusAfterMissedPickup(shelter, 'shelter'), 'intake');

  const refer = r.animalsAfterMissedPickup(animals, [0], 'refer', 'now');
  assert.equal(refer[0].postTreatmentAction, null);
  assert.equal(r.caseStatusAfterMissedPickup(refer, 'refer'), 'in_treatment');
  assert.equal(animals[0].postTreatmentAction, 'release', 'input is not mutated');

  // Legacy case with no animals[].
  assert.equal(r.caseStatusAfterMissedPickup([], 'shelter'), 'intake');
  assert.equal(r.caseStatusAfterMissedPickup([], 'refer'), 'in_treatment');
});

test('stage summary and status match the app helpers', () => {
  const waiting = [{postTreatmentAction: 'release'}, {postTreatmentAction: 'intake'}];
  assert.deepEqual(r.stageSummary(waiting).animalStageCounts, {in_treatment: 1, intake: 1});
  assert.equal(r.deriveCaseStatus(waiting), 'in_treatment');
  assert.equal(r.deriveCaseStatus([{postTreatmentAction: 'release', releaseCompletedAt: 'x'}]), 'completed');
  assert.equal(r.deriveCaseStatus([]), null);
  assert.deepEqual(r.stageSummary([]), {});
});

test('the case mirrors the request and a new request after a decline replaces it', () => {
  const m = r.caseAdoptionRequestOf('a1', {status: 'rejected', rejectionNotes: 'No yard', personal: {adopterId: 'u', adopterName: 'Ana'}});
  assert.deepEqual(m, {applicationId: 'a1', adopterId: 'u', adopterName: 'Ana', status: 'rejected', closedReason: 'No yard'});
  assert.equal(r.shouldMirrorRequest(null, 'a1', 'pending'), true);
  assert.equal(r.shouldMirrorRequest({applicationId: 'a1', status: 'pending'}, 'a1', 'approved'), true);
  assert.equal(r.shouldMirrorRequest({applicationId: 'a1', status: 'rejected'}, 'a2', 'pending'), true);
  assert.equal(r.shouldMirrorRequest({applicationId: 'a1', status: 'approved'}, 'a2', 'pending'), false);
  assert.equal(r.shouldMirrorRequest({applicationId: 'a2', status: 'pending'}, 'a1', 'withdrawn'), false);
});
