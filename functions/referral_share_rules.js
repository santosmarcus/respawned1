// Pure rules for shareable referral links (functions/referral_shares.js and
// public/referral/index.html). No Firebase here, so `node --test` can check
// them directly.
//
// A referral link lets staff send a referred report to someone outside the
// app (a barangay or LGU office, another rescuer) as a web page. The page
// never reads Firestore: it gets a curated copy of the report through the
// getReferralShare callable, keyed by an unguessable token that expires and
// can be revoked. The recipient can answer from the page.

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{24}$/;

/// Days a link stays open. Pending the organization's confirmation.
const SHARE_TTL_DAYS = 30;

/// Answers the recipient can give, stored as the key.
const SHARE_RESPONSES = {
  will_handle: 'Will handle it',
  cannot_handle: 'Can\'t take it',
  need_info: 'Needs more information',
};

/// Answers accepted per link, so an open page can't be used to flood staff.
const MAX_RESPONSES_PER_SHARE = 20;

const LGU_REASON_LABELS = {
  outsideServiceArea: 'Outside service area',
  shelterAtCapacity: 'Shelter at capacity',
  nonRescueConcern: 'Non-rescue concern',
  animalControlRequired: 'Animal control required',
  publicSafetyConcern: 'Public safety concern',
  ownerDispute: 'Owner dispute',
  other: 'Other',
};

function isValidToken(token) {
  return typeof token === 'string' && TOKEN_PATTERN.test(token);
}

/// 'active', 'revoked' or 'expired'.
function shareState({revoked, expiresAtMs, nowMs}) {
  if (revoked === true) return 'revoked';
  if (typeof expiresAtMs === 'number' && nowMs >= expiresAtMs) return 'expired';
  return 'active';
}

/// The case's status in words a person outside the organization follows.
function publicStatusLabel(status) {
  switch (String(status || '')) {
    case 'pending':
    case 'possibleDuplicate':
    case 'verifying':
      return 'Under review';
    case 'referred':
      return 'Referred';
    case 'in_treatment':
      return 'In treatment';
    case 'intake':
    case 'completed':
    case 'closed':
      return 'Rescued';
    case 'rejected':
    case 'cancelled':
    case 'merged':
      return 'Closed';
    case 'accepted_pending_clinic':
    case 'accepted':
    case 'assigned':
    case 'ongoing':
    case 'searching_clinic':
    case 'arrived':
    case 'treatment':
    case 'in_transit_shelter':
    case 'dropoff':
    case 'unable_to_locate':
    case 'awaiting_reporter_response':
    case 'pickup_attempt_unsuccessful':
    case 'needs_specialized_assistance':
    case 'transit_ended':
      return 'Rescue in progress';
    default:
      return 'Under review';
  }
}

function text(v, max = 500) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  if (!t) return null;
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

function textOrBool(v) {
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  return text(v, 100);
}

function millis(v) {
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return typeof v === 'number' ? v : null;
}

const httpsUrls = (list, max) =>
  (Array.isArray(list) ? list : []).filter((u) => typeof u === 'string' && u.startsWith('https://')).slice(0, max);

function compact(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) continue;
    if (Array.isArray(v) && !v.length) continue;
    out[k] = v;
  }
  return out;
}

/// The copy of a referred report the web page shows. Only fields a
/// responder needs: the animal(s), condition and risks, photos, where it is
/// and how to reach it, why it was referred, and the organization's contact.
/// The reporter's name and phone only when staff chose to include them and
/// the reporter didn't report anonymously. Never notes, verification
/// evidence, status history or rider locations.
function buildReferralSnapshot({caseId, c, referral, org, includeReporter = false}) {
  c = c || {};
  referral = referral || {};
  org = org || {};
  const animals = (Array.isArray(c.animals) ? c.animals : []).slice(0, 10).map((a) => compact({
    species: text(a && a.species, 60),
    breed: text(a && a.breed, 80),
    sex: text(a && a.sex, 30),
    size: text(a && a.size, 30),
    colorMarkings: text(a && a.colorMarkings, 200),
    behavior: text(a && a.behavior, 200),
    bodyCondition: text(a && a.bodyCondition, 100),
    mobility: text(a && a.mobility, 100),
  }));
  const lat = typeof c.lat === 'number' ? c.lat : null;
  const lng = typeof c.lng === 'number' ? c.lng : null;
  const showReporter = includeReporter === true && c.reportAnonymously !== true;
  // An LGU referral carries the media staff chose to attach (the sheet's
  // "Attach report details and media"); none attached means no photos or
  // videos on the page.
  const lgu = referral.type === 'localGovernmentUnit';
  const attached = Array.isArray(referral.attachedMediaUrls) ? referral.attachedMediaUrls : [];
  const photoSource = lgu ? attached : c.photoUrls;
  const videoSource = lgu && !attached.length ? [] : c.videoUrls;
  return compact({
    caseRef: String(caseId || '').slice(0, 7).toUpperCase(),
    rescueType: text(c.rescueType, 60),
    urgency: text(c.urgency, 30),
    species: text(c.animalType, 60),
    animalCount: animals.length || 1,
    animals,
    condition: text(c.currentCondition, 1000) || text(c.condition, 1000),
    biteRisk: textOrBool(c.biteRisk),
    escapeRisk: textOrBool(c.escapeRisk),
    handlingNotes: text(c.handlingNotes, 1000),
    accessInstructions: text(c.accessInstructions, 1000),
    containmentStatus: text(c.containmentStatus, 200),
    photoUrls: httpsUrls(photoSource, 12),
    videoUrls: httpsUrls(videoSource, 4),
    location: lat === null || lng === null ? (text(c.address, 300) ? {address: text(c.address, 300)} : null) :
      compact({lat, lng, address: text(c.address, 300)}),
    reportedAtMs: millis(c.createdAt) || millis(c.serverCreatedAt),
    referral: compact({
      type: text(referral.type, 40),
      barangay: text(referral.barangay, 120),
      reason: referral.lguReason ? (LGU_REASON_LABELS[referral.lguReason] || 'Other') : null,
      explanation: text(referral.lguExplanation, 2000) || text(referral.note, 2000),
      referredAtMs: millis(referral.createdAt),
      referredByName: text(referral.createdByName, 120),
    }),
    organization: compact({
      name: text(org.name, 120),
      phone: text(org.phone, 40) || text(org.contactNumber, 40),
      email: text(org.email, 120),
      facebookUrl: typeof org.facebookUrl === 'string' && org.facebookUrl.startsWith('https://') ?
        org.facebookUrl : null,
    }),
    reporter: showReporter ? compact({name: text(c.reporterName, 120), phone: text(c.reporterPhone, 40)}) : null,
  });
}

/// Checks an answer from the page. Returns {value} or {error}.
function validateResponse(data) {
  const d = data || {};
  if (!Object.prototype.hasOwnProperty.call(SHARE_RESPONSES, d.response)) {
    return {error: 'Choose an answer.'};
  }
  const name = text(d.name, 200);
  if (!name) return {error: 'Enter your name or office.'};
  if (typeof d.name === 'string' && d.name.trim().length > 120) return {error: 'Name is too long (max 120).'};
  const contact = text(d.contact, 200);
  if (typeof d.contact === 'string' && d.contact.trim().length > 80) return {error: 'Contact is too long (max 80).'};
  const note = text(d.note, 2000);
  if (typeof d.note === 'string' && d.note.trim().length > 1000) return {error: 'Note is too long (max 1000).'};
  if (d.response !== 'will_handle' && !note) {
    return {error: d.response === 'cannot_handle' ? 'Say why you can\'t take it.' : 'Say what information you need.'};
  }
  return {value: compact({response: d.response, name, contact, note})};
}

/// Refer → shared link (app: CaseReferralRepository.referByLink): the case's
/// `linkReferral` after someone answers on the page, or null when this
/// answer isn't for the case's current shared-link referral. "Will handle
/// it" closes the case's wait (it leaves Review for Closed in the app);
/// "Can't take it" and "Needs more information" keep it pending.
function linkReferralUpdate(linkReferral, referralId, answer, at) {
  if (!linkReferral || typeof linkReferral !== 'object' || linkReferral.referralId !== referralId) return null;
  const state = {will_handle: 'accepted', cannot_handle: 'declined', need_info: 'needs_info'}[answer.response];
  // Once someone has taken it, later answers from others don't reopen it.
  if (!state || linkReferral.state === 'accepted') return null;
  return {
    ...linkReferral,
    state,
    answeredByName: answer.name,
    answeredByContact: answer.contact || null,
    answeredNote: answer.note || null,
    answeredAt: at,
  };
}

module.exports = {
  TOKEN_PATTERN,
  SHARE_TTL_DAYS,
  SHARE_RESPONSES,
  MAX_RESPONSES_PER_SHARE,
  LGU_REASON_LABELS,
  isValidToken,
  shareState,
  publicStatusLabel,
  buildReferralSnapshot,
  validateResponse,
  linkReferralUpdate,
};
