// Campaign money arithmetic, shared by campaigns.js (allocations,
// transfers, archive checks) and sponsorship_funding_rules.js. Pure: no
// Firebase, so `node --test` checks it. Every peso amount is compared in
// centavos to avoid floating-point drift.
//
// Fields on campaigns/{id} (pesos), each written once by the callable that
// records the money (campaigns.js, paymongo.js), so nothing is counted twice:
//   collectedAmount       verified donations, minus refunds and reversals
//   allocatedAmount       recorded spending (expenses, cash-outs), minus voids
//   transferredOutAmount  excess moved to other campaigns
//   transferredInAmount   excess received from other campaigns

const centavos = (pesos) => Math.round(Number(pesos) * 100);
const pesos = (c) => c / 100;
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

// Same fallback as DonationListing.fromFirestore for docs without `status`.
function statusOf(c) {
  if (typeof c.status === 'string' && c.status) return c.status;
  return c.isActive === false ? 'closed' : 'active';
}

function moneyOf(c) {
  const collected = centavos(num(c.collectedAmount));
  const target = centavos(num(c.targetAmount));
  const allocated = centavos(num(c.allocatedAmount));
  const out = centavos(num(c.transferredOutAmount));
  const inn = centavos(num(c.transferredInAmount));
  const available = collected + inn - out - allocated;
  // Excess exists only above a real target, and never counts money that came
  // in by transfer (that was already somebody else's excess).
  const grossExcess = target > 0 ? Math.max(0, collected - target) : 0;
  const eligibleExcess = Math.max(0, Math.min(grossExcess - out, available));
  return {collected, target, allocated, out, inn, available, eligibleExcess};
}

module.exports = {centavos, pesos, num, statusOf, moneyOf};
