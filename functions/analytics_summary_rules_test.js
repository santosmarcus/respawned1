const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./analytics_summary_rules');

const H = 60 * 60 * 1000;

test('months follow Manila time', () => {
  // 31 Oct 2026 17:00 UTC is 1 Nov 01:00 in Manila.
  assert.equal(r.monthKeyOf(Date.UTC(2026, 9, 31, 17)), '2026-11');
  assert.equal(r.monthKeyOf(Date.UTC(2026, 9, 31, 15)), '2026-10');
  const {startMs, endMs} = r.monthRange('2026-11');
  assert.equal(startMs, Date.UTC(2026, 9, 31, 16));
  assert.equal(endMs, Date.UTC(2026, 10, 30, 16));
});

test('previous months, newest first, across a year boundary', () => {
  assert.deepEqual(r.previousMonthKeys(Date.UTC(2026, 1, 10), 3), ['2026-01', '2025-12', '2025-11']);
});

test('summarizes one month and ignores the others', () => {
  const nov = (day) => Date.UTC(2026, 10, day, 4);
  const oct = Date.UTC(2026, 9, 10, 4);
  const s = r.summarizeMonth({
    key: '2026-11',
    cases: [
      {createdAt: nov(2), urgency: 'Critical', rescueType: 'Injury', communityCat: true},
      {createdAt: nov(3), rescueType: 'Injury'},
      {createdAt: oct},
      {closureReason: 'reunited', closedAt: nov(4), animals: [{}, {}]},
      {deceasedAt: nov(5), causeOfDeath: 'Euthanasia: untreatable'},
      {deceasedAt: nov(5), sourceType: 'animalRecordAdmission'},
      {animals: [{postTreatmentAction: 'release', releaseCompletedAt: nov(6)}]},
    ],
    animals: [
      {createdAt: nov(1), adoptedAt: nov(20)},
      {deceasedAt: nov(9), deceasedCause: 'Parvo'},
      {adoptedAt: oct},
    ],
    adoptions: [{createdAt: nov(1), approvedAt: nov(8)}, {createdAt: oct, rejectedAt: nov(2)}],
    donations: [
      {createdAt: nov(1), amount: 500, type: 'donation'},
      {createdAt: nov(1), amount: 250.5, type: 'donation'},
      {createdAt: nov(1), amount: 100, status: 'reversed'},
      {createdAt: nov(1), quantity: 3, type: 'inkind'},
      {createdAt: oct, amount: 1000},
    ],
  });
  assert.equal(s.reports, 2);
  assert.equal(s.criticalReports, 1);
  assert.deepEqual(s.reportsByType, {Injury: 2});
  assert.equal(s.communityCatReports, 1);
  assert.equal(s.returnedToOwner, 2);
  assert.equal(s.euthanasia, 1);
  assert.equal(s.diedInCare, 1);
  assert.equal(s.releasedToReporter, 1);
  assert.equal(s.intake, 1);
  assert.equal(s.adopted, 1);
  assert.equal(s.applications, 1);
  assert.equal(s.applicationsApproved, 1);
  assert.equal(s.applicationsRejected, 1);
  assert.equal(s.donationsCount, 2);
  assert.equal(s.donationsTotal, 750.5);
  assert.equal(s.liveOutcomes, 4);
  assert.equal(s.nonLiveOutcomes, 2);
  assert.equal(s.liveRate, 0.667);
});

test('no finalized outcomes gives no rate, not zero', () => {
  assert.equal(r.summarizeMonth({key: '2026-11'}).liveRate, null);
  assert.ok(H > 0);
});
