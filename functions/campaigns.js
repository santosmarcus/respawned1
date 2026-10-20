// Admin management of donation campaigns & sponsorship listings.
//
// Every admin write to campaigns/{id} (and its allocations / updates /
// history subcollections), every manual (offline) donation, every in-kind
// confirmation and every fund reallocation goes through a callable here, so
// the rules can keep those paths closed to clients. Verified money only
// enters collectedAmount in two places: paymongo.js finalizePaidDonation()
// (gateway-verified) and recordOfflineDonation() below (admin-verified,
// marked source: 'manual'). Allocations and transfers never touch
// collectedAmount — they only move what is already there.
//
// Campaign money fields (pesos, same unit paymongo.js already uses):
//   collectedAmount       verified donations (gateway + manual)
//   allocatedAmount       recorded spending (campaigns/{id}/allocations kind 'expense')
//   transferredOutAmount  excess moved to other campaigns
//   transferredInAmount   excess received from other campaigns (NOT a donation)
//   available = collected + transferredIn - transferredOut - allocated
//
// Lifecycle: draft → active → goal_met (target reached, set by the payment
// that completes it) / goal_not_met (deadline) → closed → archived. A
// finished campaign stays visible (admin + general "Past Campaigns") until
// it is archived, and it can only be archived once every peso is allocated
// or transferred (available == 0).

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const {completedCampaignFields, certificateBenefit, issueCertificate} = require('./donation_common');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const CAMPAIGN_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9]{20}$/; // Firestore auto-id format

// users/{uid}.role values main.dart routes into the admin shell.
const LISTING_ROLES = ['admin', 'ngo_staff', 'organization'];

const TYPES = ['donation', 'sponsorship'];
const FUND_KINDS = ['campaign', 'animal', 'medical', 'shelter_resource', 'general'];
// Figma "Tags (Select at least 1)". Reallocation requires a shared tag.
const PURPOSE_TAGS = ['Rescue', 'Medicine & Treatment', 'Food and Supplies', 'Shelter', 'General Operations'];
// Same categories as the Figma "Allocate Funds" sheet.
const ALLOCATION_CATEGORIES = ['Food', 'Medicine and Treatment', 'Administrative', 'Bills and Utilities', 'Shelter', 'Transport', 'Other'];
const IN_KIND_CATEGORIES = ['Food & Water', 'Medicine & Treatment', 'Supplies & Equipment', 'Hygiene & Cleaning', 'Transport Crates', 'Others'];
const OFFLINE_METHODS = {bank_transfer: 'Bank Transfer', cash: 'Cash', check: 'Check', other: 'Other'};

const MAX_AMOUNT = 10000000; // pesos, sanity cap
const MAX_DEADLINE_DAYS = 730;
const EXPIRY_BATCH = 100;

const campaignsCol = () => db.collection('campaigns');

// ── Small helpers ───────────────────────────────────────────────────────────

const centavos = (pesos) => Math.round(Number(pesos) * 100);
const pesos = (c) => c / 100;
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

function requireString(v, field, {max = 200, optional = false} = {}) {
  if (v === undefined || v === null || v === '') {
    if (optional) return null;
    throw new HttpsError('invalid-argument', `${field} is required.`);
  }
  if (typeof v !== 'string') throw new HttpsError('invalid-argument', `${field} must be text.`);
  const s = v.trim();
  if (!s && !optional) throw new HttpsError('invalid-argument', `${field} is required.`);
  if (s.length > max) throw new HttpsError('invalid-argument', `${field} is too long (max ${max}).`);
  return s || null;
}

// Positive peso amount with at most 2 decimals.
function requireAmount(v, field, {allowZero = false} = {}) {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new HttpsError('invalid-argument', `${field} must be a number.`);
  const c = centavos(v);
  if (Math.abs(c - v * 100) > 1e-6) throw new HttpsError('invalid-argument', `${field} can have at most 2 decimals.`);
  if (c < 0 || (!allowZero && c === 0)) throw new HttpsError('invalid-argument', `${field} must be greater than zero.`);
  if (v > MAX_AMOUNT) throw new HttpsError('invalid-argument', `${field} is too large.`);
  return v;
}

function requireCampaignId(v, field = 'campaignId') {
  if (typeof v !== 'string' || !CAMPAIGN_ID_PATTERN.test(v)) throw new HttpsError('invalid-argument', `A valid ${field} is required.`);
  return v;
}

function requireRequestId(v) {
  if (typeof v !== 'string' || !REQUEST_ID_PATTERN.test(v)) throw new HttpsError('invalid-argument', 'A valid requestId is required.');
  return v;
}

function requireFutureDeadline(ms, field = 'Deadline') {
  if (typeof ms !== 'number' || !Number.isFinite(ms)) throw new HttpsError('invalid-argument', `${field} is required.`);
  const now = Date.now();
  if (ms <= now) throw new HttpsError('invalid-argument', `${field} must be in the future.`);
  if (ms > now + MAX_DEADLINE_DAYS * 86400000) throw new HttpsError('invalid-argument', `${field} is too far in the future.`);
  return Timestamp.fromMillis(ms);
}

// Only images uploaded to this project's Storage bucket.
function optionalStorageUrl(v, field) {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || !v.startsWith('https://firebasestorage.googleapis.com/') || v.length > 2048) {
    throw new HttpsError('invalid-argument', `${field} must be an uploaded image.`);
  }
  return v;
}

// Same format paymongo.js uses: "October 15, 2026" (Philippine time).
function formatManilaDate(date) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'long', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila',
  }).format(date);
}

function displayName(userData) {
  if (!userData) return 'Admin';
  const full = `${userData.firstName || ''} ${userData.lastName || ''}`.trim();
  return full || userData.name || 'Admin';
}

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

function historyEntry(tx, campaignRef, actor, type, details) {
  tx.set(campaignRef.collection('history').doc(), {
    type,
    ...details,
    byUid: actor.uid,
    byName: actor.name,
    at: FieldValue.serverTimestamp(),
  });
}

// ── Authorization ───────────────────────────────────────────────────────────
// Listing managers: users/{uid}.role in LISTING_ROLES (the existing admin
// shell roles). Financial administrators: users/{uid}.role == 'admin', or an
// Admin member of their organization (organizations/{orgId}/members/{uid},
// see lib/core/repos/org_membership_service.dart). ngo_staff can manage
// listings but not money.
async function loadActor(request, {finance = false} = {}) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const userSnap = await db.collection('users').doc(uid).get();
  const u = userSnap.exists ? userSnap.data() : {};
  const role = typeof u.role === 'string' ? u.role : '';
  if (!LISTING_ROLES.includes(role)) throw new HttpsError('permission-denied', 'Only organization staff can do this.');

  const organizationId = typeof u.organizationId === 'string' && u.organizationId ? u.organizationId : null;
  let memberRole = null;
  if (organizationId) {
    const m = await db.collection('organizations').doc(organizationId).collection('members').doc(uid).get();
    memberRole = m.exists ? m.data().role : null;
  }
  const canManageFinances = role === 'admin' || memberRole === 'admin';
  if (finance && !canManageFinances) {
    throw new HttpsError('permission-denied', 'Only financial administrators can do this.');
  }
  return {uid, name: displayName(u), role, organizationId, canManageFinances};
}

// A campaign tied to an organization can only be managed by that
// organization's staff. Legacy campaigns / accounts without an organization
// stay manageable, matching the fail-open testing phase documented in
// org_membership_service.dart.
function assertSameOrg(actor, c) {
  if (c.organizationId && actor.organizationId && c.organizationId !== actor.organizationId) {
    throw new HttpsError('permission-denied', 'This listing belongs to another organization.');
  }
}

async function organizerNameFor(actor) {
  if (!actor.organizationId) return null;
  const org = await db.collection('organizations').doc(actor.organizationId).get();
  const name = org.exists ? org.data().name : null;
  return typeof name === 'string' && name.trim() ? name.trim() : null;
}

// ── Listing payload validation ──────────────────────────────────────────────

function parseInKindItems(raw) {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > 30) throw new HttpsError('invalid-argument', 'Invalid in-kind items.');
  return raw.map((it, i) => {
    if (!it || typeof it !== 'object') throw new HttpsError('invalid-argument', `In-kind item ${i + 1} is invalid.`);
    const category = requireString(it.category, `In-kind item ${i + 1} category`, {max: 60});
    if (!IN_KIND_CATEGORIES.includes(category)) throw new HttpsError('invalid-argument', `In-kind item ${i + 1} has an unknown category.`);
    const quantityNeeded = it.quantityNeeded === undefined || it.quantityNeeded === null ? null : Number(it.quantityNeeded);
    if (quantityNeeded !== null && (!Number.isInteger(quantityNeeded) || quantityNeeded <= 0 || quantityNeeded > 100000)) {
      throw new HttpsError('invalid-argument', `In-kind item ${i + 1} quantity must be a whole number.`);
    }
    return {
      // category + description are what donation_detail.dart already shows.
      category,
      description: requireString(it.description, `In-kind item ${i + 1} description`, {max: 300}),
      quantityNeeded,
      unit: requireString(it.unit, `In-kind item ${i + 1} unit`, {max: 30, optional: true}),
      instructions: requireString(it.instructions, `In-kind item ${i + 1} delivery instructions`, {max: 500, optional: true}),
      // Owned by manageInKindDonation(); saveCampaign restores it on edit.
      quantityReceived: 0,
    };
  });
}

// Validates the editable listing fields. `existing` is the stored doc on edit.
async function buildListingFields(data, existing) {
  const type = existing ? (existing.type || 'donation') : data.type;
  if (!TYPES.includes(type)) throw new HttpsError('invalid-argument', 'Choose Donation or Sponsorship.');

  const fundKind = data.fundKind === undefined ? (existing && existing.fundKind) || (type === 'sponsorship' ? 'animal' : 'campaign') : data.fundKind;
  if (!FUND_KINDS.includes(fundKind)) throw new HttpsError('invalid-argument', 'Choose what this listing funds.');

  const tags = Array.isArray(data.purposeTags) ? [...new Set(data.purposeTags)] : [];
  if (!tags.length || tags.some((t) => !PURPOSE_TAGS.includes(t))) {
    throw new HttpsError('invalid-argument', 'Select at least one tag.');
  }

  const fields = {
    description: requireString(data.description, 'Description', {max: 5000, optional: true}) || '',
    imageUrl: optionalStorageUrl(data.imageUrl, 'Cover image'),
    fundKind,
    purposeTags: tags,
    restricted: data.restricted === true,
    linkedCaseId: requireString(data.linkedCaseId, 'Rescue case', {max: 128, optional: true}),
  };

  // Animal link (required for sponsorships; optional for donations).
  const animalId = requireString(data.animalId, 'Animal', {max: 128, optional: true});
  if (animalId) {
    const animal = await db.collection('animals').doc(animalId).get();
    if (!animal.exists) throw new HttpsError('not-found', 'That animal record does not exist.');
    const a = animal.data();
    fields.animalId = animalId;
    fields.animalName = typeof a.name === 'string' ? a.name : '';
    fields.isDog = String(a.species || '').toLowerCase() === 'dog';
  } else if (type === 'sponsorship') {
    throw new HttpsError('invalid-argument', 'Select the animal to sponsor.');
  } else {
    fields.animalId = null;
    fields.animalName = null;
  }

  if (type === 'donation') {
    fields.title = requireString(data.title, 'Title', {max: 200});
    fields.targetAmount = requireAmount(data.targetAmount, 'Target amount');
    fields.acceptInKind = data.acceptInKind === true;
    fields.inKindItems = fields.acceptInKind ? parseInKindItems(data.inKindItems) : [];
    if (fields.acceptInKind && !fields.inKindItems.length) {
      throw new HttpsError('invalid-argument', 'Add at least one in-kind item or turn off in-kind donations.');
    }
    fields.monthlyAmount = null;
    fields.intendedUse = null;
  } else {
    // Sponsorships: title defaults to the animal's name (Austin's behaviour).
    fields.title = requireString(data.title, 'Title', {max: 200, optional: true}) || fields.animalName || 'Sponsorship';
    fields.monthlyAmount = requireAmount(data.monthlyAmount, 'Monthly amount');
    fields.intendedUse = requireString(data.intendedUse, 'Intended use of funds', {max: 1000});
    fields.targetAmount = 0; // sponsorships have no funding goal
    fields.acceptInKind = false;
    fields.inKindItems = [];
  }
  return {type, fields};
}

// ── Callables ───────────────────────────────────────────────────────────────

// Create (no campaignId) or edit (campaignId) a listing.
// data: {type, title, description, imageUrl, animalId, fundKind, purposeTags,
//        restricted, linkedCaseId, targetAmount, deadlineMs, acceptInKind,
//        inKindItems, monthlyAmount, intendedUse}
// publish: true publishes immediately on create.
exports.saveCampaign = onCall(async (request) => {
  const actor = await loadActor(request);
  const {campaignId, data, publish} = request.data || {};
  if (!data || typeof data !== 'object') throw new HttpsError('invalid-argument', 'Listing details are required.');

  if (!campaignId) {
    const {type, fields} = await buildListingFields(data, null);
    let deadline = null;
    if (type === 'donation') deadline = requireFutureDeadline(data.deadlineMs, 'Expected end date');
    else if (data.deadlineMs !== undefined && data.deadlineMs !== null) deadline = requireFutureDeadline(data.deadlineMs, 'End date');

    const organizer = (await organizerNameFor(actor)) || 'Rescue Shelter';
    const ref = campaignsCol().doc();
    const status = publish === true ? 'active' : 'draft';
    await db.runTransaction(async (tx) => {
      tx.create(ref, {
        ...fields,
        type,
        date: deadline,
        startDate: status === 'active' ? FieldValue.serverTimestamp() : null,
        status,
        isActive: status === 'active',
        organizer,
        organizationId: actor.organizationId,
        collectedAmount: 0,
        allocatedAmount: 0,
        transferredOutAmount: 0,
        transferredInAmount: 0,
        numdonors: 0,
        needsExtensionDecision: false,
        extensionCount: 0,
        backgroundColor: 0xFFE3E0B9, // AppColors.tearspwn, as Austin's form saved
        createdBy: actor.uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: actor.uid,
      });
      historyEntry(tx, ref, actor, 'created', {status});
    });
    return {campaignId: ref.id, status};
  }

  requireCampaignId(campaignId);
  const ref = campaignsCol().doc(campaignId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Listing not found.');
  const existing = snap.data();
  assertSameOrg(actor, existing);
  const status = statusOf(existing);
  if (status === 'closed') throw new HttpsError('failed-precondition', 'Closed listings cannot be edited. Relaunch it first.');
  if (status === 'archived') throw new HttpsError('failed-precondition', 'Archived listings cannot be edited.');

  const {type, fields} = await buildListingFields(data, existing);
  if (existing.restricted === true && fields.restricted === false && num(existing.collectedAmount) > 0) {
    throw new HttpsError('failed-precondition', 'Funds were raised as restricted; the restriction cannot be lifted.');
  }
  // Received in-kind counts come from confirmations, never from the form.
  const oldItems = Array.isArray(existing.inKindItems) ? existing.inKindItems : [];
  fields.inKindItems = fields.inKindItems.map((it, i) => ({
    ...it,
    quantityReceived: oldItems[i] && Number.isInteger(oldItems[i].quantityReceived) ? oldItems[i].quantityReceived : 0,
  }));
  const update = {...fields, updatedAt: FieldValue.serverTimestamp(), updatedBy: actor.uid};
  if (type === 'donation') {
    // An expired campaign's deadline only moves through resolveExpiredCampaign
    // (so the extension is audited). Drafts and running campaigns can edit it.
    if (status === 'draft' || status === 'active' || status === 'paused') {
      update.date = requireFutureDeadline(data.deadlineMs, 'Expected end date');
    }
  }
  const changed = Object.keys(fields).filter((k) => JSON.stringify(fields[k]) !== JSON.stringify(existing[k]));
  await db.runTransaction(async (tx) => {
    tx.update(ref, update);
    historyEntry(tx, ref, actor, 'edited', {changedFields: changed});
  });
  return {campaignId, status};
});

// action: 'publish' | 'deactivate' | 'reactivate' | 'close'
exports.setCampaignStatus = onCall(async (request) => {
  const actor = await loadActor(request);
  const {campaignId, action, reason} = request.data || {};
  requireCampaignId(campaignId);
  const why = requireString(reason, 'Reason', {max: 500, optional: true});
  const ref = campaignsCol().doc(campaignId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const c = snap.data();
    assertSameOrg(actor, c);
    const status = statusOf(c);
    const deadlinePassed = c.date instanceof Timestamp && c.date.toMillis() <= Date.now();
    const now = FieldValue.serverTimestamp();
    let next;

    if (action === 'publish') {
      if (status !== 'draft') throw new HttpsError('failed-precondition', 'Only drafts can be published.');
      if (c.type !== 'sponsorship' && (!(c.date instanceof Timestamp) || deadlinePassed)) {
        throw new HttpsError('failed-precondition', 'Set a future end date before publishing.');
      }
      next = {status: 'active', isActive: true, startDate: now};
    } else if (action === 'deactivate') {
      if (status !== 'active') throw new HttpsError('failed-precondition', 'Only active listings can be deactivated.');
      next = {status: 'paused', isActive: false};
    } else if (action === 'reactivate') {
      if (status !== 'paused') throw new HttpsError('failed-precondition', 'Only deactivated listings can be reactivated.');
      if (deadlinePassed) throw new HttpsError('failed-precondition', 'The end date has passed. Extend the campaign instead.');
      next = {status: 'active', isActive: true};
    } else if (action === 'close') {
      if (status === 'closed') return {status};
      if (status === 'draft') throw new HttpsError('failed-precondition', 'Drafts are not published; edit or leave them.');
      if (status === 'archived') throw new HttpsError('failed-precondition', 'This listing is archived.');
      next = {status: 'closed', isActive: false, needsExtensionDecision: false, closedAt: now};
    } else if (action === 'archive') {
      // Removes it from both views — only once every peso is accounted for.
      if (!['goal_met', 'closed'].includes(status)) {
        throw new HttpsError('failed-precondition', 'Only completed or closed listings can be archived.');
      }
      const m = moneyOf(c);
      if (m.available > 0) {
        throw new HttpsError('failed-precondition',
            `Allocate the remaining ₱${pesos(m.available).toFixed(2)} before archiving this listing.`);
      }
      next = {status: 'archived', isActive: false, needsExtensionDecision: false, archivedAt: now};
    } else {
      throw new HttpsError('invalid-argument', 'Unknown action.');
    }
    tx.update(ref, {...next, updatedAt: now, updatedBy: actor.uid});
    historyEntry(tx, ref, actor, action, {from: status, to: next.status, reason: why});
    return {status: next.status, type: c.type || 'donation'};
  });

  // Closing a sponsorship ends its sponsors' active periods (what Austin's
  // endCampaign did from the client). Donation records are kept, only marked.
  if (action === 'close' && result.type === 'sponsorship') {
    const active = await db.collection('donations')
        .where('campaignId', '==', campaignId)
        .where('sponsorshipStatus', '==', 'active')
        .get();
    for (let i = 0; i < active.docs.length; i += 200) {
      const batch = db.batch();
      for (const doc of active.docs.slice(i, i + 200)) {
        const update = {sponsorshipStatus: 'inactive', status: 'inactive'};
        batch.update(doc.ref, update);
        const uid = doc.data().userId;
        if (typeof uid === 'string') {
          batch.set(db.collection('users').doc(uid).collection('history').doc(doc.id), update, {merge: true});
        }
      }
      await batch.commit();
    }
  }
  return {status: result.status};
});

// After the deadline: decision 'extend' | 'close' | 'convert_to_general'.
// 'relaunch' reopens a closed or goal-not-met campaign with a new deadline.
// Never touches collectedAmount or donation records.
exports.resolveExpiredCampaign = onCall(async (request) => {
  const actor = await loadActor(request);
  const {campaignId, decision, newDeadlineMs, reason} = request.data || {};
  requireCampaignId(campaignId);
  const why = requireString(reason, 'Reason', {max: 500, optional: decision === 'close'});
  const ref = campaignsCol().doc(campaignId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const c = snap.data();
    assertSameOrg(actor, c);
    if ((c.type || 'donation') !== 'donation') throw new HttpsError('failed-precondition', 'Only donation campaigns have deadlines to resolve.');
    const status = statusOf(c);
    const now = FieldValue.serverTimestamp();
    const previousDeadline = c.date instanceof Timestamp ? c.date : null;

    if (decision === 'extend' || decision === 'relaunch') {
      const allowed = decision === 'extend' ? ['goal_not_met'] : ['goal_not_met', 'closed'];
      if (!allowed.includes(status)) {
        throw new HttpsError('failed-precondition', decision === 'extend' ?
          'Only campaigns that ended below their goal can be extended.' :
          'Only closed or goal-not-met campaigns can be relaunched.');
      }
      const newDeadline = requireFutureDeadline(newDeadlineMs, 'New deadline');
      tx.update(ref, {
        date: newDeadline,
        status: 'active',
        isActive: true,
        needsExtensionDecision: false,
        extensionCount: FieldValue.increment(1),
        updatedAt: now,
        updatedBy: actor.uid,
      });
      historyEntry(tx, ref, actor, decision === 'extend' ? 'extended' : 'relaunched', {
        previousDeadline, newDeadline, previousStatus: status, reason: why,
        collectedAtDecision: num(c.collectedAmount),
      });
      tx.set(ref.collection('updates').doc(), {
        type: 'extended',
        title: `Campaign extended to ${formatManilaDate(newDeadline.toDate())}`,
        date: formatManilaDate(new Date()),
        createdAt: now,
      });
      return {status: 'active'};
    }

    if (decision === 'close') {
      if (!['goal_not_met', 'goal_met'].includes(status)) throw new HttpsError('failed-precondition', 'This campaign has no pending deadline decision.');
      tx.update(ref, {status: 'closed', isActive: false, needsExtensionDecision: false, closedAt: now, updatedAt: now, updatedBy: actor.uid});
      historyEntry(tx, ref, actor, 'extension_declined', {previousStatus: status, reason: why});
      return {status: 'closed'};
    }

    if (decision === 'convert_to_general') {
      if (!['goal_not_met', 'closed'].includes(status)) throw new HttpsError('failed-precondition', 'Only ended campaigns can be converted to a general fund.');
      tx.update(ref, {
        fundKind: 'general',
        date: null,
        status: 'active',
        isActive: true,
        needsExtensionDecision: false,
        convertedToGeneralAt: now,
        updatedAt: now,
        updatedBy: actor.uid,
      });
      historyEntry(tx, ref, actor, 'converted_to_general', {previousDeadline, previousStatus: status, reason: why});
      tx.set(ref.collection('updates').doc(), {
        type: 'converted',
        title: 'Now accepting donations as a general fund',
        date: formatManilaDate(new Date()),
        createdAt: now,
      });
      return {status: 'active'};
    }
    throw new HttpsError('invalid-argument', 'Unknown decision.');
  });
});

// Progress update shown on the public detail pages (campaigns/{id}/updates,
// read by sponsorship_detail.dart's _UpdateTile: title, date, type).
exports.postCampaignUpdate = onCall(async (request) => {
  const actor = await loadActor(request);
  const {campaignId, title, body, type} = request.data || {};
  requireCampaignId(campaignId);
  const t = requireString(title, 'Title', {max: 200});
  const b = requireString(body, 'Details', {max: 2000, optional: true});
  const kind = ['general', 'medical', 'milestone', 'photo'].includes(type) ? type : 'general';
  const ref = campaignsCol().doc(campaignId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Listing not found.');
  assertSameOrg(actor, snap.data());
  await ref.collection('updates').add({
    type: kind,
    title: t,
    body: b,
    date: formatManilaDate(new Date()),
    createdAt: FieldValue.serverTimestamp(),
    byUid: actor.uid,
  });
  return {ok: true};
});

// Payment received outside PayMongo (bank transfer, cash, ...). Credited to
// collectedAmount like a verified donation, but marked source 'manual' with
// who recorded it. Duplicate guard: one record per campaign + method + reference.
exports.recordOfflineDonation = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  requireCampaignId(d.campaignId);
  const amount = requireAmount(d.amount, 'Amount');
  if (!Object.prototype.hasOwnProperty.call(OFFLINE_METHODS, d.method)) throw new HttpsError('invalid-argument', 'Choose how the payment was received.');
  const reference = requireString(d.referenceNumber, 'Reference number', {max: 100});
  const donorName = requireString(d.donorName, 'Donor name', {max: 120, optional: true});
  const notes = requireString(d.notes, 'Notes', {max: 1000, optional: true});
  const receiptUrl = optionalStorageUrl(d.receiptUrl, 'Receipt');
  if (typeof d.receivedAtMs !== 'number' || d.receivedAtMs > Date.now() + 60000 || d.receivedAtMs < Date.now() - 365 * 86400000) {
    throw new HttpsError('invalid-argument', 'Enter when the payment was received (within the last year).');
  }
  const receivedAt = Timestamp.fromMillis(d.receivedAtMs);

  const key = crypto.createHash('sha256')
      .update(`${d.campaignId}|${d.method}|${reference.toUpperCase().replace(/\s+/g, '')}`)
      .digest('hex');
  const refDoc = db.collection('manualDonationRefs').doc(key);
  const campaignRef = campaignsCol().doc(d.campaignId);
  const donationRef = db.collection('donations').doc();

  await db.runTransaction(async (tx) => {
    const [dup, campaignSnap] = await Promise.all([tx.get(refDoc), tx.get(campaignRef)]);
    if (dup.exists) throw new HttpsError('already-exists', 'A payment with this reference number was already recorded for this campaign.');
    if (!campaignSnap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const c = campaignSnap.data();
    assertSameOrg(actor, c);
    if ((c.type || 'donation') !== 'donation') throw new HttpsError('failed-precondition', 'Offline payments can only be recorded for donation campaigns.');
    if (statusOf(c) === 'draft') throw new HttpsError('failed-precondition', 'Publish the campaign first.');

    const label = OFFLINE_METHODS[d.method];
    const now = FieldValue.serverTimestamp();
    // Same shape as paymongo.js records so existing admin/general lists read it.
    tx.set(donationRef, {
      userId: null,
      donorName: donorName || 'Anonymous',
      isAnonymous: !donorName,
      campaignId: d.campaignId,
      campaignName: c.title || '',
      amount,
      amountString: `₱${amount.toFixed(2)}`,
      method: label,
      donationMethod: label,
      timestamp: receivedAt,
      createdAt: now,
      date: formatManilaDate(receivedAt.toDate()),
      refNumber: reference,
      type: 'donation',
      organizer: c.organizer || 'Rescue Shelter',
      organizationId: c.organizationId || null, // organization_profile_page.dart queries by it
      itemDescription: c.title || 'Donation',
      status: 'received',
      source: 'manual',
      verification: 'admin_recorded',
      recordedBy: actor.uid,
      recordedByName: actor.name,
      notes,
      receiptUrl,
    });
    tx.set(refDoc, {campaignId: d.campaignId, donationId: donationRef.id, method: d.method, reference, createdAt: now});
    const campaignUpdate = {
      collectedAmount: FieldValue.increment(amount),
      numdonors: FieldValue.increment(1),
      updatedAt: now,
    };
    const m = moneyOf(c);
    const completes = statusOf(c) === 'active' && m.target > 0 && m.collected < m.target && m.collected + centavos(amount) >= m.target;
    if (completes) Object.assign(campaignUpdate, completedCampaignFields());
    tx.update(campaignRef, campaignUpdate);
    historyEntry(tx, campaignRef, actor, 'offline_donation_recorded', {donationId: donationRef.id, amount, method: d.method, reference});
    if (completes) historyEntry(tx, campaignRef, actor, 'goal_completed', {to: 'goal_met', donationId: donationRef.id});
  });
  return {donationId: donationRef.id};
});

// Spending from a campaign's available balance. Written to
// campaigns/{id}/allocations, which donation_detail.dart's Fund Tracking
// already reads (label, category, amount, date).
exports.recordAllocation = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  requireCampaignId(d.campaignId);
  const requestId = requireRequestId(d.requestId);
  const label = requireString(d.label, 'Title', {max: 120});
  const category = requireString(d.category, 'Category', {max: 60});
  if (!ALLOCATION_CATEGORIES.includes(category)) throw new HttpsError('invalid-argument', 'Choose a category.');
  const amount = requireAmount(d.amount, 'Amount');
  const notes = requireString(d.notes, 'Notes', {max: 1000, optional: true});
  const receiptUrl = optionalStorageUrl(d.receiptUrl, 'Receipt');
  const linkedCaseId = requireString(d.linkedCaseId, 'Rescue case', {max: 128, optional: true});
  // Figma "Include In-Kind Donations": descriptive only, no quantity accounting.
  const inKindDescription = requireString(d.inKindDescription, 'In-kind donations used', {max: 500, optional: true});

  const campaignRef = campaignsCol().doc(d.campaignId);
  const allocRef = campaignRef.collection('allocations').doc(requestId);

  return db.runTransaction(async (tx) => {
    const [campaignSnap, existing] = await Promise.all([tx.get(campaignRef), tx.get(allocRef)]);
    if (existing.exists) return {allocationId: requestId, duplicate: true}; // retry of the same request
    if (!campaignSnap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const c = campaignSnap.data();
    assertSameOrg(actor, c);
    const m = moneyOf(c);
    if (centavos(amount) > m.available) {
      throw new HttpsError('failed-precondition', `Only ₱${pesos(m.available).toFixed(2)} is available to allocate.`);
    }
    const now = FieldValue.serverTimestamp();
    tx.set(allocRef, {
      kind: 'expense',
      label,
      category,
      amount,
      date: formatManilaDate(new Date()),
      notes,
      receiptUrl,
      linkedCaseId,
      inKindDescription,
      status: 'recorded',
      recordedBy: actor.uid,
      recordedByName: actor.name,
      createdAt: now,
    });
    tx.update(campaignRef, {allocatedAmount: FieldValue.increment(amount), updatedAt: now});
    historyEntry(tx, campaignRef, actor, 'allocation_recorded', {allocationId: requestId, amount, category});
    return {allocationId: requestId, duplicate: false};
  });
});

// Moves eligible excess (verified collections above the target) to another
// campaign of the same organization with a shared purpose tag. Recorded as a
// transfer, never as a donation: the destination's collectedAmount and the
// original donor records are untouched.
exports.reallocateExcess = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  const sourceId = requireCampaignId(d.sourceCampaignId, 'source campaign');
  const destinationId = requireCampaignId(d.destinationCampaignId, 'destination campaign');
  if (sourceId === destinationId) throw new HttpsError('invalid-argument', 'Choose a different destination campaign.');
  const requestId = requireRequestId(d.requestId);
  const amount = requireAmount(d.amount, 'Amount');
  const reason = requireString(d.reason, 'Reason', {max: 1000});

  const srcRef = campaignsCol().doc(sourceId);
  const dstRef = campaignsCol().doc(destinationId);
  const transferRef = db.collection('fundTransfers').doc(requestId);

  return db.runTransaction(async (tx) => {
    const [transferSnap, srcSnap, dstSnap] = await Promise.all([tx.get(transferRef), tx.get(srcRef), tx.get(dstRef)]);
    if (transferSnap.exists) {
      const t = transferSnap.data();
      if (t.sourceCampaignId !== sourceId || t.destinationCampaignId !== destinationId || t.amount !== amount) {
        throw new HttpsError('already-exists', 'This request id was already used for a different transfer.');
      }
      return {transferId: requestId, duplicate: true};
    }
    if (!srcSnap.exists || !dstSnap.exists) throw new HttpsError('not-found', 'Campaign not found.');
    const src = srcSnap.data();
    const dst = dstSnap.data();
    assertSameOrg(actor, src);
    assertSameOrg(actor, dst);

    if ((src.type || 'donation') !== 'donation' || (dst.type || 'donation') !== 'donation') {
      throw new HttpsError('failed-precondition', 'Only donation campaigns can transfer or receive excess funds.');
    }
    if (src.restricted === true) throw new HttpsError('failed-precondition', 'This campaign\'s funds are restricted to their original purpose.');
    if ((src.organizationId || null) !== (dst.organizationId || null)) {
      throw new HttpsError('failed-precondition', 'Funds can only move between campaigns of the same organization.');
    }
    const srcTags = Array.isArray(src.purposeTags) ? src.purposeTags : [];
    const dstTags = Array.isArray(dst.purposeTags) ? dst.purposeTags : [];
    const shared = srcTags.filter((t) => dstTags.includes(t));
    if (!shared.length) throw new HttpsError('failed-precondition', 'The destination must share a purpose tag with this campaign.');
    if (statusOf(src) === 'draft') throw new HttpsError('failed-precondition', 'The source campaign is a draft.');
    if (statusOf(dst) !== 'active') throw new HttpsError('failed-precondition', 'The destination campaign must be active.');

    const m = moneyOf(src);
    if (m.target <= 0 || m.collected <= m.target) {
      throw new HttpsError('failed-precondition', 'This campaign has not raised more than its goal, so it has no excess.');
    }
    if (centavos(amount) > m.eligibleExcess) {
      throw new HttpsError('failed-precondition', `Only ₱${pesos(m.eligibleExcess).toFixed(2)} of excess is eligible for reallocation.`);
    }

    const now = FieldValue.serverTimestamp();
    const record = {
      sourceCampaignId: sourceId,
      sourceTitle: src.title || '',
      sourcePurposeTags: srcTags,
      destinationCampaignId: destinationId,
      destinationTitle: dst.title || '',
      destinationPurposeTags: dstTags,
      sharedPurposeTags: shared,
      amount,
      currency: 'PHP',
      reason,
      status: 'completed',
      kind: 'excess_reallocation',
      organizationId: src.organizationId || null,
      sourceCollectedAtTransfer: pesos(m.collected),
      sourceTargetAtTransfer: pesos(m.target),
      byUid: actor.uid,
      byName: actor.name,
      createdAt: now,
    };
    tx.create(transferRef, record);
    tx.update(srcRef, {transferredOutAmount: FieldValue.increment(amount), updatedAt: now});
    tx.update(dstRef, {transferredInAmount: FieldValue.increment(amount), updatedAt: now});
    // Public trail on both detail pages. The source's Fund Tracking list shows
    // it as an outflow; the destination gets an update, not a donation.
    tx.set(srcRef.collection('allocations').doc(requestId), {
      kind: 'transfer_out',
      label: `Transferred to "${dst.title || 'another campaign'}"`,
      category: 'Excess reallocation',
      amount,
      date: formatManilaDate(new Date()),
      transferId: requestId,
      destinationCampaignId: destinationId,
      notes: reason,
      status: 'recorded',
      recordedBy: actor.uid,
      recordedByName: actor.name,
      createdAt: now,
    });
    tx.set(dstRef.collection('updates').doc(requestId), {
      type: 'transfer_in',
      title: `₱${amount.toFixed(2)} of existing funds allocated from "${src.title || 'another campaign'}" (not a new donation)`,
      date: formatManilaDate(new Date()),
      transferId: requestId,
      createdAt: now,
    });
    historyEntry(tx, srcRef, actor, 'excess_transferred_out', {transferId: requestId, amount, destinationCampaignId: destinationId, reason});
    historyEntry(tx, dstRef, actor, 'excess_transferred_in', {transferId: requestId, amount, sourceCampaignId: sourceId, reason});
    return {transferId: requestId, duplicate: false};
  });
});

// In-kind pledges (donation_review_inkind.dart writes them with status
// 'inprogress'). action: 'received' (needs quantityReceived and, when the
// campaign lists quantities, itemIndex) | 'cancel' | 'follow_up'.
exports.manageInKindDonation = onCall(async (request) => {
  const actor = await loadActor(request);
  const {donationId, action, itemIndex, quantityReceived, notes} = request.data || {};
  if (typeof donationId !== 'string' || !CAMPAIGN_ID_PATTERN.test(donationId)) throw new HttpsError('invalid-argument', 'A valid donationId is required.');
  const note = requireString(notes, 'Notes', {max: 1000, optional: true});
  const donationRef = db.collection('donations').doc(donationId);

  if (action === 'follow_up') {
    const snap = await donationRef.get();
    if (!snap.exists || snap.data().type !== 'inkind') throw new HttpsError('not-found', 'In-kind donation not found.');
    const p = snap.data();
    const c = p.campaignId ? await campaignsCol().doc(p.campaignId).get() : null;
    if (c && c.exists) assertSameOrg(actor, c.data());
    if (typeof p.userId !== 'string') throw new HttpsError('failed-precondition', 'This pledge has no donor account to notify.');
    await db.collection('users').doc(p.userId).collection('notifications').add({
      title: 'In-Kind Donation Follow-up',
      message: `We are following up on your in-kind donation for ${(c && c.exists && c.data().title) || 'our campaign'}. Please let us know if you have any updates!`,
      timestamp: FieldValue.serverTimestamp(),
      isRead: false,
      type: 'inkind_followup',
      donationId,
    });
    await donationRef.update({lastFollowUpAt: FieldValue.serverTimestamp(), lastFollowUpBy: actor.uid});
    return {status: p.status};
  }

  if (action !== 'received' && action !== 'cancel') throw new HttpsError('invalid-argument', 'Unknown action.');

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(donationRef);
    if (!snap.exists || snap.data().type !== 'inkind') throw new HttpsError('not-found', 'In-kind donation not found.');
    const p = snap.data();
    const campaignRef = p.campaignId ? campaignsCol().doc(p.campaignId) : null;
    const campaignSnap = campaignRef ? await tx.get(campaignRef) : null;
    // Donor name for the certificate (all reads before any write).
    const donorSnap = action === 'received' && typeof p.userId === 'string' ?
      await tx.get(db.collection('users').doc(p.userId)) : null;
    if (campaignSnap && campaignSnap.exists) assertSameOrg(actor, campaignSnap.data());
    const current = String(p.status || '').toLowerCase();
    if (current === 'complete' || current === 'completed' || current === 'cancelled') {
      throw new HttpsError('failed-precondition', 'This pledge was already resolved.');
    }
    const now = FieldValue.serverTimestamp();
    // 'complete' / 'cancelled' are the values HistoryItem.fromFirestore maps.
    const update = action === 'received' ?
      {status: 'complete', receivedAt: now, confirmedBy: actor.uid, confirmedByName: actor.name, receiptNotes: note} :
      {status: 'cancelled', cancelledAt: now, cancelledBy: actor.uid, receiptNotes: note};

    if (action === 'received') {
      const q = quantityReceived === undefined || quantityReceived === null ? null : Number(quantityReceived);
      if (q !== null && (!Number.isInteger(q) || q <= 0 || q > 100000)) throw new HttpsError('invalid-argument', 'Quantity received must be a whole number.');
      update.quantityReceived = q;
      if (campaignSnap && campaignSnap.exists && q !== null && Number.isInteger(itemIndex)) {
        const items = Array.isArray(campaignSnap.data().inKindItems) ? [...campaignSnap.data().inKindItems] : [];
        if (itemIndex < 0 || itemIndex >= items.length) throw new HttpsError('invalid-argument', 'Unknown in-kind item.');
        const it = {...items[itemIndex]};
        it.quantityReceived = (Number.isInteger(it.quantityReceived) ? it.quantityReceived : 0) + q;
        items[itemIndex] = it;
        update.itemIndex = itemIndex;
        tx.update(campaignRef, {inKindItems: items, updatedAt: now});
      }
    }
    tx.update(donationRef, update);
    if (typeof p.userId === 'string') {
      tx.set(db.collection('users').doc(p.userId).collection('history').doc(donationId), {status: update.status}, {merge: true});
    }
    if (donorSnap) {
      const c = campaignSnap && campaignSnap.exists ? campaignSnap.data() : {};
      const items = [p.category, p.clarification].filter((s) => typeof s === 'string' && s.trim()).join(': ');
      const qty = update.quantityReceived ? `${update.quantityReceived} × ` : '';
      issueCertificate(tx, {
        uid: p.userId,
        id: donationId,
        type: 'inkind',
        recipientName: displayName(donorSnap.data()) === 'Admin' ? 'Our Supporter' : displayName(donorSnap.data()),
        organizationName: c.organizer || p.organizer || p.organizationName,
        contribution: `${qty}${items || 'in-kind goods'}`.slice(0, 200),
        benefit: certificateBenefit(c, c.title),
        campaignId: p.campaignId || null,
        campaignTitle: c.title || null,
        refNumber: p.refNumber || null,
      });
    }
    if (campaignRef && campaignSnap && campaignSnap.exists) {
      historyEntry(tx, campaignRef, actor, action === 'received' ? 'inkind_received' : 'inkind_cancelled', {donationId, quantityReceived: update.quantityReceived || null});
    }
    return {status: update.status};
  });
});

// ── Scheduled: deadline evaluation ──────────────────────────────────────────
//
// Authoritative end-of-campaign transition (the app does not need to be
// open). Index: campaigns (isActive ASC, date ASC).
exports.evaluateCampaignDeadlines = onSchedule('every 60 minutes', async () => {
  const due = await campaignsCol()
      .where('isActive', '==', true)
      .where('date', '<=', Timestamp.now())
      .limit(EXPIRY_BATCH)
      .get();
  for (const doc of due.docs) {
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (!snap.exists) return;
        const c = snap.data();
        if (c.isActive !== true || !(c.date instanceof Timestamp) || c.date.toMillis() > Date.now()) return;
        if (!['active', undefined, null, ''].includes(c.status)) return;
        const m = moneyOf(c);
        const met = m.target <= 0 || m.collected >= m.target;
        const status = met ? 'goal_met' : 'goal_not_met';
        tx.update(doc.ref, {
          status,
          isActive: false,
          // Asked once; resolveExpiredCampaign clears it.
          needsExtensionDecision: !met,
          deadlineEvaluatedAt: FieldValue.serverTimestamp(),
        });
        tx.set(doc.ref.collection('history').doc(), {
          type: 'deadline_reached',
          to: status,
          collectedAtDeadline: pesos(m.collected),
          targetAtDeadline: pesos(m.target),
          byUid: 'system',
          byName: 'System',
          at: FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      logger.error('evaluateCampaignDeadlines failed', {campaignId: doc.id, message: String(e && e.message)});
    }
  }
});
