const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./donation_rules');

test('a refund is refused for in-kind, empty or already-spent money', () => {
  const money = {available: 50000}; // ₱500.00
  assert.equal(r.reversalBlocker(null, money, 100), 'Donation not found.');
  assert.match(r.reversalBlocker({type: 'inkind'}, money, 0), /cancelled, not refunded/);
  assert.match(r.reversalBlocker({type: 'donation'}, money, 0), /no amount/);
  assert.equal(r.reversalBlocker({type: 'donation'}, money, 50000), null);
  assert.match(r.reversalBlocker({type: 'donation'}, money, 50001), /Only ₱500.00 .* Void a spending record/);
  // Campaign deleted: nothing to check the balance against.
  assert.equal(r.reversalBlocker({type: 'donation'}, null, 50001), null);
  // Repeat call on a refunded record is not an error.
  assert.equal(r.reversalBlocker({type: 'donation', status: 'reversed'}, {available: 0}, 50001), null);
});

test('donor count never goes below zero', () => {
  assert.equal(r.donorCountChange(3), -1);
  assert.equal(r.donorCountChange(0), 0);
  assert.equal(r.donorCountChange(undefined), 0);
});

test('history entries are mirrored once, with readable wording', () => {
  assert.equal(r.shouldMirrorHistory('allocation_recorded'), true);
  assert.equal(r.shouldMirrorHistory('offline_donation_recorded'), false);
  assert.equal(r.shouldMirrorHistory('allocation_voided'), false);
  assert.equal(r.shouldMirrorHistory('donation_reversed'), false);
  assert.equal(r.shouldMirrorHistory(''), false);
  assert.equal(r.historyAction('inkind_received'), 'In-kind donation received');
  assert.equal(r.historyAction('some_new_type'), 'some new type');
  assert.equal(r.historyCategory('allocation_recorded'), 'expenses');
  assert.equal(r.historyCategory('publish'), 'donations');
  assert.deepEqual(r.historyDetails({type: 'x', byUid: 'u', byName: 'n', at: 1, amount: 5}), {amount: 5});
});

test('stock ids and units', () => {
  assert.equal(r.stockItemId('Food & Water'), 'inkind_food_water');
  assert.equal(r.stockItemId(''), 'inkind_others');
  assert.equal(r.stockItemId(null), 'inkind_others');
  assert.equal(r.stockUnit({unit: ' kg '}), 'kg');
  assert.equal(r.stockUnit(null), 'pcs');
});

test('acknowledgment number', () => {
  assert.equal(r.acknowledgmentNumber('abcdefghijk'), 'ACK-ABCDEFGH');
});
