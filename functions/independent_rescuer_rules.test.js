// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {
  effectiveAccess,
  planAccessChange,
  orgEnabledPermissions,
  independentCaseRefusal,
} = require('./org_access');
const rules = require('./independent_rescuer_rules');
const {deletionBlocker} = require('./account_deletion_rules');

const independent = (extra = {}) => ({
  ownerId: 'owner',
  kind: 'independent',
  verificationStatus: 'approved',
  serviceAreas: [{name: 'Home', lat: 14.6, lng: 121.0, radiusKm: 3}],
  ...extra,
});

test('a shelter has every permission; an independent its defaults, never more than allowed', () => {
  assert.ok(orgEnabledPermissions({}).includes('campaigns'));
  assert.deepStrictEqual(orgEnabledPermissions(independent()), ['rescue', 'animals', 'care']);
  assert.deepStrictEqual(
    orgEnabledPermissions(independent({enabledPermissions: ['rescue', 'adoptions', 'campaigns', 'financeManage']})),
    ['rescue', 'adoptions']);
});

test('even an independent\'s owner gets only its enabled permissions', () => {
  const a = effectiveAccess({uid: 'owner', orgId: 'o', org: independent(), member: null, userOrgId: 'o'});
  assert.strictEqual(a.isAdmin, true);
  assert.deepStrictEqual(a.permissions, ['rescue', 'animals', 'care']);
  assert.strictEqual(a.has('financeView'), false);
  assert.strictEqual(a.has('volunteers'), false);
  const staff = effectiveAccess({
    uid: 's', orgId: 'o', org: independent(), member: {role: 'staff'}, userOrgId: 'o',
  });
  // The default Staff set, minus what an independent doesn't have.
  assert.deepStrictEqual(staff.permissions, ['rescue', 'animals', 'care']);
});

test('an Admin can\'t give an independent\'s Staff a module it doesn\'t have', () => {
  const base = {ownerId: 'owner', memberUid: 's', member: {role: 'staff'}, members: new Map(), role: 'staff'};
  assert.match(planAccessChange({...base, permissions: ['rescue', 'insights'], org: independent()}).error,
    /doesn't have: insights/);
  assert.ok(!planAccessChange({...base, permissions: ['rescue', 'care'], org: independent()}).error);
  assert.ok(!planAccessChange({...base, permissions: ['campaigns'], org: {ownerId: 'owner'}}).error);
});

test('capacity: paused, at the case limit or full of animals refuses; shelters never', () => {
  assert.strictEqual(independentCaseRefusal({}), null);
  assert.strictEqual(independentCaseRefusal(independent()), null);
  assert.match(independentCaseRefusal(independent({acceptingCases: false})), /paused/);
  assert.match(independentCaseRefusal(independent({activeCaseCount: 3})), /3 active case/);
  assert.match(independentCaseRefusal(independent({activeCaseCount: 3, maxActiveCases: 5})) || 'ok', /ok/);
  assert.match(independentCaseRefusal(independent({animalsInCareCount: 5})), /animal/);
});

test('nearby independents: approved, available, under capacity and covering the point, nearest first', () => {
  const orgs = [
    {id: 'far', data: independent({serviceAreas: [{lat: 14.62, lng: 121.0, radiusKm: 3}]})},
    {id: 'near', data: independent()},
    {id: 'outside', data: independent({serviceAreas: [{lat: 14.8, lng: 121.0, radiusKm: 3}]})},
    {id: 'paused', data: independent({acceptingCases: false})},
    {id: 'full', data: independent({activeCaseCount: 3})},
    {id: 'pending', data: independent({verificationStatus: 'pending'})},
    {id: 'shelter', data: {verificationStatus: 'approved', serviceAreas: [{lat: 14.6, lng: 121.0, radiusKm: 10}]}},
    // A saved radius over the 5 km cap is clamped: 20 km away isn't covered.
    {id: 'huge', data: independent({serviceAreas: [{lat: 14.78, lng: 121.0, radiusKm: 50}]})},
  ];
  assert.deepStrictEqual(rules.nearbyIndependents(orgs, 14.6, 121.0).map((x) => x.id), ['near', 'far']);
  assert.deepStrictEqual(rules.nearbyIndependents(orgs, null, null), []);
});

test('head start: Critical reports open to independents at once, others after 15 minutes', () => {
  const t = Date.UTC(2026, 10, 20, 8, 0, 0);
  assert.strictEqual(rules.independentsOpenAtMs(t, 'Critical'), t);
  assert.strictEqual(rules.independentsOpenAtMs(t, 'Medium'), t + 15 * 60 * 1000);
  assert.strictEqual(rules.independentsOpenAtMs(t, undefined), t + 15 * 60 * 1000);
});

test('open cases and animals in care', () => {
  assert.ok(rules.isOpenCaseStatus('pending'));
  assert.ok(rules.isOpenCaseStatus('in_treatment'));
  assert.ok(rules.isOpenCaseStatus('referred'));
  for (const s of ['completed', 'closed', 'rejected', 'cancelled', 'merged']) assert.ok(!rules.isOpenCaseStatus(s));
  assert.ok(rules.isAnimalInCare({adoptionStatus: 'adoptable'}));
  assert.ok(!rules.isAnimalInCare({adoptionStatus: 'adopted'}));
  assert.ok(!rules.isAnimalInCare({status: 'deceased'}));
  assert.ok(!rules.isAnimalInCare({transferStatus: 'pending'}));
});

test('a system admin\'s limits change is checked', () => {
  assert.deepStrictEqual(rules.planLimitsChange({enabledPermissions: ['insights', 'rescue'], memberCap: 3}).update,
    {enabledPermissions: ['rescue', 'insights'], memberCap: 3});
  assert.match(rules.planLimitsChange({enabledPermissions: ['rescue', 'campaigns']}).error, /campaigns/);
  assert.match(rules.planLimitsChange({enabledPermissions: ['animals']}).error, /Rescue cases/);
  assert.match(rules.planLimitsChange({maxActiveCases: 0}).error, /maxActiveCases/);
  assert.match(rules.planLimitsChange({memberCap: 2.5}).error, /memberCap/);
  assert.match(rules.planLimitsChange({}).error, /Nothing/);
});

test('an independent still holding cases or animals can\'t be deleted', () => {
  const holding = [{name: 'Ana', status: 'approved', kind: 'independent', activeCaseCount: 1, animalsInCareCount: 0}];
  assert.match(deletionBlocker({ownedOrgs: holding}), /1 active case/);
  assert.match(deletionBlocker({ownedOrgs: holding, subject: 'other'}), /This rescuer/);
  const empty = [{name: 'Ana', status: 'approved', kind: 'independent'}];
  assert.match(deletionBlocker({ownedOrgs: empty}), /owner's account/);
});
