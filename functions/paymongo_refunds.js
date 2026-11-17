// PayMongo Refunds API call for the refund request flow. Not a functions
// module: recordDonationReversal (campaigns.js) uses it. The caller must
// declare the PAYMONGO_SECRET_KEY secret on its function.
// VERIFY the endpoint and fields against PayMongo's current API reference
// before going live (https://developers.paymongo.com/reference/refund-resource).

const PAYMONGO_API_BASE = 'https://api.paymongo.com/v1';
const TIMEOUT_MS = 15000;

class PaymongoRefundError extends Error {
  constructor(httpStatus, codes) {
    super(`PayMongo refund error ${httpStatus}`);
    this.httpStatus = httpStatus;
    this.codes = codes;
  }
}

/// Asks PayMongo to refund [amountCentavos] of payment [paymentId].
/// [reason]: duplicate | fraudulent | requested_by_customer | others.
/// Returns {id, status} of the PayMongo refund (status is usually
/// 'pending' until PayMongo completes it).
async function createPaymongoRefund(secretKey, {paymentId, amountCentavos, reason, notes}) {
  const auth = Buffer.from(`${secretKey}:`).toString('base64');
  const res = await fetch(`${PAYMONGO_API_BASE}/refunds`, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({
      data: {
        attributes: {
          amount: amountCentavos,
          payment_id: paymentId,
          reason,
          ...(notes ? {notes: String(notes).slice(0, 250)} : {}),
        },
      },
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const codes = Array.isArray(json.errors) ? json.errors.map((e) => e && e.code).filter(Boolean) : [];
    throw new PaymongoRefundError(res.status, codes);
  }
  const data = json.data || {};
  return {id: data.id || null, status: (data.attributes && data.attributes.status) || 'pending'};
}

module.exports = {createPaymongoRefund, PaymongoRefundError};
