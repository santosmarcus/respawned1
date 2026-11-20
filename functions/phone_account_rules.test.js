const test = require('node:test');
const assert = require('node:assert');
const {phoneVariants, maskEmail, phoneSignUpDecision} = require('./phone_account_rules');

test('phoneVariants accepts the stored PH formats', () => {
  for (const input of ['+639171234567', '639171234567', '09171234567', '9171234567', '+63 917 123 4567']) {
    const v = phoneVariants(input);
    assert.ok(v.includes('+639171234567'), input);
    assert.ok(v.includes('09171234567'), input);
    assert.ok(v.includes('9171234567'), input);
  }
  assert.deepStrictEqual(phoneVariants(''), []);
  assert.deepStrictEqual(phoneVariants('+15551234567'), []);
  assert.deepStrictEqual(phoneVariants('12345'), []);
});

test('maskEmail keeps a hint only', () => {
  assert.strictEqual(maskEmail('marcus@gmail.com'), 'ma***@gmail.com');
  assert.strictEqual(maskEmail('a@x.com'), 'a***@x.com');
  assert.strictEqual(maskEmail(''), '');
  assert.strictEqual(maskEmail('nope'), '');
});

test('a finished account keeps its verified number', () => {
  const d = phoneSignUpDecision({callerFinished: true, callerProviders: ['phone'], holders: [{email: 'a@b.com'}]});
  assert.strictEqual(d.action, 'keep');
});

test('a new sign-up with an unused number keeps it', () => {
  assert.strictEqual(phoneSignUpDecision({callerFinished: false, callerProviders: ['phone'], holders: []}).action, 'keep');
});

test('a new phone-only sign-up for a listed number is removed', () => {
  const d = phoneSignUpDecision({callerFinished: false, callerProviders: ['phone'], holders: [{email: 'owner@gmail.com'}]});
  assert.deepStrictEqual(d, {action: 'deleteAccount', hint: 'ow***@gmail.com'});
});

test('a new email or Google sign-up only loses the number', () => {
  const d = phoneSignUpDecision({callerFinished: false, callerProviders: ['password', 'phone'], holders: [{email: ''}]});
  assert.deepStrictEqual(d, {action: 'unlinkPhone', hint: ''});
});
