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
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const {completedCampaignFields, certificateBenefit, issueCertificate} = require('./donation_common');
const donationRules = require('./donation_rules');
const {requireOrgPermission} = require('./org_access');
const refundRules = require('./refund_rules');
const {createPaymongoRefund, PaymongoRefundError} = require('./paymongo_refunds');
const {recountActiveSponsors} = require('./sponsor_counts');
const {defineSecret} = require('firebase-functions/params');

// Same secret paymongo.js uses; recordDonationReversal needs it to refund
// through PayMongo.
const paymongoSecretKey = defineSecret('PAYMONGO_SECRET_KEY');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const CAMPAIGN_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9]{20}$/; // Firestore auto-id format

// users/{uid}.role values main.dart routes into the admin shell.

const TYPES = ['donation', 'sponsorship'];
const FUND_KINDS = ['campaign', 'animal', 'medical', 'shelter_resource', 'general'];
// Figma "Tags (Select at least 1)". Reallocation requires a shared tag.
const PURPOSE_TAGS = ['Rescue', 'Medicine & Treatment', 'Food and Supplies', 'Shelter', 'General Operations'];
// Same categories as the Figma "Allocate Funds" sheet.
const ALLOCATION_CATEGORIES = ['Food', 'Medicine and Treatment', 'Administrative', 'Bills and Utilities', 'Shelter', 'Transport', 'Other'];
// Same list as stockUnits in lib/features/admin/stock/stock_service.dart.
const STOCK_UNITS = ['pcs', 'kg', 'g', 'L', 'mL', 'sacks', 'packs', 'boxes', 'cans', 'bottles'];
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
// Organization permissions (functions/org_access.js): running listings needs
// `campaigns`; anything that moves or records money needs `financeManage`.
// Admins and the owner have both. Platform roles grant nothing here: money
// is managed only by the organization's own people.
async function loadActor(request, {finance = false} = {}) {
  const a = await requireOrgPermission(db, request, {
    anyOf: [finance ? 'financeManage' : 'campaigns'],
    message: finance ?
      "Only people who manage this organization's money can do this." :
      "You don't have permission to manage fundraising campaigns.",
  });
  return {
    uid: a.uid,
    name: a.name,
    role: a.role,
    organizationId: a.organizationId,
    canManageFinances: a.access.has('financeManage'),
  };
}

// A listing belongs to one organization; only its own people manage it.
// Older listings saved without an organization are left to the people who
// manage money.
function assertSameOrg(actor, c) {
  if (c.organizationId) {
    if (c.organizationId !== actor.organizationId) {
      throw new HttpsError('permission-denied', 'This listing belongs to another organization.');
    }
    return;
  }
  if (!actor.canManageFinances) {
    throw new HttpsError('permission-denied', 'This older listing has no organization; only people who manage money can change it.');
  }
}

async function organizerNameFor(actor) {
  if (!actor.organizationId) return null;
  const org = await db.collection('organizations').doc(actor.organizationId).get();
  const name = org.exists ? org.data().name : null;
  return typeof name === 'string' && name.trim() ? name.trim() : null;
}

// ── General fund ────────────────────────────────────────────────────────────
// Each organization has one permanent General fund at
// campaigns/general_{orgId}: an open-ended donation listing (no deadline, no
// target) for money that isn't for a particular campaign. It is created on
// first use and can't be edited, closed, deactivated or archived, so there is
// always somewhere to record unrestricted money and pay general costs from.

const GENERAL_FUND_PREFIX = 'general_';
const generalFundId = (orgId) => `${GENERAL_FUND_PREFIX}${orgId}`;
const isGeneralFund = (campaignId, c) =>
  (c && c.isGeneralFund === true) || String(campaignId || '').startsWith(GENERAL_FUND_PREFIX);

function generalFundDoc(actor, organizer) {
  return {
    title: 'General Fund',
    description: 'Donations not tied to a particular campaign. Used for any of the organization\'s rescue, care and shelter costs.',
    imageUrl: null,
    type: 'donation',
    fundKind: 'general',
    purposeTags: ['General Operations'],
    restricted: false,
    linkedCaseId: null,
    animalId: null,
    animalName: null,
    targetAmount: 0,
    acceptInKind: false,
    inKindItems: [],
    monthlyAmount: null,
    intendedUse: null,
    isGeneralFund: true,
    date: null,
    startDate: FieldValue.serverTimestamp(),
    status: 'active',
    isActive: true,
    organizer: organizer || 'Rescue Shelter',
    organizationId: actor.organizationId,
    collectedAmount: 0,
    allocatedAmount: 0,
    transferredOutAmount: 0,
    transferredInAmount: 0,
    numdonors: 0,
    needsExtensionDecision: false,
    extensionCount: 0,
    backgroundColor: 0xFFE3E0B9,
    createdBy: actor.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.uid,
  };
}

// Inside a transaction, after every other read: returns the actor's General
// fund data, creating the document (with a history entry) when it doesn't
// exist yet. `snap` is the transaction's read of generalFundId(orgId).
function ensureGeneralFund(tx, ref, snap, actor, organizer) {
  if (snap.exists) return snap.data();
  const data = generalFundDoc(actor, organizer);
  tx.create(ref, data);
  historyEntry(tx, ref, actor, 'created', {status: 'active', generalFund: true});
  return {...data, collectedAmount: 0, allocatedAmount: 0};
}

function assertNotGeneralFund(campaignId, c, what) {
  if (isGeneralFund(campaignId, c)) {
    throw new HttpsError('failed-precondition', `The General fund is permanent and can't be ${what}.`);
  }
}

// Appends an entry to the top-level auditLogs collection (Audit page,
// Donations / Expenses tabs) inside the same transaction as the change.
function auditEntry(tx, actor, {category, action, organizationId, targetType, targetId, oldValues, newValues, metadata}) {
  tx.set(db.collection('auditLogs').doc(), {
    category,
    action,
    actorId: actor.uid,
    actorName: actor.name,
    actorRole: actor.role,
    ...(organizationId ? {organizationId} : {}),
    targetType,
    targetId,
    oldValues: oldValues || null,
    newValues: newValues || null,
    metadata: metadata || null,
    createdAt: FieldValue.serverTimestamp(),
  });
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
    const unit = requireString(it.unit, `In-kind item ${i + 1} unit`, {max: 30, optional: true});
    if (unit && !STOCK_UNITS.includes(unit)) {
      throw new HttpsError('invalid-argument', `In-kind item ${i + 1} has an unknown unit.`);
    }
    return {
      // category + description are what donation_detail.dart already shows.
      category,
      description: requireString(it.description, `In-kind item ${i + 1} description`, {max: 300}),
      quantityNeeded,
      unit,
      instructions: requireString(it.instructions, `In-kind item ${i + 1} delivery instructions`, {max: 500, optional: true}),
      // Owned by manageInKindDonation(); saveCampaign restores it on edit.
      quantityReceived: 0,
    };
  });
}

// A sponsorship listing that is still taking (or about to take) sponsors.
const OPEN_SPONSORSHIP_STATUSES = ['draft', 'active', 'paused'];

// Why an animals/{id} doc can't get a new sponsorship listing, or null when
// it is ready. Mirrors sponsorshipReadiness() in
// lib/features/admin/donation/sponsorable_animals.dart.
function sponsorshipBlocker(a) {
  if (!a) return 'does not exist.';
  if (a.archived === true) return 'is archived.';
  if (a.status === 'deceased' || a.adoptionStatus === 'deceased') return 'is deceased.';
  if (a.adoptionStatus === 'adopted' || a.status === 'adopted') return 'has already been adopted.';
  if (a.transferStatus === 'pending') return 'is being transferred to another organization.';
  return null;
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
    // Choosing (or changing) the animal on a sponsorship: it must be ready to
    // be sponsored and not already have an open sponsorship listing.
    if (type === 'sponsorship' && (!existing || existing.animalId !== animalId)) {
      const notReady = sponsorshipBlocker(a);
      if (notReady) throw new HttpsError('failed-precondition', `${a.name || 'This animal'} ${notReady}`);
      const open = await campaignsCol().where('animalId', '==', animalId).where('type', '==', 'sponsorship').get();
      if (open.docs.some((d) => OPEN_SPONSORSHIP_STATUSES.includes(statusOf(d.data())))) {
        throw new HttpsError('already-exists', `${a.name || 'This animal'} already has an open sponsorship listing.`);
      }
    }
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
  assertNotGeneralFund(campaignId, existing, 'edited');
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
    if (action !== 'publish') {
      assertNotGeneralFund(campaignId, c, action === 'deactivate' ? 'deactivated' : `${action}d`);
    }
    const status = statusOf(c);
    const deadlinePassed =c.date instanceof Timestamp && c.date.toMillis() <= Date.now();
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
// Deciding what happens to an ended campaign's money is a money decision.
exports.resolveExpiredCampaign = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
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
      // Money raised for a specific animal or treatment stays with that purpose.
      if (c.restricted === true) {
        throw new HttpsError('failed-precondition', "This campaign's funds are restricted to their original purpose, so it can't become a general fund.");
      }
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
// generalFund: true (instead of campaignId) records it to the actor's
// organization's General fund, creating that fund on first use.
exports.recordOfflineDonation = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  const toGeneralFund = d.generalFund === true;
  if (toGeneralFund) {
    if (!actor.organizationId) {
      throw new HttpsError('failed-precondition', 'Your account is not linked to an organization, so it has no General fund.');
    }
    d.campaignId = generalFundId(actor.organizationId);
  }
  requireCampaignId(d.campaignId);
  const organizer = toGeneralFund ? await organizerNameFor(actor) : null;
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
    if (dup.exists) {
      throw new HttpsError('already-exists', toGeneralFund ?
        'A payment with this reference number was already recorded for the General fund.' :
        'A payment with this reference number was already recorded for this campaign.');
    }
    if (!campaignSnap.exists && !toGeneralFund) throw new HttpsError('not-found', 'Listing not found.');
    const c = toGeneralFund ?
      ensureGeneralFund(tx, campaignRef, campaignSnap, actor, organizer) :
      campaignSnap.data();
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
      generalFund: toGeneralFund,
      // Offline donors often have no account, so no certificate reaches
      // them: staff print an acknowledgment instead (Donation gap 8).
      acknowledgmentNumber: donationRules.acknowledgmentNumber(donationRef.id),
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
    auditEntry(tx, actor, {
      category: 'donations',
      action: toGeneralFund ? 'Offline donation recorded to the General fund' : 'Offline donation recorded',
      organizationId: c.organizationId || actor.organizationId,
      targetType: 'Donation',
      targetId: donationRef.id,
      newValues: {amount, method: label, reference, campaignId: d.campaignId, campaignTitle: c.title || ''},
    });
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
      // Analytics and the dashboard read allocations by organization.
      organizationId: c.organizationId || null,
      recordedBy: actor.uid,
      recordedByName: actor.name,
      createdAt: now,
    });
    tx.update(campaignRef, {allocatedAmount: FieldValue.increment(amount), updatedAt: now});
    historyEntry(tx, campaignRef, actor, 'allocation_recorded', {allocationId: requestId, amount, category});
    return {allocationId: requestId, duplicate: false};
  });
});

// Reverses a spending record (its expense line was removed or the expense
// deleted, see lib/core/services/expense_funding_service.dart): the
// allocation is kept for history but marked 'voided', and its amount goes
// back to the campaign's available balance. Transfers can't be voided here.
// Repeating the call for an already-voided allocation changes nothing.
exports.voidAllocation = onCall(async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  requireCampaignId(d.campaignId);
  const allocationId = requireCampaignId(d.allocationId, 'allocationId');
  const reason = requireString(d.reason, 'Reason', {max: 500});

  const campaignRef = campaignsCol().doc(d.campaignId);
  const allocRef = campaignRef.collection('allocations').doc(allocationId);

  return db.runTransaction(async (tx) => {
    const [campaignSnap, allocSnap] = await Promise.all([tx.get(campaignRef), tx.get(allocRef)]);
    if (!campaignSnap.exists) throw new HttpsError('not-found', 'Listing not found.');
    if (!allocSnap.exists) throw new HttpsError('not-found', 'Spending record not found.');
    const c = campaignSnap.data();
    assertSameOrg(actor, c);
    const a = allocSnap.data();
    if (a.status === 'voided') return {allocationId, duplicate: true};
    if ((a.kind || 'expense') !== 'expense') {
      throw new HttpsError('failed-precondition', 'Only spending records can be voided. Transfers between campaigns stay as recorded.');
    }
    const amount = num(a.amount);
    const now = FieldValue.serverTimestamp();
    tx.update(allocRef, {
      status: 'voided',
      voidReason: reason,
      voidedAt: now,
      voidedBy: actor.uid,
      voidedByName: actor.name,
    });
    tx.update(campaignRef, {allocatedAmount: FieldValue.increment(-amount), updatedAt: now});
    historyEntry(tx, campaignRef, actor, 'allocation_voided', {allocationId, amount, category: a.category || null, reason});
    auditEntry(tx, actor, {
      category: 'expenses',
      action: 'Campaign spending voided',
      organizationId: c.organizationId || actor.organizationId,
      targetType: 'CampaignAllocation',
      targetId: allocationId,
      oldValues: {status: a.status || 'recorded', amount},
      newValues: {status: 'voided', reason},
      metadata: {campaignId: d.campaignId, campaignTitle: c.title || '', label: a.label || null, linkedCaseId: a.linkedCaseId || null},
    });
    return {allocationId, duplicate: false};
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
      organizationId: src.organizationId || null,
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
    // Donation gap 5: received goods go into the organization's stock.
    const stockOrgId = (campaignSnap && campaignSnap.exists && campaignSnap.data().organizationId) ||
      p.organizationId || actor.organizationId || null;
    const stockRef = action === 'received' && stockOrgId ?
      db.collection('organizations').doc(stockOrgId).collection('stock').doc(donationRules.stockItemId(p.category)) :
      null;
    const stockSnap = stockRef ? await tx.get(stockRef) : null;
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
    if (stockRef && update.quantityReceived) {
      const listed = campaignSnap && campaignSnap.exists && Array.isArray(campaignSnap.data().inKindItems) ?
        campaignSnap.data().inKindItems : [];
      addStock(tx, stockRef, stockSnap, {
        category: p.category,
        unit: donationRules.stockUnit(Number.isInteger(itemIndex) ? listed[itemIndex] : null),
        quantity: update.quantityReceived,
        organizationId: stockOrgId,
        source: {kind: 'inkind', donationId, campaignId: p.campaignId || null},
        actor,
      });
      update.stockItemId = stockRef.id;
    }
    tx.update(donationRef, update);
    const c = campaignSnap && campaignSnap.exists ? campaignSnap.data() : {};
    const campaignTitle = c.title || p.campaignName || 'our campaign';
    const orgName = c.organizer || p.organizer || p.organizationName || 'The organization';
    const items = [p.category, p.clarification].filter((s) => typeof s === 'string' && s.trim()).join(': ');
    const hasDonor = typeof p.userId === 'string' && p.userId.length > 0;
    if (hasDonor) {
      tx.set(db.collection('users').doc(p.userId).collection('history').doc(donationId), {status: update.status}, {merge: true});
    }
    if (hasDonor && action === 'cancel') {
      tx.set(db.collection('users').doc(p.userId).collection('notifications').doc(`inkind_cancelled_${donationId}`), {
        title: 'In-Kind Pledge Cancelled',
        message: `${orgName} marked your in-kind pledge${items ? ` (${items})` : ''} for ${campaignTitle} as cancelled.` +
          (note ? ` Note: ${note}` : ''),
        timestamp: now,
        isRead: false,
        type: 'inkind_cancelled',
        donationId,
        campaignId: p.campaignId || null,
      });
    }
    if (donorSnap) {
      const qty = update.quantityReceived ? `${update.quantityReceived} × ` : '';
      issueCertificate(tx, {
        notification: {
          type: 'inkind_received',
          title: 'In-Kind Donation Received',
          message: `${orgName} confirmed they received your in-kind donation (${qty}${items || 'in-kind goods'}) ` +
            `for ${campaignTitle}. Thank you! Your certificate is in Profile → Certificates.`,
        },
                details: {
                  inKindCategory: typeof p.category === 'string' && p.category.trim() ? p.category.trim() : null,
                  inKindItems: typeof p.clarification === 'string' && p.clarification.trim() ?
                    p.clarification.trim().slice(0, 500) : null,
                  quantityReceived: update.quantityReceived || null,
                },
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
    // donorNotified tells the admin UI whether a donor account was told.
    return {
      status: update.status,
      donorNotified: hasDonor,
      donorName: p.isAnonymous === true ? 'Anonymous' : (p.donorName || null),
    };
  });
});

// ── In-kind stock (Donation gap 5) ──────────────────────────────────────────
// organizations/{orgId}/stock/{itemId}: {name, category, unit, quantity,
// lowStockThreshold}. Received in-kind goods are added by
// manageInKindDonation above; staff record usage and purchases in the app
// (lib/features/admin/stock/stock_page.dart). Every change is a row in
// organizations/{orgId}/stockMovements.
function addStock(tx, ref, snap, {category, unit, quantity, organizationId, source, actor}) {
  const now = FieldValue.serverTimestamp();
  const name = typeof category === 'string' && category.trim() ? category.trim() : 'Others';
  if (snap && snap.exists) {
    tx.update(ref, {quantity: FieldValue.increment(quantity), updatedAt: now, updatedBy: actor.uid});
  } else {
    tx.set(ref, {
      name,
      category: name,
      unit,
      quantity,
      lowStockThreshold: null,
      organizationId,
      createdAt: now,
      updatedAt: now,
      updatedBy: actor.uid,
    });
  }
  tx.set(db.collection('organizations').doc(organizationId).collection('stockMovements').doc(), {
    itemId: ref.id,
    itemName: (snap && snap.exists && snap.data().name) || name,
    change: quantity,
    kind: 'received',
    source,
    note: null,
    organizationId,
    byUid: actor.uid,
    byName: actor.name,
    at: now,
  });
}

// ── In-kind pledge (Donation gap 9) ─────────────────────────────────────────
// The pledge used to be written from the phone, including the campaign's
// donor count. Now one backend transaction creates the pledge, the donor's
// history entry and notification, and counts the donor, like money does.
exports.pledgeInKindDonation = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const d = request.data || {};
  requireCampaignId(d.campaignId);
  const category = requireString(d.category, 'Category', {max: 60});
  const clarification = requireString(d.clarification, 'Items', {max: 1000});
  const address = requireString(d.address, 'Address', {max: 500, optional: true}) || '';
  const isAnonymous = d.isAnonymous === true;

  const campaignRef = campaignsCol().doc(d.campaignId);
  const userRef = db.collection('users').doc(uid);
  const donationRef = db.collection('donations').doc();
  const refNumber = `REF-IK-${Date.now()}`;

  await db.runTransaction(async (tx) => {
    const [campaignSnap, userSnap] = await Promise.all([tx.get(campaignRef), tx.get(userRef)]);
    if (!campaignSnap.exists) throw new HttpsError('not-found', 'Campaign not found.');
    const c = campaignSnap.data();
    if (statusOf(c) !== 'active') throw new HttpsError('failed-precondition', 'This campaign is not taking donations right now.');
    const u = userSnap.exists ? userSnap.data() : {};
    const full = `${u.firstName || ''} ${u.lastName || ''}`.trim() || u.name || 'User';
    const organizer = c.organizer || 'the organization';
    const now = FieldValue.serverTimestamp();
    // Same fields donation_review_inkind.dart used to write.
    const record = {
      userId: uid,
      donorName: isAnonymous ? 'Anonymous' : full,
      campaignId: d.campaignId,
      campaignName: c.title || '',
      organizationName: c.organizer || '',
      organizer: c.organizer || '',
      organizationId: c.organizationId || null,
      category,
      clarification,
      itemDescription: `${category}: ${clarification}`,
      isAnonymous,
      address,
      timestamp: now,
      createdAt: now,
      date: formatManilaDate(new Date()),
      refNumber,
      status: 'inprogress',
      type: 'inkind',
      amount: 0,
      amountString: `In-kind: ${category}`,
      source: 'app',
    };
    tx.set(donationRef, record);
    tx.set(userRef.collection('history').doc(donationRef.id), record);
    tx.set(userRef.collection('notifications').doc(`inkind_pledged_${donationRef.id}`), {
      title: 'In-Kind Pledge Recorded',
      message: `Your pledge of ${category} to ${organizer} was recorded. ` +
        'You will be notified once they confirm receiving the items.',
      timestamp: now,
      isRead: false,
      type: 'inkind_pledged',
      donationId: donationRef.id,
      campaignId: d.campaignId,
    });
    tx.set(userRef.collection('donated').doc(d.campaignId), {donationId: d.campaignId, donatedAt: now});
    tx.update(campaignRef, {numdonors: FieldValue.increment(1)});
    tx.set(campaignRef.collection('history').doc(), {
      type: 'inkind_pledged',
      donationId: donationRef.id,
      category,
      byUid: uid,
      byName: isAnonymous ? 'Anonymous' : full,
      at: now,
    });
  });
  return {donationId: donationRef.id, refNumber};
});

// ── Refunds and reversals (Donation gap 3) ──────────────────────────────────
// A financial admin records that money already credited was given back
// (refunded in PayMongo, a bounced check, an offline entry made by mistake).
// The donation is kept but marked 'reversed', the campaign's collected total
// and donor count go down, the donor's certificate is voided and they are
// told. Refused while the money is already spent: void a spending record
// first. Repeating the call for a refunded donation changes nothing.
// action (default 'record'):
//   record   staff record a refund made outside the app (no request needed).
//   approve  approve the donor's refund request (donations/{id}.refundRequest):
//            refunds through PayMongo when it can (refund_rules.refundRoute),
//            otherwise needs `reference` for a refund made by hand.
//   decline  decline the donor's request, with `reason` shown to the donor.
exports.recordDonationReversal = onCall({secrets: [paymongoSecretKey]}, async (request) => {
  const actor = await loadActor(request, {finance: true});
  const d = request.data || {};
  if (typeof d.donationId !== 'string' || !CAMPAIGN_ID_PATTERN.test(d.donationId)) {
    throw new HttpsError('invalid-argument', 'A valid donationId is required.');
  }
  const action = d.action || 'record';
  if (!['record', 'approve', 'decline'].includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const reason = requireString(d.reason, 'Reason', {max: 1000});
  const reference = requireString(d.reference, 'Refund reference', {max: 120, optional: true});
  const donationRef = db.collection('donations').doc(d.donationId);

  if (action === 'decline') return declineRefundRequest(actor, donationRef, reason);
  if (action === 'record') {
    const out = await reverseDonation(actor, donationRef, {reason, reference});
    await afterReversal(out);
    return {status: out.status, duplicate: out.duplicate};
  }

  // approve
  const snap = await donationRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Donation not found.');
  const r = snap.data();
  const rr = r.refundRequest || null;
  if (!rr || !['requested', 'failed'].includes(rr.status)) {
    throw new HttpsError('failed-precondition', 'There is no open refund request for this donation.');
  }
  const campaignSnap = typeof r.campaignId === 'string' && CAMPAIGN_ID_PATTERN.test(r.campaignId) ?
    await campaignsCol().doc(r.campaignId).get() : null;
  const c = campaignSnap && campaignSnap.exists ? campaignSnap.data() : null;
  assertSameOrg(actor, c || r);
  // Refuse before any money moves when it is already spent.
  const blocker = donationRules.reversalBlocker(r, c ? moneyOf(c) : null, centavos(num(r.amount)));
  if (blocker) throw new HttpsError('failed-precondition', blocker);

  let refundId = rr.paymongoRefundId || null;
  let refundStatus = rr.paymongoRefundStatus || null;
  let method = 'manual';
  if (!refundId) {
    const paymentSnap = await db.collection('donationPayments').doc(d.donationId).get();
    const payment = paymentSnap.exists ? paymentSnap.data() : null;
    const route = refundRules.refundRoute(payment && {
      ...payment,
      paidAtMs: payment.paidAt instanceof Timestamp ? payment.paidAt.toMillis() : null,
    }, {nowMs: Date.now()});
    if (route.route === 'paymongo' && !reference) {
      try {
        const refund = await createPaymongoRefund(paymongoSecretKey.value(), {
          paymentId: payment.paymongoPaymentId,
          amountCentavos: Number.isInteger(payment.amountCreditedCentavos) ? payment.amountCreditedCentavos : centavos(num(r.amount)),
          reason: refundRules.REASONS[rr.reason] || 'others',
          notes: `ResPAWnd refund request ${d.donationId}`,
        });
        refundId = refund.id;
        refundStatus = refund.status;
        method = 'paymongo';
        // Saved before the records change, so a retry never refunds twice.
        await donationRef.update({
          'refundRequest.paymongoRefundId': refundId,
          'refundRequest.paymongoRefundStatus': refundStatus,
          'refundRequest.status': 'processing',
        });
      } catch (e) {
        const codes = e instanceof PaymongoRefundError ? e.codes : [];
        logger.error('PayMongo refund failed', {donationId: d.donationId, httpStatus: e.httpStatus || null, codes});
        await donationRef.update({
          'refundRequest.status': 'failed',
          'refundRequest.failCodes': codes,
          'refundRequest.failedAt': FieldValue.serverTimestamp(),
        });
        throw new HttpsError('failed-precondition',
            `PayMongo could not refund this payment${codes.length ? ` (${codes.join(', ')})` : ''}. ` +
            'Refund it by hand, then approve again with the reference number.');
      }
    } else if (!reference) {
      throw new HttpsError('failed-precondition',
          `${route.why} Refund it by hand (e.g. GCash or bank transfer), then approve with the reference number.`);
    }
  } else {
    method = 'paymongo';
  }

  const out = await reverseDonation(actor, donationRef, {
    reason: `Refund request approved (${rr.reason}). ${reason}`,
    reference: refundId || reference,
    refundRequest: {
      status: 'refunded',
      method,
      paymongoRefundId: refundId,
      paymongoRefundStatus: refundStatus,
      manualReference: method === 'manual' ? reference : null,
    },
  });
  await afterReversal(out);
  return {status: 'reversed', method, paymongoRefundId: refundId};
});

async function declineRefundRequest(actor, donationRef, reason) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(donationRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Donation not found.');
    const r = snap.data();
    const rr = r.refundRequest || null;
    if (!rr || !['requested', 'failed'].includes(rr.status)) {
      throw new HttpsError('failed-precondition', 'There is no open refund request for this donation.');
    }
    const campaignSnap = typeof r.campaignId === 'string' && CAMPAIGN_ID_PATTERN.test(r.campaignId) ?
      await tx.get(campaignsCol().doc(r.campaignId)) : null;
    const c = campaignSnap && campaignSnap.exists ? campaignSnap.data() : null;
    assertSameOrg(actor, c || r);
    const now = FieldValue.serverTimestamp();
    tx.update(donationRef, {
      'refundRequest.status': 'declined',
      'refundRequest.declineReason': reason,
      'refundRequest.decidedAt': now,
      'refundRequest.decidedBy': actor.uid,
      'refundRequest.decidedByName': actor.name,
    });
    if (typeof r.userId === 'string' && r.userId) {
      tx.set(db.collection('users').doc(r.userId).collection('notifications').doc(`refund_declined_${snap.id}`), {
        title: 'Refund Request Declined',
        message: `Your refund request for ${r.amountString || 'your donation'} to ${r.campaignName || 'a campaign'} ` +
          `was declined. Reason: ${reason}`,
        timestamp: now,
        isRead: false,
        type: 'refund_declined',
        donationId: snap.id,
      });
    }
    auditEntry(tx, actor, {
      category: 'donations',
      action: 'Refund request declined',
      organizationId: (c && c.organizationId) || r.organizationId || actor.organizationId,
      targetType: 'Donation',
      targetId: snap.id,
      oldValues: {refundRequest: rr.status},
      newValues: {refundRequest: 'declined', reason},
      metadata: {campaignId: r.campaignId || null, requestReason: rr.reason || null},
    });
    return {status: 'declined'};
  });
}

async function afterReversal(out) {
  if (out && out.sponsorshipCampaignId) {
    await recountActiveSponsors(out.sponsorshipCampaignId).catch((e) =>
      logger.warn('recountActiveSponsors failed', {campaignId: out.sponsorshipCampaignId, message: e.message}));
  }
}

// The records side of a refund: donation marked reversed, campaign total
// and donor count lowered, certificate voided, donor told, history and
// audit entries. Refused while the money is already spent.
async function reverseDonation(actor, donationRef, {reason, reference, refundRequest}) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(donationRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Donation not found.');
    const r = snap.data();
    const donationId = snap.id;
    if (r.status === 'reversed') return {status: 'reversed', duplicate: true};
    const campaignRef = typeof r.campaignId === 'string' && CAMPAIGN_ID_PATTERN.test(r.campaignId) ?
      campaignsCol().doc(r.campaignId) : null;
    const campaignSnap = campaignRef ? await tx.get(campaignRef) : null;
    const c = campaignSnap && campaignSnap.exists ? campaignSnap.data() : null;
    assertSameOrg(actor, c || r);
    const amount = num(r.amount);
    const blocker = donationRules.reversalBlocker(r, c ? moneyOf(c) : null, centavos(amount));
    if (blocker) throw new HttpsError('failed-precondition', blocker);

    const now = FieldValue.serverTimestamp();
    const isSponsorship = r.type === 'sponsorship';
    tx.update(donationRef, {
      status: 'reversed',
      statusBeforeReversal: r.status || null,
      // A refunded sponsorship no longer covers the animal.
      ...(isSponsorship ? {sponsorshipStatus: 'refunded'} : {}),
      reversedAt: now,
      reversedBy: actor.uid,
      reversedByName: actor.name,
      reversalReason: reason,
      reversalReference: reference,
      ...(refundRequest ? {
        'refundRequest.status': refundRequest.status,
        'refundRequest.method': refundRequest.method,
        'refundRequest.paymongoRefundId': refundRequest.paymongoRefundId || null,
        'refundRequest.paymongoRefundStatus': refundRequest.paymongoRefundStatus || null,
        'refundRequest.manualReference': refundRequest.manualReference || null,
        'refundRequest.decidedAt': now,
        'refundRequest.decidedBy': actor.uid,
        'refundRequest.decidedByName': actor.name,
      } : {}),
    });
    if (typeof r.userId === 'string' && r.userId) {
      const userRef = db.collection('users').doc(r.userId);
      tx.set(userRef.collection('history').doc(donationId),
          {status: 'reversed', ...(isSponsorship ? {sponsorshipStatus: 'refunded'} : {})}, {merge: true});
      // Certificates use the payment id (online) or the donation id; both
      // are this record's id, see paymongo.js and issueCertificate().
      tx.set(userRef.collection('certificates').doc(donationId),
          {voided: true, voidedAt: now, voidReason: reason}, {merge: true});
      const viaPaymongo = refundRequest && refundRequest.method === 'paymongo';
      tx.set(userRef.collection('notifications').doc(`donation_reversed_${donationId}`), {
        title: 'Donation Refunded',
        message: `Your ${r.amountString || `₱${amount.toFixed(2)}`} ${isSponsorship ? 'sponsorship' : 'donation'} to ` +
          `${r.campaignName || 'a campaign'} was refunded` +
          (viaPaymongo ? ' through PayMongo to your original payment method.' : '.') +
          ' Its certificate is no longer valid.',
        timestamp: now,
        isRead: false,
        type: 'donation_reversed',
        donationId,
      });
    }
    if (c) {
      tx.update(campaignRef, {
        collectedAmount: FieldValue.increment(-amount),
        numdonors: FieldValue.increment(donationRules.donorCountChange(c.numdonors)),
        updatedAt: now,
      });
      historyEntry(tx, campaignRef, actor, 'donation_reversed', {donationId, amount, reason, reference});
    }
    auditEntry(tx, actor, {
      category: 'donations',
      action: refundRequest ? 'Refund request approved' : 'Donation refunded',
      organizationId: (c && c.organizationId) || r.organizationId || actor.organizationId,
      targetType: 'Donation',
      targetId: donationId,
      oldValues: {status: r.status || null, amount},
      newValues: {status: 'reversed', reason, reference, method: refundRequest ? refundRequest.method : 'recorded'},
      metadata: {campaignId: r.campaignId || null, campaignTitle: (c && c.title) || r.campaignName || null, source: r.source || 'paymongo'},
    });
    return {status: 'reversed', duplicate: false, sponsorshipCampaignId: isSponsorship ? r.campaignId : null};
  });
}

// ── Donation audit trail (Donation gap 4) ───────────────────────────────────
// Every money and listing action above already writes campaigns/{id}/history
// (and so do paymongo.js and the deadline job). This copies each entry to the
// central auditLogs with the campaign's organization, so the Audit page's
// Donations and Expenses tabs list them. Entries the source function already
// audited are skipped (donation_rules.js AUDITED_AT_SOURCE). The audit id is
// derived from the history id, so a retried trigger writes the same entry.
exports.mirrorCampaignHistoryToAudit = onDocumentCreated('campaigns/{campaignId}/history/{entryId}', async (event) => {
  const h = event.data && event.data.data();
  if (!h || !donationRules.shouldMirrorHistory(h.type)) return;
  const campaign = await campaignsCol().doc(event.params.campaignId).get();
  const c = campaign.exists ? campaign.data() : {};
  await db.collection('auditLogs').doc(`campaign_${event.params.campaignId}_${event.params.entryId}`).set({
    category: donationRules.historyCategory(h.type),
    action: donationRules.historyAction(h.type),
    actorId: h.byUid || null,
    actorName: h.byName || null,
    ...(c.organizationId ? {organizationId: c.organizationId} : {}),
    targetType: c.type === 'sponsorship' ? 'Sponsorship' : 'Campaign',
    targetId: event.params.campaignId,
    oldValues: null,
    newValues: donationRules.historyDetails(h),
    metadata: {campaignTitle: c.title || null, historyType: h.type, historyId: event.params.entryId},
    createdAt: h.at || FieldValue.serverTimestamp(),
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
