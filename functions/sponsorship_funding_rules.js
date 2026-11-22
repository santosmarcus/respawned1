// Sponsorship funding status (open / fully funded). Pure: no Firebase, so
// `node --test` checks it. Written onto the listing and its animal by
// sponsorship_funding.js whenever the listing's money changes.
//
// The target is the listing's own monthlyAmount: sponsorships have no
// targetAmount (saveCampaign stores 0), and monthlyAmount is the amount the
// organization set as one month of the animal's care. The listing is fully
// funded while its available balance (campaign_money.moneyOf: verified
// donations, minus refunds and reversals, minus recorded expenses and
// cash-outs, plus/minus transfers) covers that month. When spending or a
// refund brings the balance back under it, it is open again: funding never
// closes a sponsorship for good.

const {centavos, pesos, num, statusOf, moneyOf} = require('./campaign_money');

const FUNDING_OPEN = 'open';
const FUNDING_FULLY_FUNDED = 'fully_funded';

// Lifecycle statuses in which a listing can take sponsors (same list as
// OPEN_SPONSORSHIP_STATUSES in campaigns.js).
const LIVE_STATUSES = ['draft', 'active', 'paused'];

function isSponsorship(c) {
  return !!c && (c.type || 'donation') === 'sponsorship';
}

/// {status, targetCentavos, availableCentavos} for a sponsorship listing,
/// or null for any other listing. Without a positive monthly amount there
/// is nothing to be funded against, so it stays open.
function sponsorshipFunding(c) {
  if (!isSponsorship(c)) return null;
  const target = centavos(num(c.monthlyAmount));
  const {available} = moneyOf(c);
  const status = target > 0 && available >= target ? FUNDING_FULLY_FUNDED : FUNDING_OPEN;
  return {status, targetCentavos: target, availableCentavos: available};
}

/// The fields to write on the listing, or null when they are already
/// current (so the trigger that writes them doesn't fire forever).
function listingFundingUpdate(c) {
  const f = sponsorshipFunding(c);
  if (!f) return null;
  const next = {
    fundingStatus: f.status,
    fundingTarget: pesos(f.targetCentavos),
    fundingAvailable: pesos(f.availableCentavos),
  };
  const same = c.fundingStatus === next.fundingStatus &&
    centavos(num(c.fundingTarget)) === f.targetCentavos &&
    centavos(num(c.fundingAvailable)) === f.availableCentavos;
  return same ? null : next;
}

/// What the animal record should say about its sponsorship: the live
/// listing's funding, or null when the listing has ended (the caller then
/// clears it if it still points at this listing).
function animalFundingSummary(campaignId, c) {
  const f = sponsorshipFunding(c);
  if (!f || !LIVE_STATUSES.includes(statusOf(c))) return null;
  return {
    campaignId,
    status: f.status,
    target: pesos(f.targetCentavos),
    available: pesos(f.availableCentavos),
  };
}

/// Whether a new sponsor may start sponsoring this listing. A fully funded
/// listing is taken out of the open opportunities; people already
/// sponsoring it can keep renewing.
function acceptsNewSponsor(c) {
  const f = sponsorshipFunding(c);
  return !f || f.status !== FUNDING_FULLY_FUNDED;
}

module.exports = {
  FUNDING_OPEN, FUNDING_FULLY_FUNDED, LIVE_STATUSES,
  sponsorshipFunding, listingFundingUpdate, animalFundingSummary, acceptsNewSponsor,
};
