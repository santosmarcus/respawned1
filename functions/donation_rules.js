// Pure decisions for the donation gaps 3, 4, 5 and 8 (refunds, the audit
// trail, in-kind stock, offline acknowledgments). Used by functions/
// campaigns.js. No Firebase here, so `node --test` checks them.

/// Donation gap 3: why a donation can't be reversed, or null when it can.
/// [record] is donations/{id}; [money] is campaigns.js moneyOf() of its
/// campaign (centavos), or null when the campaign no longer exists.
function reversalBlocker(record, money, amountCentavos) {
  if (!record) return 'Donation not found.';
  if (record.type === 'inkind') return 'In-kind pledges are cancelled, not refunded.';
  if (record.status === 'reversed') return null; // repeat call: nothing to do
  if (!(amountCentavos > 0)) return 'This record has no amount to refund.';
  if (money && amountCentavos > money.available) {
    const available = (Math.max(0, money.available) / 100).toFixed(2);
    return `Only ₱${available} of this campaign is unspent. Void a spending record before refunding this donation.`;
  }
  return null;
}

/// Donor count after a refund: one fewer, never below zero.
function donorCountChange(numdonors) {
  return typeof numdonors === 'number' && numdonors > 0 ? -1 : 0;
}

/// Donation gap 4: campaign history types and their Audit page wording.
/// Types already written to auditLogs by the function that made them are
/// left out (AUDITED_AT_SOURCE), so nothing appears twice.
const HISTORY_ACTIONS = {
  created: 'Listing created',
  edited: 'Listing edited',
  publish: 'Listing published',
  deactivate: 'Listing deactivated',
  reactivate: 'Listing reactivated',
  close: 'Listing closed',
  archive: 'Listing archived',
  extended: 'Campaign extended',
  relaunched: 'Campaign relaunched',
  extension_declined: 'Campaign closed after its deadline',
  converted_to_general: 'Campaign converted to a general fund',
  allocation_recorded: 'Funds allocated',
  excess_transferred_out: 'Excess transferred out',
  excess_transferred_in: 'Excess transferred in',
  inkind_pledged: 'In-kind pledge made',
  inkind_received: 'In-kind donation received',
  inkind_cancelled: 'In-kind pledge cancelled',
  goal_completed: 'Goal reached',
  deadline_reached: 'Deadline reached below goal',
};

const AUDITED_AT_SOURCE = new Set([
  'offline_donation_recorded', // recordOfflineDonation
  'allocation_voided', // voidAllocation
  'flagged_payment_accepted', // paymongo.js settleFlaggedPayment
  'donation_reversed', // recordDonationReversal
]);

function shouldMirrorHistory(type) {
  return typeof type === 'string' && type.length > 0 && !AUDITED_AT_SOURCE.has(type);
}

function historyAction(type) {
  return HISTORY_ACTIONS[type] || String(type || 'Campaign changed').replace(/_/g, ' ');
}

/// Spending and transfers are Expenses on the Audit page; the rest Donations.
function historyCategory(type) {
  return type === 'allocation_recorded' || type === 'excess_transferred_out' || type === 'excess_transferred_in' ?
    'expenses' : 'donations';
}

/// The history entry without its bookkeeping fields, for newValues.
function historyDetails(entry) {
  const out = {};
  for (const [k, v] of Object.entries(entry || {})) {
    if (['type', 'byUid', 'byName', 'at'].includes(k)) continue;
    out[k] = v;
  }
  return out;
}

/// Donation gap 5: one stock line per in-kind category of an organization,
/// e.g. 'Food & Water' -> 'inkind_food_water'.
function stockItemId(category) {
  const slug = String(category || 'others').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return `inkind_${slug || 'others'}`;
}

/// Unit for a received pledge: the campaign item's unit when the staff
/// picked the item, else pieces.
function stockUnit(item) {
  const unit = item && typeof item.unit === 'string' ? item.unit.trim() : '';
  return unit || 'pcs';
}

/// Donation gap 8: number printed on an offline donation's acknowledgment.
function acknowledgmentNumber(donationId) {
  return `ACK-${String(donationId || '').slice(0, 8).toUpperCase()}`;
}

module.exports = {
  reversalBlocker,
  donorCountChange,
  HISTORY_ACTIONS,
  shouldMirrorHistory,
  historyAction,
  historyCategory,
  historyDetails,
  stockItemId,
  stockUnit,
  acknowledgmentNumber,
};
