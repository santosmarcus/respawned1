const test = require('node:test');
const assert = require('node:assert');
const {deletionBlocker} = require('./account_deletion_rules');

test('a general account can be deleted', () => {
  assert.strictEqual(deletionBlocker({}), null);
});

test('an organization owner cannot, unless the org is only a draft', () => {
  assert.match(deletionBlocker({ownedOrgs: [{name: 'Org A', status: 'approved'}]}), /Org A/);
  assert.match(deletionBlocker({ownedOrgs: [{name: 'Org P', status: 'pending'}]}), /Org P/);
  assert.strictEqual(deletionBlocker({ownedOrgs: [{name: 'Draft', status: 'draft'}]}), null);
});

test('the only Admin cannot; one of several can', () => {
  assert.match(deletionBlocker({isOrgAdmin: true, activeAdminCount: 1}), /only Admin/);
  assert.strictEqual(deletionBlocker({isOrgAdmin: true, activeAdminCount: 2}), null);
  assert.strictEqual(deletionBlocker({isOrgAdmin: false, activeAdminCount: 1}), null);
});

test('a transporter with a live offer cannot', () => {
  assert.match(deletionBlocker({transportStatus: 'accepted'}), /transport/);
  assert.match(deletionBlocker({transportStatus: 'pending'}), /transport/);
  assert.strictEqual(deletionBlocker({transportStatus: 'completed'}), null);
  assert.strictEqual(deletionBlocker({transportStatus: 'rejected'}), null);
});

test('a system admin removing someone gets wording about that account', () => {
  assert.match(deletionBlocker({ownedOrgs: [{name: 'Org A', status: 'approved'}], subject: 'other'}), /This account owns Org A/);
  assert.match(deletionBlocker({isOrgAdmin: true, activeAdminCount: 1, subject: 'other'}), /This account/);
});
