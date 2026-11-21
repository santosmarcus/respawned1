const test = require('node:test');
const assert = require('node:assert');
const inv = require('./org_involvement');

test('older reports without the field are organization workload', () => {
  assert.strictEqual(inv.involvementOf({}), inv.ORG_ASSIST);
  assert.strictEqual(inv.involvementOf({orgInvolvement: 'bogus'}), inv.ORG_ASSIST);
  assert.ok(inv.countsAsOrgWorkload({status: 'pending'}));
  assert.ok(inv.broadcastsForHelp({}));
});

test('surrenders and reporter-led reports are not workload while in review', () => {
  for (const orgInvolvement of [inv.NOT_ORG_FACILITATED, inv.INDEPENDENT_REPORT]) {
    assert.ok(!inv.countsAsOrgWorkload({orgInvolvement, status: 'pending'}));
    assert.ok(!inv.countsAsOrgWorkload({orgInvolvement, status: 'verifying'}));
    assert.ok(inv.countsAsOrgWorkload({orgInvolvement, status: 'accepted'}), 'staff took it on');
    assert.ok(!inv.broadcastsForHelp({orgInvolvement}));
  }
});
