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

test('presets match exactly, anything else is custom', () => {
  assert.strictEqual(presetFor(PRESETS.treasurer), 'treasurer');
  assert.strictEqual(presetFor([...PRESETS.animalCare]), 'animalCare');
  assert.strictEqual(presetFor(['care', 'rescue']), 'custom');
  assert.strictEqual(presetFor([]), 'custom');
});

test('legacy members: carer is Animal care, staff is Full staff (+ Facebook when granted)', () => {
  assert.deepStrictEqual(memberPermissions({role: 'carer'}), ['care']);
  assert.deepStrictEqual(memberPermissions({role: 'staff'}), PERMISSIONS.filter((k) => PRESETS.fullStaff.includes(k)));
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
  const treasurer = access('t', {role: 'staff', permissions: PRESETS.treasurer});
  assert.strictEqual(treasurer.isAdmin, false);
  assert.strictEqual(treasurer.preset, 'treasurer');
  assert.strictEqual(treasurer.has('financeManage'), true);
  assert.strictEqual(treasurer.has('rescue'), false);
  assert.strictEqual(access('c', {role: 'carer'}).preset, 'animalCare');
});

test('no members doc but linked: Full staff', () => {
  const a = access('linked', null);
  assert.strictEqual(a.active, true);
  assert.strictEqual(a.isAdmin, false);
  assert.strictEqual(a.preset, 'fullStaff');
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
    ['treasurer', {role: 'staff', permissions: PRESETS.treasurer}],
    ['carer', {role: 'carer'}],
    ['legacy', {role: 'staff'}],
    ['gone', {role: 'admin', status: 'removed'}],
  ]);
  const sort = (a) => [...a].sort();
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, anyOf: ['financeManage']})),
    ['adm', 'owner', 'treasurer']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, anyOf: ['rescue'], linkedUids: ['noDoc']})),
    ['adm', 'legacy', 'noDoc', 'owner']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: 'owner', members, adminsOnly: true})), ['adm', 'owner']);
  assert.deepStrictEqual(sort(selectAudience({ownerId: null, members})), ['adm', 'carer', 'legacy', 'treasurer']);
});

const {planAccessChange} = require('./org_access');

test('access change: Staff with a preset, normalized and named', () => {
  const members = new Map([['owner', {role: 'admin'}], ['s', {role: 'staff'}]]);
  const plan = planAccessChange({ownerId: 'owner', memberUid: 's', member: {role: 'staff'}, members,
    role: 'staff', permissions: ['financeManage', 'insights', 'campaigns']});
  assert.deepStrictEqual(plan.after, {role: 'staff', preset: 'treasurer',
    permissions: ['campaigns', 'financeView', 'financeManage', 'insights']});
  assert.strictEqual(plan.before.preset, 'fullStaff');
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
  assert.strictEqual(toAdmin.before.preset, 'animalCare');
});
