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
  assert.deepStrictEqual(listIn(firestoreRules, 'fullStaffPerms'), DEF.presets.fullStaff);
  // Everything but daily care and Facebook posting.
  assert.deepStrictEqual(listIn(firestoreRules, 'opsKeys'),
    DEF.permissions.filter((k) => !['care', 'facebookPublish'].includes(k)));
});

test('storage.rules Full staff list matches org_permissions.json', () => {
  assert.deepStrictEqual(listIn(storageRules, 'fullStaffPerms'), DEF.presets.fullStaff);
});

test('the legacy presets exist', () => {
  assert.deepStrictEqual(DEF.presets[DEF.legacy.carer], ['care']);
  assert.ok(DEF.presets[DEF.legacy.staff]);
});
