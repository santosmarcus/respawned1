// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {
  PERMISSIONS,
  PRESETS,
  normalizePerms,
  presetFor,
  memberPermissions,
  effectiveAccess,
  selectAudience,
} = require('./org_access');

const org = {ownerId: 'owner', verificationStatus: 'approved'};
const access = (uid, member, extra = {}) =>
  effectiveAccess({uid, orgId: 'o1', org, member, userOrgId: 'o1', ...extra});

test('normalize: known keys only, sorted, financeManage brings financeView', () => {
  assert.deepStrictEqual(normalizePerms(['care', 'rescue', 'care']), ['rescue', 'care']);
  assert.deepStrictEqual(normalizePerms(['financeManage']), ['financeView', 'financeManage']);
  assert.throws(() => normalizePerms(['rescue', 'everything']), /Unknown permission/);
  assert.throws(() => normalizePerms('rescue'));
});

test('the default Staff set matches exactly, anything else is custom', () => {
  assert.strictEqual(presetFor(PRESETS.staff), 'staff');
  assert.strictEqual(presetFor([...PRESETS.staff, 'financeView']), 'custom');
  assert.strictEqual(presetFor(['care']), 'custom');
  assert.strictEqual(presetFor([]), 'custom');
});

test('legacy members: staff and former carers get the default Staff set (+ Facebook when granted)', () => {
  const defaults = PERMISSIONS.filter((k) => PRESETS.staff.includes(k));
  assert.deepStrictEqual(memberPermissions({role: 'carer'}), defaults);
  assert.deepStrictEqual(memberPermissions({role: 'staff'}), defaults);
  assert.ok(!memberPermissions({role: 'staff'}).includes('financeView'));
  assert.ok(!memberPermissions({role: 'staff'}).includes('campaigns'));
  assert.ok(memberPermissions({role: 'staff', facebookPublisher: true}).includes('facebookPublish'));
  assert.ok(!memberPermissions({role: 'staff'}).includes('financeManage'));
  // An explicit list wins over the role, ignores unknown keys, adds financeView.
  assert.deepStrictEqual(memberPermissions({role: 'carer', permissions: ['financeManage', 'bogus']}),
    ['financeView', 'financeManage']);
});

test('owner and Admins have everything; Staff what they were given', () => {
  assert.strictEqual(access('owner', null).isAdmin, true);
  assert.deepStrictEqual(access('owner', null).permissions, [...PERMISSIONS]);
  assert.strictEqual(access('a', {role: 'admin'}).has('financeManage'), true);
  const treasurer = access('t', {role: 'staff', permissions: ['campaigns', 'financeView', 'financeManage', 'insights']});
  assert.strictEqual(treasurer.isAdmin, false);
  assert.strictEqual(treasurer.preset, 'custom');
  assert.strictEqual(treasurer.has('financeManage'), true);
  assert.strictEqual(treasurer.has('rescue'), false);
  assert.strictEqual(access('c', {role: 'carer'}).preset, 'staff');
  assert.strictEqual(access('c', {role: 'carer'}).has('rescue'), true);
});

test('no members doc but linked: the default Staff set', () => {
  const a = access('linked', null);
  assert.strictEqual(a.active, true);
  assert.strictEqual(a.isAdmin, false);
  assert.strictEqual(a.preset, 'staff');
  assert.strictEqual(a.has('financeManage'), false);
});

test('inactive members, other organizations and unapproved organizations get nothing', () => {
  assert.strictEqual(access('a', {role: 'admin', status: 'removed'}).active, false);
  assert.strictEqual(access('a', {role: 'admin'}, {userOrgId: 'o2'}).active, false);
  assert.strictEqual(access('a', {role: 'admin'}, {org: {...org, verificationStatus: 'pending'}}).active, false);
  assert.strictEqual(access('a', {role: 'admin'}, {org: null}).active, false);
  // The owner can't be made inactive by their members doc.
  assert.strictEqual(access('owner', {role: 'admin', status: 'disabled'}).active, true);
});

test('notification audience: owner, Admins, and Staff holding the permission', () => {
  const members = new Map([
    ['adm', {role: 'admin'}],
    ['treasurer', {role: 'staff', permissions: ['campaigns', 'financeView', 'financeManage', 'insights']}],
    ['carer', {role: 'carer'}],
    ['legacy', {role: 'staff'}],
    ['gone', {role: 'admin', status: 'removed'}],
  ]);
  const sort = (a) => [...a].sort();
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, anyOf: ['financeManage']})),
    ['adm', 'owner', 'treasurer']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, anyOf: ['rescue'], linkedUids: ['noDoc']})),
    ['adm', 'carer', 'legacy', 'noDoc', 'owner']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, adminsOnly: true})), ['adm', 'owner']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: null, members})), ['adm', 'carer', 'legacy', 'treasurer']);
});

const {planAccessChange} = require('./org_access');

test('access change: Staff with money ticked by hand, normalized', () => {
  const members = new Map([['owner', {role: 'admin'}], ['s', {role: 'staff'}]]);
  const plan = planAccessChange({ownerId: 'owner', memberUid: 's', member: {role: 'staff'}, members,
    role: 'staff', permissions: ['financeManage', 'insights', 'campaigns']});
  assert.deepStrictEqual(plan.after, {role: 'staff', preset: 'custom',
    permissions: ['campaigns', 'financeView', 'financeManage', 'insights']});
  assert.strictEqual(plan.before.preset, 'staff');
  const back = planAccessChange({ownerId: 'owner', memberUid: 's', member: {role: 'staff'}, members,
    role: 'staff', permissions: [...PRESETS.staff]});
  assert.strictEqual(back.after.preset, 'staff');
});

test('access change: the owner stays Admin, and one Admin must remain', () => {
  const members = new Map([['owner', {role: 'admin'}], ['a', {role: 'admin'}], ['b', {role: 'admin', status: 'removed'}]]);
  assert.match(planAccessChange({ownerId: 'owner', memberUid: 'owner', member: {role: 'admin'}, members,
    role: 'staff', permissions: []}).error, /owner/);
  // The owner still counts, so another Admin can be made Staff.
  assert.ok(planAccessChange({ownerId: 'owner', memberUid: 'a', member: {role: 'admin'}, members,
    role: 'staff', permissions: ['care']}).after);
  // With no owner on record and no other active Admin, the last Admin can't step down.
  const onlyA = new Map([['a', {role: 'admin'}], ['b', {role: 'admin', status: 'removed'}], ['s', {role: 'staff'}]]);
  assert.match(planAccessChange({ownerId: null, memberUid: 'a', member: {role: 'admin'}, members: onlyA,
    role: 'staff', permissions: ['care']}).error, /At least one/);
});

test('access change: rejects unknown roles, keys and missing members', () => {
  const members = new Map();
  assert.ok(planAccessChange({ownerId: 'o', memberUid: 'x', member: null, members, role: 'staff'}).error);
  assert.ok(planAccessChange({ownerId: 'o', memberUid: 'x', member: {role: 'staff'}, members, role: 'carer'}).error);
  assert.match(planAccessChange({ownerId: 'o', memberUid: 'x', member: {role: 'staff'}, members,
    role: 'staff', permissions: ['god']}).error, /Unknown permission/);
  const toAdmin = planAccessChange({ownerId: 'o', memberUid: 'x', member: {role: 'carer'}, members, role: 'admin'});
  assert.deepStrictEqual(toAdmin.after, {role: 'admin', preset: null, permissions: []});
  assert.strictEqual(toAdmin.before.preset, 'staff');
});
