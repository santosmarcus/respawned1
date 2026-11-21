// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const r = require('./cash_out_rules');

const opts = {categories: ['Food', 'Transport', 'Other'], idPattern: /^[A-Za-z0-9_-]{1,128}$/};
const line = (extra = {}) => ({campaignId: 'general_org1', category: 'Food', label: 'Dog food', amount: 1500, ...extra});

test('lines need a fund, a purpose, a description and an amount', () => {
  assert.deepStrictEqual(r.validateLines([line()], opts),
      {lines: [{campaignId: 'general_org1', category: 'Food', label: 'Dog food', amountC: 150000}]});
  assert.match(r.validateLines([], opts).error, /at least one/);
  assert.match(r.validateLines([line({campaignId: 'bad/id'})], opts).error, /fund for line 1/);
  assert.match(r.validateLines([line(), line({category: 'Toys'})], opts).error, /what line 2/);
  assert.match(r.validateLines([line({label: '  '})], opts).error, /Describe line 1/);
  assert.match(r.validateLines([line({amount: 0})], opts).error, /more than zero/);
  assert.match(r.validateLines([line({amount: 1.234})], opts).error, /2 decimals/);
  assert.match(r.validateLines(Array(11).fill(line()), opts).error, /at most 10/);
});

const funds = new Map([
  ['general_org1', {organizationId: 'org1', availableC: 500000, title: 'General fund'}],
  ['camp1', {organizationId: 'org1', availableC: 100000, title: 'Vet bills'}],
  ['other', {organizationId: 'org2', availableC: 900000, title: 'Theirs'}],
]);
const cashOut = {amount: 3000, assignedAmount: 0, status: 'needs_assignment'};
const lines = (...ls) => r.validateLines(ls, opts).lines;

test('a cash-out can be split across funds, in parts', () => {
  assert.deepStrictEqual(
      r.planAssignment({cashOut, organizationId: 'org1', funds,
        lines: lines(line({amount: 2000}), line({campaignId: 'camp1', amount: 1000}))}),
      {totalC: 300000, assignedAfterC: 300000, status: 'assigned'});
  assert.deepStrictEqual(
      r.planAssignment({cashOut, organizationId: 'org1', funds, lines: lines(line({amount: 500}))}),
      {totalC: 50000, assignedAfterC: 50000, status: 'partly_assigned'});
  assert.strictEqual(
      r.planAssignment({cashOut: {...cashOut, assignedAmount: 500, status: 'partly_assigned'}, organizationId: 'org1',
        funds, lines: lines(line({amount: 2500}))}).status,
      'assigned');
});

test('never more than is left, more than a fund has, or another organization\'s fund', () => {
  assert.match(r.planAssignment({cashOut, organizationId: 'org1', funds, lines: lines(line({amount: 3001}))}).error,
      /only ₱3,000 is left/);
  assert.match(r.planAssignment({cashOut, organizationId: 'org1', funds,
    lines: lines(line({campaignId: 'camp1', amount: 600}), line({campaignId: 'camp1', amount: 500}))}).error,
  /Vet bills only has ₱1,000 available/);
  assert.match(r.planAssignment({cashOut, organizationId: 'org1', funds, lines: lines(line({campaignId: 'other'}))}).error,
      /another organization/);
  assert.match(r.planAssignment({cashOut, organizationId: 'org1', funds, lines: lines(line({campaignId: 'gone'}))}).error,
      /no longer exists/);
  assert.match(r.planAssignment({cashOut: {...cashOut, status: 'assigned'}, organizationId: 'org1', funds,
    lines: lines(line())}).error, /already been sorted out/);
});

test('reads a PayMongo payout defensively', () => {
  assert.deepStrictEqual(r.payoutFromPaymongo({
    id: 'po_abc123',
    attributes: {amount: 510000, net_amount: 500000, fee: 10000, status: 'paid', paid_at: 1763600000,
      destination: {bank_name: 'BPI', account_number_last4: '1234'}},
  }), {
    payoutId: 'po_abc123', amountC: 500000, grossC: 510000, feeC: 10000, status: 'paid',
    occurredAtMs: 1763600000000, destination: 'BPI ···1234',
  });
  assert.strictEqual(r.payoutFromPaymongo({id: 'po_1', attributes: {amount: 2500}}).amountC, 2500);
  assert.strictEqual(r.payoutFromPaymongo({id: 'po_1', attributes: {}}), null);
  assert.strictEqual(r.payoutFromPaymongo({id: 'bad id', attributes: {amount: 1}}), null);
  assert.strictEqual(r.payoutFromPaymongo(null), null);
});

test('notices: a new cash-out asks where the money went', () => {
  const n = r.noticeFor(null, {source: 'paymongo', amount: 5000, assignedAmount: 0, status: 'needs_assignment'});
  assert.strictEqual(n.type, 'cash_out_needs_assignment');
  assert.strictEqual(n.title, 'Where did this money go?');
  assert.match(n.body, /^₱5,000 was paid out from PayMongo\. Tap to choose/);
  assert.strictEqual(n.actorUid, null);

  const manual = r.noticeFor(null, {source: 'cash', amount: 800, assignedAmount: 0, status: 'needs_assignment',
    recordedBy: 'u1', recordedByName: 'Ana'});
  assert.match(manual.body, /^Ana recorded ₱800 taken out \(Cash on hand\)/);
  assert.strictEqual(manual.actorUid, 'u1');

  const done = r.noticeFor(null, {source: 'bank', amount: 2000, assignedAmount: 2000, status: 'assigned',
    recordedBy: 'u1', recordedByName: 'Ana', lines: [{amount: 2000, campaignTitle: 'General fund'}]});
  assert.strictEqual(done.type, 'cash_out_assigned');
  assert.match(done.body, /Ana took out ₱2,000 \(Bank withdrawal\): ₱2,000 to General fund\./);
});

test('notices: assigning tells the others', () => {
  const before = {source: 'paymongo', amount: 5000, assignedAmount: 0, status: 'needs_assignment', lines: []};
  const part = r.noticeFor(before, {...before, assignedAmount: 2000, status: 'partly_assigned',
    lastActionBy: 'u2', lastActionByName: 'Ben', lines: [{amount: 2000, campaignTitle: 'Vet bills'}]});
  assert.strictEqual(part.type, 'cash_out_needs_assignment');
  assert.match(part.body, /Ben assigned ₱2,000 to Vet bills\. ₱3,000 still needs a fund\./);
  assert.strictEqual(part.actorUid, 'u2');
  const settled = r.noticeFor(before, {...before, status: 'already_recorded', settleNote: 'In general expenses',
    lastActionByName: 'Ben'});
  assert.match(settled.title, /already recorded/);
  assert.strictEqual(r.noticeFor(before, {...before, note: 'edited'}), null);
});

test('a returned payout closes what still waits and flags assigned spending', () => {
  assert.deepStrictEqual(r.returnUpdate({status: 'needs_assignment', assignedAmount: 0}),
      {status: 'returned', payoutReturned: true});
  assert.deepStrictEqual(r.returnUpdate({status: 'partly_assigned', assignedAmount: 200}),
      {status: 'returned', payoutReturned: true});
  assert.deepStrictEqual(r.returnUpdate({status: 'assigned', assignedAmount: 500}), {payoutReturned: true});
  assert.strictEqual(r.returnUpdate({status: 'returned', payoutReturned: true}), null);
  assert.strictEqual(r.returnUpdate(null), null);

  const before = {source: 'paymongo', amount: 5000, assignedAmount: 0, status: 'needs_assignment'};
  const closed = r.noticeFor(before, {...before, status: 'returned', payoutReturned: true});
  assert.strictEqual(closed.type, 'cash_out_returned');
  assert.match(closed.body, /returned the ₱5,000 payout to PayMongo, so it no longer needs a fund/);
  const spent = r.noticeFor({...before, status: 'assigned', assignedAmount: 5000},
      {...before, status: 'assigned', assignedAmount: 5000, payoutReturned: true});
  assert.match(spent.body, /₱5,000 of it was already assigned to funds\. Check that spending/);
});

test('reads the deposit date first', () => {
  assert.strictEqual(
      r.payoutFromPaymongo({id: 'po_1', attributes: {amount: 100, deposited_at: 1763700000, created_at: 1763600000}})
          .occurredAtMs,
      1763700000000);
});
