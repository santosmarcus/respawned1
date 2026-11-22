const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./dashboard_digest_rules');

const NOW = Date.UTC(2026, 10, 17, 0, 0, 0);
const DAY = 24 * 60 * 60 * 1000;

test('counts follow the Priority actions groups', () => {
  const c = r.digestCounts({
    cases: [
      {status: 'pending', urgency: 'Critical'},
      {status: 'verifying', urgency: 'Low'},
      {status: 'accepted'},
      {status: 'accepted_pending_clinic'},
      {status: 'needs_specialized_assistance'},
      {status: 'ended'},
      {status: 'in_treatment', readyForDischarge: true},
      {status: 'in_treatment'},
      {status: 'intake'},
    ],
    adoptions: [
      {status: 'pending'},
      {status: 'approved'},
      {status: 'adopted', returnRequest: {status: 'pendingReview'}},
      {status: 'adopted', returnRequest: {status: 'intake'}},
    ],
    followUps: [{scheduledDate: NOW - DAY}, {scheduledDate: NOW + DAY}],
    payments: [{status: 'needs_review'}, {status: 'paid'}],
    nowMs: NOW,
  });
  assert.equal(c.criticalReview, 1);
  assert.equal(c.review, 1);
  assert.equal(c.needsTransport, 1);
  assert.equal(c.needsClinic, 1);
  assert.equal(c.specialized, 1);
  assert.equal(c.transitEnded, 1);
  assert.equal(c.readyForDischarge, 1);
  assert.equal(c.intake, 1);
  assert.equal(c.applications, 1);
  assert.equal(c.awaitingRelease, 1);
  assert.equal(c.returns, 1);
  assert.equal(c.followUpsOverdue, 1);
  assert.equal(c.paymentsToVerify, 1);
});

test('no message when nothing needs action', () => {
  assert.equal(r.digestMessage(r.digestCounts({nowMs: NOW})), null);
});

test('urgent items lead the title; areas are listed in order', () => {
  const m = r.digestMessage({...r.digestCounts({nowMs: NOW}), criticalReview: 2, intake: 1, applications: 1});
  assert.equal(m.title, 'Today: 2 urgent items first');
  assert.match(m.body, /^Rescue: 2 critical reports to assess · Care: 1 case awaiting intake · Adoption: 1 application to screen$/);
  const calm = r.digestMessage({...r.digestCounts({nowMs: NOW}), paymentsToVerify: 1});
  assert.equal(calm.title, 'Today on the dashboard');
  assert.equal(calm.body, 'Funds: 1 donation to verify');
});

test('lapsed claims are deleted after 48 hours', () => {
  const h = 60 * 60 * 1000;
  assert.equal(r.claimDeletable({at: NOW - 47 * h}, NOW), false);
  assert.equal(r.claimDeletable({at: NOW - 48 * h}, NOW), true);
  assert.equal(r.claimDeletable({}, NOW), true);
});

test('the case status list stays within one Firestore in query', () => {
  assert.ok(r.DIGEST_CASE_STATUSES.length <= 30);
});

test('surrenders and reporter-led reports in review are left out of the digest', () => {
  const {digestCounts} = require('./dashboard_digest_rules');
  const c = digestCounts({
    nowMs: 0,
    cases: [
      {status: 'pending', urgency: 'Critical', orgInvolvement: 'independent_report'},
      {status: 'pending', orgInvolvement: 'not_org_facilitated'},
      {status: 'pending', urgency: 'Critical'},
    ],
  });
  assert.strictEqual(c.criticalReview, 1);
  assert.strictEqual(c.review, 0);
});
