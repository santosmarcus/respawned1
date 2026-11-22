// Run with: cd functions && npm test
// firestore.rules and storage.rules copy the permission lists from
// org_permissions.json (rules can't read files); this keeps them in step.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const DEF = require('./org_permissions.json');

function listIn(rules, fnName) {
  const m = rules.match(new RegExp(String.raw`function ${fnName}\(\)\s*\{\s*return\s*\[([^\]]*)\]`));
  assert.ok(m, `${fnName}() not found`);
  return m[1].split(',').map((x) => x.trim().replace(/^'|'$/g, '')).filter(Boolean);
}

const firestoreRules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const storageRules = fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8');

test('firestore.rules permission lists match org_permissions.json', () => {
  assert.deepStrictEqual(listIn(firestoreRules, 'allPermKeys'), DEF.permissions);
  assert.deepStrictEqual(listIn(firestoreRules, 'defaultStaffPerms'), DEF.presets.staff);
  // Everything but daily care and Facebook posting.
  assert.deepStrictEqual(listIn(firestoreRules, 'opsKeys'),
    DEF.permissions.filter((k) => !['care', 'facebookPublish'].includes(k)));
});

test('firestore.rules independent rescuer lists match org_permissions.json', () => {
  assert.deepStrictEqual(listIn(firestoreRules, 'independentPerms'), DEF.independent.allowed);
  assert.deepStrictEqual(listIn(firestoreRules, 'independentDefaultPerms'), DEF.independent.defaults);
  for (const k of DEF.independent.defaults) assert.ok(DEF.independent.allowed.includes(k));
  for (const never of ['campaigns', 'financeView', 'financeManage', 'volunteers', 'facebookPublish']) {
    assert.ok(!DEF.independent.allowed.includes(never), `${never} is never for independent rescuers`);
  }
});

test('storage.rules default Staff list matches org_permissions.json', () => {
  assert.deepStrictEqual(listIn(storageRules, 'defaultStaffPerms'), DEF.presets.staff);
});

test('one default Staff set, without money permissions, for staff and former carers', () => {
  assert.deepStrictEqual(Object.keys(DEF.presets), ['staff']);
  assert.strictEqual(DEF.legacy.carer, 'staff');
  assert.strictEqual(DEF.legacy.staff, 'staff');
  for (const money of ['campaigns', 'financeView', 'financeManage', 'facebookPublish']) {
    assert.ok(!DEF.presets.staff.includes(money), `${money} must be ticked by hand`);
  }
});
