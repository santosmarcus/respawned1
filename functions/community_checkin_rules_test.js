const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./community_checkin_rules');

const DAY = 24 * 60 * 60 * 1000;

test('the check-in is due two weeks after the claim, and asked once', () => {
  assert.equal(r.checkInDueAtMs(0), 14 * DAY);
  const c = {status: 'scheduled', dueAtMs: 14 * DAY};
  assert.equal(r.checkInRequestDue(c, 13 * DAY), false);
  assert.equal(r.checkInRequestDue(c, 14 * DAY), true);
  assert.equal(r.checkInRequestDue({...c, status: 'requested'}, 20 * DAY), false);
  assert.equal(r.checkInRequestDue({...c, status: 'submitted'}, 20 * DAY), false);
  assert.equal(r.checkInRequestDue(null, 20 * DAY), false);
});

test('the owning organization sees it, else every organization covering the area', () => {
  assert.deepEqual(r.checkInOrgIds({organizationId: 'a'}, {organizationId: 'b'}), ['b']);
  assert.deepEqual(r.checkInOrgIds({organizationId: 'a', areaOrgIds: ['c']}, {}), ['a']);
  assert.deepEqual(r.checkInOrgIds({organizationId: '', areaOrgIds: ['c', 'd']}, {}), ['c', 'd']);
  assert.deepEqual(r.checkInOrgIds(null, null), []);
});
