// Refund policy decisions (refund request flow). Used by
// recordDonationReversal in campaigns.js and paymongo_refunds.js. No
// Firebase here, so `node --test` checks them.
//
// Keep in step with lib/core/models/donation/refund_policy.dart.

/// Version of the refund terms the donor accepts before paying and before
/// requesting a refund. Change it whenever the terms change.
const REFUND_TERMS_VERSION = '2026-11-18';

/// Days after paying in which a donor may ask for a refund.
const REQUEST_DAYS = 7;
/// Unauthorized payments may be reported for longer.
const UNAUTHORIZED_REQUEST_DAYS = 60;

/// Why a donor may ask, and the PayMongo reason each one is sent as.
const REASONS = {
  duplicate: 'duplicate',
  wrong_amount: 'requested_by_customer',
  unauthorized: 'fraudulent',
  campaign_closed: 'requested_by_customer',
  animal_outcome: 'requested_by_customer',
};

/// How long PayMongo accepts a refund after payment, per method (days).
/// QR Ph refunds go through a link the donor must claim, so they are
/// handled by hand here; anything unknown is handled by hand too.
const PAYMONGO_WINDOW_DAYS = {
  card: 60,
  gcash: 180,
  grab_pay: 90,
  paymaya: 365,
};

const DAY_MS = 86400000;

/// Whether a donor's request can be accepted now; null when it can.
function requestBlocker(donation, reason, {uid, nowMs}) {
  if (!donation) return 'Donation not found.';
  if (donation.userId !== uid) return 'Only the donor can ask for a refund.';
  if (donation.type === 'inkind') return 'In-kind pledges are cancelled, not refunded.';
  if (donation.status === 'reversed') return 'This donation was already refunded.';
  if (!(typeof donation.amount === 'number' && donation.amount > 0)) return 'This record has no amount to refund.';
  if (donation.refundRequest) return 'A refund was already requested for this donation.';
  if (!Object.prototype.hasOwnProperty.call(REASONS, reason)) return 'Choose why you are asking for a refund.';
  const paidMs = typeof donation.paidAtMs === 'number' ? donation.paidAtMs : null;
  if (paidMs === null) return null;
  const days = reason === 'unauthorized' ? UNAUTHORIZED_REQUEST_DAYS : REQUEST_DAYS;
  if (nowMs - paidMs > days * DAY_MS) {
    return `Refunds can be requested within ${days} days of payment.`;
  }
  return null;
}

/// How the approved refund is paid back: through PayMongo, or by hand
/// (with why). [payment] is donationPayments/{id}.
function refundRoute(payment, {nowMs}) {
  if (!payment || payment.provider !== 'paymongo' || !payment.paymongoPaymentId) {
    return {route: 'manual', why: 'This donation was not paid through PayMongo.'};
  }
  if (payment.livemode !== true) {
    return {route: 'manual', why: 'Test-mode payments cannot be refunded through PayMongo.'};
  }
  const method = payment.paymentMethodType || payment.paymentMethod;
  const days = PAYMONGO_WINDOW_DAYS[method];
  if (!days) return {route: 'manual', why: 'PayMongo cannot refund this payment method from here.'};
  const paidMs = typeof payment.paidAtMs === 'number' ? payment.paidAtMs : null;
  if (paidMs !== null && nowMs - paidMs > days * DAY_MS) {
    return {route: 'manual', why: `PayMongo only refunds this payment method within ${days} days.`};
  }
  return {route: 'paymongo', why: null};
}

module.exports = {
  REFUND_TERMS_VERSION,
  REQUEST_DAYS,
  UNAUTHORIZED_REQUEST_DAYS,
  REASONS,
  PAYMONGO_WINDOW_DAYS,
  requestBlocker,
  refundRoute,
};
