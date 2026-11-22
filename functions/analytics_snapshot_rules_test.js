const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./analytics_snapshot_rules');

test('days follow Manila time', () => {
  // 21 Nov 2026 16:30 UTC is 22 Nov 00:30 in Manila.
  assert.equal(r.dayKeyOf(Date.UTC(2026, 10, 21, 16, 30)), '2026-11-22');
  assert.equal(r.dayKeyOf(Date.UTC(2026, 10, 21, 15, 59)), '2026-11-21');
});

test('counts animals in treatment and in the shelter, not documents', () => {
  const nowMs = Date.UTC(2026, 10, 22);
  const s = r.dailySnapshot({
    nowMs,
    maxCapacity: 200,
    cases: [
      {status: 'in_treatment', animals: [{}, {dischargedAt: 1}, {}]},
      {status: 'awaiting_adopter_pickup'},
      {status: 'treatment'}, // on the way to the clinic
      {status: 'pending'},
      {status: 'completed'},
      {status: 'community_adoption'},
      {status: 'in_treatment', isDemo: true},
    ],
    animals: [
      {adoptionStatus: 'adoptable'},
      {adoptionStatus: 'not_ready', careStatus: 'isolation'},
      {adoptionStatus: 'adopted'},
      {status: 'deceased'},
      {archived: true},
    ],
    followUps: [
      {status: 'scheduled', scheduledDate: nowMs - 1},
      {status: 'reminderSent', scheduledDate: {toMillis: () => nowMs - 5}},
      {status: 'scheduled', scheduledDate: nowMs + 1},
      {status: 'submitted', scheduledDate: nowMs - 1},
    ],
  });
  assert.deepEqual(
    {...s},
    {
      version: 1, day: '2026-11-22', inTreatment: 3, inShelter: 2, inIsolation: 1, readyForAdoption: 1,
      shelterCapacity: 200, activeCases: 4, followUpsOverdue: 2,
    },
  );
});

test('no capacity set is stored as null, never 0', () => {
  assert.equal(r.dailySnapshot({nowMs: 0, maxCapacity: null}).shelterCapacity, null);
  assert.equal(r.dailySnapshot({nowMs: 0, maxCapacity: 0}).shelterCapacity, null);
});
