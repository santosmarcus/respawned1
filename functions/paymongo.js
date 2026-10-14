// PayMongo donations & sponsorships — Hosted Checkout (Checkout Sessions API).
//
// Everything donation_review.dart's _recordToFirebase() used to write from
// the phone (donations/, users/{uid}/history, users/{uid}/donated, campaign
// totals, goal-reached notifications) is written here, only after the
// Checkout Session was re-fetched from PayMongo with the secret key and shows
// a paid payment for exactly the amount this backend priced.

const crypto = require('crypto');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret, defineString} = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const paymongoSecretKey = defineSecret('PAYMONGO_SECRET_KEY');
const paymongoWebhookSecret = defineSecret('PAYMONGO_WEBHOOK_SECRET');
const paymentReturnBaseUrl = defineString('PAYMENT_RETURN_BASE_URL');
// v1 creates the Payment Intent together with the session (lets payment.failed
// be matched to a donation). VERIFY against the API reference before /v2.
const PAYMONGO_API_BASE = 'https://api.paymongo.com/v1';
const PAYMONGO_TIMEOUT_MS = 15000;
const CURRENCY = 'PHP';

// type → label shown in History/Summary. Must match kDonationPaymentMethods in
// lib/features/donation/donation_payment_service.dart, and each type must be
// enabled on the PayMongo account (Dashboard → Settings → Payment Methods).
const PAYMENT_METHOD_LABELS = {
  card: 'Credit Card',
  gcash: 'GCash',
  paymaya: 'Maya',
  grab_pay: 'GrabPay',
  qrph: 'QR Ph',
};

// Pesos. Used when campaigns/{id} doesn't set minAmount / maxAmount.
// VERIFY PayMongo's per-method minimum for your account before going live.
const DEFAULT_MIN_AMOUNT = 20;
const DEFAULT_MAX_AMOUNT = 100000;
const SPONSORSHIP_PERIOD_DAYS = 30;

const PAYMENT_ID_PATTERN = /^[A-Za-z0-9]{20}$/; // Firestore auto-id format
const CAMPAIGN_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const EVENT_ID_PATTERN = /^[A-Za-z0-9_]{1,128}$/;
const OPEN_STATUSES = ['creating', 'pending'];
const STALE_CHECKOUT_HOURS = 24;

const paymentsCol = () => db.collection('donationPayments');

// ── PayMongo API client ─────────────────────────────────────────────────────

class PaymongoApiError extends Error {
  constructor(httpStatus, codes) {
    super(`PayMongo API error ${httpStatus}`);
    this.httpStatus = httpStatus;
    this.codes = codes;
  }
}

function isLiveMode() {
  return paymongoSecretKey.value().startsWith('sk_live_');
}

async function paymongoRequest(method, path, body) {
  const auth = Buffer.from(`${paymongoSecretKey.value()}:`).toString('base64');
  const res = await fetch(`${PAYMONGO_API_BASE}${path}`, {
    method,
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(PAYMONGO_TIMEOUT_MS),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    // Only PayMongo's error codes are kept, never bodies or customer data.
    const codes = Array.isArray(json.errors) ?
      json.errors.map((e) => e && e.code).filter(Boolean) : [];
    throw new PaymongoApiError(res.status, codes);
  }
  return json.data;
}

// VERIFY: retrieve/expire paths against the current API reference.
const retrieveCheckoutSession = (id) =>
  paymongoRequest('GET', `/checkout_sessions/${encodeURIComponent(id)}`);
const expireCheckoutSession = (id) =>
  paymongoRequest('POST', `/checkout_sessions/${encodeURIComponent(id)}/expire`);

function logPaymongoError(where, id, e) {
  logger.error(`${where} failed`, {
    id,
    httpStatus: e instanceof PaymongoApiError ? e.httpStatus : null,
    codes: e instanceof PaymongoApiError ? e.codes : [],
    message: e instanceof PaymongoApiError ? null : String(e && e.message),
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function findPaidPayment(session) {
  const list = (session && session.attributes && session.attributes.payments) || [];
  return list.find((p) => p && p.attributes && p.attributes.status === 'paid') || null;
}

// Same format donation_review.dart used: "October 15, 2026" (Philippine time).
function formatManilaDate(date) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'long', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila',
  }).format(date);
}

// Same fallback order as the old client code.
function donorDisplayName(userData) {
  if (!userData) return 'User';
  const full = `${userData.firstName || ''} ${userData.lastName || ''}`.trim();
  return full || userData.name || 'User';
}

// Moves an open (creating/pending) payment to newStatus; never touches a
// paid / needs_review record. Returns the status afterwards.
async function markIfStillOpen(paymentRef, newStatus, extra = {}) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(paymentRef);
    if (!snap.exists) return 'missing';
    const current = snap.data().status;
    if (!OPEN_STATUSES.includes(current)) return current;
    tx.update(paymentRef, {...extra, status: newStatus, updatedAt: FieldValue.serverTimestamp()});
    return newStatus;
  });
}

// The ONLY place a monetary donation is recorded. `session` must come from
// PayMongo via the secret key (never from a webhook body or the client).
// Idempotent: webhook + sync racing each other credit the campaign once,
// because the status check and every write share one transaction.
// Returns {outcome: 'paid'|'needs_review'|'not_paid'|'mismatch', goal?}.
async function finalizePaidDonation(paymentRef, session) {
  const paid = findPaidPayment(session);
  if (!paid) return {outcome: 'not_paid'};

  const result = await db.runTransaction(async (tx) => {
    // All reads first (Firestore transaction rule).
    const snap = await tx.get(paymentRef);
    if (!snap.exists) return {outcome: 'mismatch'};
    const p = snap.data();
    if (p.status === 'paid' || p.status === 'needs_review') return {outcome: p.status};
    if (p.checkoutSessionId !== session.id ||
        session.attributes.reference_number !== paymentRef.id) {
      return {outcome: 'mismatch'};
    }
    const campaignRef = db.collection('campaigns').doc(p.campaignId);
    const userRef = db.collection('users').doc(p.donorId);
    const [campaignSnap, userSnap] = await Promise.all([tx.get(campaignRef), tx.get(userRef)]);

    const now = FieldValue.serverTimestamp();
    const paidAmount = paid.attributes.amount;
    const paidCurrency = String(paid.attributes.currency || '').toUpperCase();
    if (paidAmount !== p.amountCentavos || paidCurrency !== p.currency) {
      // Money moved, but not for the amount priced here — a human must look.
      tx.update(paymentRef, {
        status: 'needs_review',
        reviewReason: 'amount_mismatch',
        paymongoPaymentId: paid.id,
        updatedAt: now,
      });
      return {outcome: 'needs_review'};
    }

    const methodType = session.attributes.payment_method_used ||
      (paid.attributes.source && paid.attributes.source.type) || p.paymentMethod;
    const methodLabel = PAYMENT_METHOD_LABELS[methodType] || p.paymentMethodLabel;
    const refNumber = `REF-${Date.now()}`;
    const isSponsorship = p.campaignType === 'sponsorship';

    // Same fields donation_review.dart's _recordToFirebase() wrote, plus
    // donationMethod (what HistoryItem.fromFirestore actually reads),
    // campaignName and payment ids.
    const record = {
      userId: p.donorId,
      donorName: p.isAnonymous ? 'Anonymous' : donorDisplayName(userSnap.data()),
      campaignId: p.campaignId,
      campaignName: p.campaignName,
      amount: p.amount,
      amountString: `₱${p.amount.toFixed(2)}`,
      method: methodLabel,
      donationMethod: methodLabel,
      isAnonymous: p.isAnonymous === true,
      timestamp: now,
      createdAt: now,
      date: formatManilaDate(new Date()),
      refNumber,
      type: isSponsorship ? 'sponsorship' : 'donation',
      organizer: p.organizer,
      itemDescription: p.itemDescription,
      paymentId: paymentRef.id,
      paymongoPaymentId: paid.id,
    };
    if (isSponsorship) {
      record.lastPaymentTime = Timestamp.now();
      record.nextChargeDate = Timestamp.fromMillis(Date.now() + SPONSORSHIP_PERIOD_DAYS * 86400000);
      record.status = 'active';
      record.sponsorshipStatus = 'active';
      record.nextChargeAmount = p.amount;
    }

    tx.update(paymentRef, {
      status: 'paid',
      refNumber,
      paidAt: now,
      updatedAt: now,
      paymongoPaymentId: paid.id,
      paymentMethodType: methodType,
      livemode: session.attributes.livemode === true,
      lastPaymentError: FieldValue.delete(),
    });
    // Doc id = paymentId, so the app's local HistoryItem (id = paymentId)
    // and this history doc merge in historyProvider instead of duplicating.
    tx.set(db.collection('donations').doc(paymentRef.id), record);
    tx.set(userRef.collection('history').doc(paymentRef.id), record);
    tx.set(userRef.collection('donated').doc(p.campaignId), {
      donationId: p.campaignId,
      donatedAt: now,
    });

    let goal = null;
    if (campaignSnap.exists) {
      const c = campaignSnap.data();
      const before = Number(c.collectedAmount) || 0;
      const target = Number(c.targetAmount) || 0;
      tx.update(campaignRef, {
        collectedAmount: FieldValue.increment(p.amount),
        numdonors: FieldValue.increment(1),
      });
      if (target > 0 && before < target && before + p.amount >= target) {
        goal = {campaignId: p.campaignId, title: c.title || 'this campaign'};
      }
    }
    return {outcome: 'paid', goal};
  });

  if (result.goal) {
    await notifyGoalReached(result.goal.campaignId, result.goal.title).catch((e) =>
      logger.warn('notifyGoalReached failed', {campaignId: result.goal.campaignId, message: e.message}));
  }
  return result;
}

// Moved from the client (it used to write into other users' notifications).
async function notifyGoalReached(campaignId, title) {
  const snap = await db.collection('donations').where('campaignId', '==', campaignId).get();
  const uids = [...new Set(snap.docs.map((d) => d.data().userId).filter((u) => typeof u === 'string'))];
  for (let i = 0; i < uids.length; i += 400) {
    const batch = db.batch();
    for (const uid of uids.slice(i, i + 400)) {
      batch.set(db.collection('users').doc(uid).collection('notifications').doc(), {
        title: 'Goal Reached',
        message: `A campaign you donated to, ${title}, has reached its goal. Thank you for your contribution!`,
        timestamp: FieldValue.serverTimestamp(),
        isRead: false,
      });
    }
    await batch.commit();
  }
}

// Expires an unpaid session at PayMongo, then re-checks it, so a payment that
// lands at the same moment is credited instead of cancelled.
async function expireAndSettle(paymentRef, sessionId, closedStatus) {
  let session = await retrieveCheckoutSession(sessionId);
  let {outcome} = await finalizePaidDonation(paymentRef, session);
  if (outcome !== 'not_paid') return outcome;

  if (session.attributes.status !== 'expired') {
    try {
      await expireCheckoutSession(sessionId);
    } catch (e) {
      logPaymongoError('expireCheckoutSession', paymentRef.id, e);
    }
    session = await retrieveCheckoutSession(sessionId);
    ({outcome} = await finalizePaidDonation(paymentRef, session));
    if (outcome !== 'not_paid') return outcome;
  }
  if (session.attributes.status !== 'expired') return 'pending';
  return markIfStillOpen(paymentRef, closedStatus);
}

// "Doesn't exist" and "not yours" give the same error so ids can't be probed.
async function loadOwnedPayment(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const {paymentId} = request.data || {};
  if (typeof paymentId !== 'string' || !PAYMENT_ID_PATTERN.test(paymentId)) {
    throw new HttpsError('invalid-argument', 'A valid paymentId is required.');
  }
  const ref = paymentsCol().doc(paymentId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().donorId !== request.auth.uid) {
    throw new HttpsError('not-found', 'Payment not found.');
  }
  return {ref, snap};
}

function resumeExisting(snap, uid) {
  const p = snap.data();
  if (p.donorId !== uid) throw new HttpsError('not-found', 'Payment not found.');
  if (p.status === 'creating') {
    throw new HttpsError('aborted', 'Your checkout is still being prepared. Please try again in a moment.');
  }
  return {paymentId: snap.id, status: p.status, checkoutUrl: p.status === 'pending' ? p.checkoutUrl : null};
}

// ── Callables ───────────────────────────────────────────────────────────────

// Idempotent by paymentId (double tap / retry after timeout → same checkout).
exports.createDonationCheckout = onCall({secrets: [paymongoSecretKey]}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {paymentId, campaignId, amount, paymentMethod, isAnonymous} = request.data || {};

  if (typeof paymentId !== 'string' || !PAYMENT_ID_PATTERN.test(paymentId)) {
    throw new HttpsError('invalid-argument', 'A valid paymentId is required.');
  }
  if (typeof campaignId !== 'string' || !CAMPAIGN_ID_PATTERN.test(campaignId)) {
    throw new HttpsError('invalid-argument', 'A valid campaign is required.');
  }
  if (!Object.prototype.hasOwnProperty.call(PAYMENT_METHOD_LABELS, paymentMethod)) {
    throw new HttpsError('invalid-argument', 'Choose a supported payment method.');
  }
  // Pesos with at most 2 decimals; centavos are computed here, not trusted.
  const amountCentavos = typeof amount === 'number' && Number.isFinite(amount) ? Math.round(amount * 100) : NaN;
  if (!Number.isInteger(amountCentavos) || amountCentavos <= 0 || Math.abs(amountCentavos - amount * 100) > 1e-6) {
    throw new HttpsError('invalid-argument', 'Enter a valid amount.');
  }

  const paymentRef = paymentsCol().doc(paymentId);
  const existing = await paymentRef.get();
  if (existing.exists) return resumeExisting(existing, uid);

  // Trusted campaign data comes from Firestore, never from the client.
  const campaignSnap = await db.collection('campaigns').doc(campaignId).get();
  if (!campaignSnap.exists) throw new HttpsError('not-found', 'This campaign does not exist.');
  const c = campaignSnap.data();
  const campaignType = c.type || 'donation';
  if (campaignType !== 'donation' && campaignType !== 'sponsorship') {
    throw new HttpsError('failed-precondition', 'This campaign does not accept monetary donations.');
  }
  if (c.isActive === false || (c.date instanceof Timestamp && c.date.toMillis() < Date.now())) {
    throw new HttpsError('failed-precondition', 'This campaign has ended.');
  }
  const min = typeof c.minAmount === 'number' ? c.minAmount : DEFAULT_MIN_AMOUNT;
  const max = typeof c.maxAmount === 'number' ? c.maxAmount : DEFAULT_MAX_AMOUNT;
  const pesos = amountCentavos / 100;
  if (pesos < min || pesos > max) {
    throw new HttpsError('invalid-argument', `Amounts must be between ₱${min} and ₱${max}.`);
  }

  const baseUrl = paymentReturnBaseUrl.value().replace(/\/+$/, '');
  if (!baseUrl.startsWith('https://')) {
    logger.error('PAYMENT_RETURN_BASE_URL must be an https URL');
    throw new HttpsError('failed-precondition', 'Online payments are not available right now.');
  }

  const title = (typeof c.title === 'string' && c.title.trim()) ? c.title.trim().slice(0, 200) : 'Donation';
  const itemDescription = campaignType === 'sponsorship' ?
    `Monthly Sponsorship: ${c.animalName || 'Pet'}` : title;
  const organizer = c.organizer || 'Rescue Shelter';

  try {
    // create() fails if the doc exists → concurrent calls can't both reach PayMongo.
    await paymentRef.create({
      donorId: uid,
      campaignId,
      campaignName: title,
      campaignType,
      itemDescription,
      organizer,
      amount: pesos,
      amountCentavos,
      currency: CURRENCY,
      paymentMethod,
      paymentMethodLabel: PAYMENT_METHOD_LABELS[paymentMethod],
      isAnonymous: isAnonymous === true,
      provider: 'paymongo',
      livemode: isLiveMode(),
      status: 'creating',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e && e.code === 6) return resumeExisting(await paymentRef.get(), uid); // ALREADY_EXISTS
    throw e;
  }

  let session;
  try {
    session = await paymongoRequest('POST', '/checkout_sessions', {
      data: {
        attributes: {
          line_items: [{
            name: itemDescription.slice(0, 200),
            amount: amountCentavos,
            currency: CURRENCY,
            quantity: 1,
            description: `${organizer} — ${title}`.slice(0, 250),
          }],
          payment_method_types: [paymentMethod],
          description: `ResPAWnd ${campaignType} — ${title}`.slice(0, 250),
          reference_number: paymentId,
          success_url: `${baseUrl}/payment/success/?pid=${paymentId}`,
          cancel_url: `${baseUrl}/payment/cancel/?pid=${paymentId}`,
          send_email_receipt: false,
          show_description: true,
          show_line_items: true,
          metadata: {paymentId, campaignId},
        },
      },
    });
  } catch (e) {
    logPaymongoError('createCheckoutSession', paymentId, e);
    await paymentRef.update({status: 'error', errorReason: 'create_failed', updatedAt: FieldValue.serverTimestamp()});
    if (e instanceof PaymongoApiError && e.httpStatus >= 400 && e.httpStatus < 500 && e.httpStatus !== 401) {
      throw new HttpsError('failed-precondition', 'PayMongo could not start this payment. Try a different payment method.');
    }
    throw new HttpsError('unavailable', 'The payment service is unavailable right now. Please try again.');
  }

  const checkoutUrl = session && session.attributes && session.attributes.checkout_url;
  if (!session || !session.id || typeof checkoutUrl !== 'string') {
    logger.error('createCheckoutSession returned no checkout_url', {paymentId});
    await paymentRef.update({status: 'error', errorReason: 'no_checkout_url', updatedAt: FieldValue.serverTimestamp()});
    throw new HttpsError('internal', 'Could not start the payment. Please try again.');
  }

  await paymentRef.update({
    status: 'pending',
    checkoutSessionId: session.id,
    paymentIntentId: (session.attributes.payment_intent && session.attributes.payment_intent.id) || null,
    checkoutUrl,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {paymentId, status: 'pending', checkoutUrl};
});

// Fallback for late/missed webhooks (PayMongo doesn't resend missed events).
exports.syncDonationPayment = onCall({secrets: [paymongoSecretKey]}, async (request) => {
  const {ref, snap} = await loadOwnedPayment(request);
  const p = snap.data();
  if (p.status !== 'pending' || !p.checkoutSessionId) return {status: p.status};
  try {
    const session = await retrieveCheckoutSession(p.checkoutSessionId);
    const {outcome} = await finalizePaidDonation(ref, session);
    if (outcome === 'not_paid' && session.attributes.status === 'expired') {
      return {status: await markIfStillOpen(ref, 'expired')};
    }
    return {status: (await ref.get()).data().status};
  } catch (e) {
    logPaymongoError('syncDonationPayment', snap.id, e);
    throw new HttpsError('unavailable', 'Could not reach the payment service. Please try again.');
  }
});

exports.cancelDonationCheckout = onCall({secrets: [paymongoSecretKey]}, async (request) => {
  const {ref, snap} = await loadOwnedPayment(request);
  const p = snap.data();
  if (p.status !== 'pending' || !p.checkoutSessionId) return {status: p.status};
  try {
    await expireAndSettle(ref, p.checkoutSessionId, 'cancelled');
    return {status: (await ref.get()).data().status};
  } catch (e) {
    logPaymongoError('cancelDonationCheckout', snap.id, e);
    throw new HttpsError('unavailable', 'Could not cancel right now. Please try again.');
  }
});

// ── Webhook ─────────────────────────────────────────────────────────────────

// Paymongo-Signature: t=<timestamp>,te=<test sig>,li=<live sig>
// sig = hex HMAC-SHA256(webhook secret, `${t}.${rawBody}`)
function verifyPaymongoSignature(header, rawBody) {
  if (typeof header !== 'string' || !rawBody) return false;
  const parts = {};
  for (const piece of header.split(',')) {
    const i = piece.indexOf('=');
    if (i > 0) parts[piece.slice(0, i).trim()] = piece.slice(i + 1).trim();
  }
  const provided = isLiveMode() ? parts.li : parts.te;
  if (!parts.t || !provided) return false;
  const expected = crypto.createHmac('sha256', paymongoWebhookSecret.value())
      .update(`${parts.t}.`).update(rawBody).digest();
  const given = Buffer.from(provided, 'hex');
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

async function recordFailedAttempt(paymentResource) {
  // VERIFY: field name on the payment resource in payment.failed events.
  const intentId = paymentResource && paymentResource.attributes &&
    paymentResource.attributes.payment_intent_id;
  if (typeof intentId !== 'string' || !intentId) return 'ignored_no_intent';
  const match = await paymentsCol().where('paymentIntentId', '==', intentId).limit(1).get();
  if (match.empty) return 'ignored_unknown_intent';
  const ref = match.docs[0].ref;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || !OPEN_STATUSES.includes(snap.data().status)) return;
    // Not final: the donor can retry on the same hosted page.
    tx.update(ref, {
      lastPaymentError: {
        code: String(paymentResource.attributes.failed_code || 'unknown').slice(0, 100),
        at: Timestamp.now(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return 'recorded_failure';
}

async function handlePaymongoEvent(type, resource) {
  if (type === 'checkout_session.payment.paid') {
    const sessionId = resource && resource.id;
    const paymentId = resource && resource.attributes && resource.attributes.reference_number;
    if (typeof sessionId !== 'string' || typeof paymentId !== 'string' || !PAYMENT_ID_PATTERN.test(paymentId)) {
      return 'ignored_unknown_reference';
    }
    const ref = paymentsCol().doc(paymentId);
    const snap = await ref.get();
    if (!snap.exists) return 'ignored_unknown_payment';
    if (snap.data().checkoutSessionId !== sessionId) return 'ignored_session_mismatch';
    const session = await retrieveCheckoutSession(sessionId); // don't trust the body
    return (await finalizePaidDonation(ref, session)).outcome;
  }
  if (type === 'payment.failed') return recordFailedAttempt(resource);
  return 'ignored_type';
}

exports.paymongoWebhook = onRequest(
    {secrets: [paymongoSecretKey, paymongoWebhookSecret]},
    async (req, res) => {
      if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
      }
      const rawBody = req.rawBody; // exact bytes PayMongo signed
      if (!verifyPaymongoSignature(req.get('Paymongo-Signature'), rawBody)) {
        logger.warn('paymongoWebhook: rejected (invalid signature)');
        res.status(401).send('Invalid signature');
        return;
      }
      let event;
      try {
        event = JSON.parse(rawBody.toString('utf8')).data;
      } catch (_) {
        res.status(400).send('Bad payload');
        return;
      }
      const eventId = event && event.id;
      const type = event && event.attributes && event.attributes.type;
      if (typeof eventId !== 'string' || !EVENT_ID_PATTERN.test(eventId) || typeof type !== 'string') {
        res.status(400).send('Bad payload');
        return;
      }
      const livemode = event.attributes.livemode === true;
      if (livemode !== isLiveMode()) {
        logger.warn('paymongoWebhook: mode mismatch, ignored', {eventId, type});
        res.status(200).send('ignored');
        return;
      }
      const eventRef = db.collection('paymongoWebhookEvents').doc(eventId);
      if ((await eventRef.get()).exists) {
        res.status(200).send('duplicate');
        return;
      }
      try {
        const outcome = await handlePaymongoEvent(type, event.attributes.data);
        // Recorded only after success, so failures stay retryable.
        await eventRef.set({type, outcome, livemode, processedAt: FieldValue.serverTimestamp()});
        logger.info('paymongoWebhook processed', {eventId, type, outcome});
        res.status(200).send('ok');
      } catch (e) {
        logPaymongoError(`paymongoWebhook(${type})`, eventId, e);
        res.status(500).send('error'); // PayMongo retries non-2xx
      }
    },
);

// ── Scheduled jobs ──────────────────────────────────────────────────────────

// Checkout sessions never expire on their own. Index: donationPayments
// (status ASC, createdAt ASC).
exports.expireStaleDonationCheckouts = onSchedule(
    {schedule: 'every 60 minutes', secrets: [paymongoSecretKey]},
    async () => {
      const cutoff = Timestamp.fromMillis(Date.now() - STALE_CHECKOUT_HOURS * 3600000);
      const stale = await paymentsCol()
          .where('status', 'in', OPEN_STATUSES)
          .where('createdAt', '<', cutoff)
          .limit(50)
          .get();
      for (const doc of stale.docs) {
        const p = doc.data();
        try {
          if (!p.checkoutSessionId) {
            await markIfStillOpen(doc.ref, 'error', {errorReason: 'stuck_creating'});
            continue;
          }
          await expireAndSettle(doc.ref, p.checkoutSessionId, 'expired');
        } catch (e) {
          logPaymongoError('expireStaleDonationCheckouts', doc.id, e);
        }
      }
    },
);

// OPTIONAL. Sponsorships are one-time 30-day payments (no automatic renewal):
// once nextChargeDate passes, mark them inactive so donation_page.dart stops
// showing them as active. Index: donations (type, sponsorshipStatus, nextChargeDate).
exports.lapseExpiredSponsorships = onSchedule('every 24 hours', async () => {
  const lapsed = await db.collection('donations')
      .where('type', '==', 'sponsorship')
      .where('sponsorshipStatus', '==', 'active')
      .where('nextChargeDate', '<', Timestamp.now())
      .limit(200)
      .get();
  for (const doc of lapsed.docs) {
    const update = {sponsorshipStatus: 'inactive', status: 'inactive'};
    const batch = db.batch();
    batch.update(doc.ref, update);
    const uid = doc.data().userId;
    if (typeof uid === 'string') {
      batch.set(db.collection('users').doc(uid).collection('history').doc(doc.id), update, {merge: true});
    }
    await batch.commit();
  }
});