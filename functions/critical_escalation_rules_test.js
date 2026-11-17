const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./critical_escalation_rules');

const MIN = 60 * 1000;

test('escalates an unreviewed Critical report once the threshold passes', () => {
  const c = {urgency: 'Critical', status: 'pending'};
  assert.equal(r.escalationDue(c, {createdAtMs: 1, nowMs: 1 + 29 * MIN}), false);
  assert.equal(r.escalationDue(c, {createdAtMs: 1, nowMs: 1 + 30 * MIN}), true);
  assert.equal(r.escalationDue({...c, status: 'verifying'}, {createdAtMs: 1, nowMs: 1 + 30 * MIN}), true);
});

test('only once, only Critical, only while in review', () => {
  const at = {createdAtMs: 1, nowMs: 1 + 60 * MIN};
  assert.equal(r.escalationDue({urgency: 'Critical', status: 'pending', criticalEscalatedAt: 5}, at), false);
  assert.equal(r.escalationDue({urgency: 'Medium', status: 'pending'}, at), false);
  assert.equal(r.escalationDue({urgency: 'Critical', status: 'accepted'}, at), false);
  assert.equal(r.escalationDue({urgency: 'Critical', status: 'pending'}, {createdAtMs: 0, nowMs: 60 * MIN}), false);
});

test("an organization's own threshold wins over the default", () => {
  const c = {urgency: 'Critical', status: 'pending'};
  assert.equal(r.escalationDue(c, {createdAtMs: 1, nowMs: 1 + 10 * MIN, thresholdMinutes: 10}), true);
  assert.equal(r.escalationMinutes(null), r.DEFAULT_ESCALATION_MINUTES);
  assert.equal(r.escalationMinutes(-5), r.DEFAULT_ESCALATION_MINUTES);
});

test('alerts the owner, or every organization covering the area', () => {
  assert.deepEqual(r.escalationOrgIds({organizationId: 'a', areaOrgIds: ['b']}), ['a']);
  assert.deepEqual(r.escalationOrgIds({organizationId: '', areaOrgIds: ['b', 'c']}), ['b', 'c']);
  assert.deepEqual(r.escalationOrgIds({}), []);
});
