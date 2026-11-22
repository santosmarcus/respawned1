const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./sponsorship_funding_rules');
const {moneyOf} = require('./campaign_money');

const listing = (over = {}) => ({type: 'sponsorship', status: 'active', monthlyAmount: 1500, collectedAmount: 0, ...over});

test('donations below the monthly amount keep the sponsorship open', () => {
  assert.equal(r.sponsorshipFunding(listing({collectedAmount: 1499.99})).status, r.FUNDING_OPEN);
  assert.ok(r.acceptsNewSponsor(listing({collectedAmount: 1000})));
});

test('donations that meet the monthly amount make it fully funded and close it to new sponsors', () => {
  assert.equal(r.sponsorshipFunding(listing({collectedAmount: 1500})).status, r.FUNDING_FULLY_FUNDED);
  assert.equal(r.sponsorshipFunding(listing({collectedAmount: 2000})).status, r.FUNDING_FULLY_FUNDED);
  assert.ok(!r.acceptsNewSponsor(listing({collectedAmount: 2000})));
});

test('recorded expenses bringing the balance back under the amount reopen it', () => {
  const funded = listing({collectedAmount: 2000});
  const spent = listing({collectedAmount: 2000, allocatedAmount: 700});
  assert.equal(r.sponsorshipFunding(funded).status, r.FUNDING_FULLY_FUNDED);
  assert.equal(r.sponsorshipFunding(spent).status, r.FUNDING_OPEN);
  assert.ok(r.acceptsNewSponsor(spent));
});

test('refunds and transfers count through the shared money formula', () => {
  // A refund lowers collectedAmount (recordDonationReversal); transfers out lower the balance.
  assert.equal(r.sponsorshipFunding(listing({collectedAmount: 1500, transferredOutAmount: 1})).status, r.FUNDING_OPEN);
  assert.equal(r.sponsorshipFunding(listing({collectedAmount: 1000, transferredInAmount: 500})).status, r.FUNDING_FULLY_FUNDED);
  const c = listing({collectedAmount: 1800, allocatedAmount: 100, transferredInAmount: 50});
  assert.equal(r.sponsorshipFunding(c).availableCentavos, moneyOf(c).available);
});

test('no monthly amount means nothing to fund against: stays open', () => {
  assert.equal(r.sponsorshipFunding(listing({monthlyAmount: 0, collectedAmount: 500})).status, r.FUNDING_OPEN);
});

test('only sponsorships are evaluated', () => {
  assert.equal(r.sponsorshipFunding({type: 'donation', collectedAmount: 10}), null);
  assert.equal(r.listingFundingUpdate({type: 'donation'}), null);
  assert.ok(r.acceptsNewSponsor({type: 'donation'}));
});

test('the listing update is written only when something changed (no trigger loop)', () => {
  const c = listing({collectedAmount: 1500});
  const update = r.listingFundingUpdate(c);
  assert.deepEqual(update, {fundingStatus: r.FUNDING_FULLY_FUNDED, fundingTarget: 1500, fundingAvailable: 1500});
  assert.equal(r.listingFundingUpdate({...c, ...update}), null);
});

test('the animal shows the live listing, and nothing once it has ended', () => {
  const live = r.animalFundingSummary('c1', listing({collectedAmount: 200}));
  assert.deepEqual(live, {campaignId: 'c1', status: r.FUNDING_OPEN, target: 1500, available: 200});
  assert.equal(r.animalFundingSummary('c1', listing({status: 'closed'})), null);
  assert.equal(r.animalFundingSummary('c1', listing({status: 'archived'})), null);
});
