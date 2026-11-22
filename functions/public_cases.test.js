const test = require('node:test');
const assert = require('node:assert');
const {publicCaseOf} = require('./public_cases');

test('a surrender filed from the form hides the owner address', () => {
  const copy = publicCaseOf({rescueType: 'Pet Surrender', address: '12 Home St', lat: 14.123456, lng: 121.987654});
  assert.strictEqual(copy.address, undefined);
  assert.strictEqual(copy.lat, 14.123);
  assert.strictEqual(copy.lng, 121.988);
});

test('legacy "Surrender" is still treated as a surrender', () => {
  assert.strictEqual(publicCaseOf({rescueType: 'Surrender', address: 'x'}).address, undefined);
});

test('other reports keep their address and carry orgInvolvement', () => {
  const copy = publicCaseOf({rescueType: 'Injury', address: 'Main Rd', orgInvolvement: 'org_assist', urgencyAssessment: {level: 'Low'}});
  assert.strictEqual(copy.address, 'Main Rd');
  assert.strictEqual(copy.orgInvolvement, 'org_assist');
  assert.strictEqual(copy.urgencyAssessment, undefined, 'assessment reasons stay private');
});
