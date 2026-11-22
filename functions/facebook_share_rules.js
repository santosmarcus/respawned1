// Input checks for facebookPublishAnimalRecords (functions/facebook.js),
// kept apart so they can be tested without Firestore or the Graph API.

const MAX_RECORDS = 10;
// Facebook allows many photos per post, but a long upload loop inside one
// callable risks its timeout; 20 covers a multi-animal adoption drive.
const MAX_PHOTOS = 20;
const MAX_CAPTION_LENGTH = 300;
const MAX_MESSAGE_LENGTH = 5000;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

const isHttpUrl = (v) => typeof v === 'string' && /^https:\/\//i.test(v);

/// The request's records and photos in one shape:
/// [{animalId, photos: [{url, caption}], legacy}]. `legacy` marks a request
/// from an older build that sent only `animalRecordIds` (it posts each
/// record's first photo). Throws Error with a user-facing message.
function normalizePublishItems(data) {
  const {items, animalRecordIds, message, link} = data || {};
  if (message != null && (typeof message !== 'string' || message.length > MAX_MESSAGE_LENGTH)) {
    throw new Error(`The post text must be under ${MAX_MESSAGE_LENGTH} characters.`);
  }
  if (link != null && !isHttpUrl(link)) throw new Error('The link must be an https:// address.');

  let out;
  if (Array.isArray(items)) {
    out = items.map((item) => {
      const animalId = item && item.animalId;
      if (typeof animalId !== 'string' || !ID_PATTERN.test(animalId)) throw new Error('Invalid animal record.');
      const photos = Array.isArray(item.photos) ? item.photos : [];
      return {
        animalId,
        legacy: false,
        photos: photos.map((p) => {
          if (!p || !isHttpUrl(p.url)) throw new Error('Invalid photo.');
          const caption = typeof p.caption === 'string' ? p.caption.trim() : '';
          if (caption.length > MAX_CAPTION_LENGTH) {
            throw new Error(`Photo descriptions must be under ${MAX_CAPTION_LENGTH} characters.`);
          }
          return {url: p.url, caption};
        }),
      };
    });
  } else if (Array.isArray(animalRecordIds)) {
    out = animalRecordIds.map((animalId) => {
      if (typeof animalId !== 'string' || !ID_PATTERN.test(animalId)) throw new Error('Invalid animal record.');
      return {animalId, legacy: true, photos: []};
    });
  } else {
    out = [];
  }

  if (out.length === 0) throw new Error('Select at least one animal record.');
  if (out.length > MAX_RECORDS) throw new Error(`Share up to ${MAX_RECORDS} records at a time.`);
  if (new Set(out.map((i) => i.animalId)).size !== out.length) throw new Error('A record was selected twice.');
  const photoCount = out.reduce((n, i) => n + (i.legacy ? 1 : i.photos.length), 0);
  if (photoCount > MAX_PHOTOS) throw new Error(`A post can carry up to ${MAX_PHOTOS} photos.`);
  return out;
}

/// Which records facebookPublishRecordPost can share, and the Firestore
/// collection each lives in.
/// `referral` is a rescue case referred by shared link (the app's Refer →
/// Post to Facebook Page); its post links to the referral web page.
const RECORD_KINDS = {campaign: 'campaigns', event: 'events', referral: 'cases'};

/// Input for facebookPublishRecordPost: one campaign or event, the post
/// text, and whether to attach the record's own cover photo. Throws Error
/// with a user-facing message.
function normalizeRecordPost(data) {
  const {kind, recordId, message, includePhoto} = data || {};
  if (!Object.prototype.hasOwnProperty.call(RECORD_KINDS, kind)) throw new Error('Pick a campaign, an event or a referral to share.');
  if (typeof recordId !== 'string' || !ID_PATTERN.test(recordId)) throw new Error('Invalid record.');
  if (typeof message !== 'string' || message.trim().length === 0) throw new Error('Write the post text first.');
  if (message.length > MAX_MESSAGE_LENGTH) throw new Error(`The post text must be under ${MAX_MESSAGE_LENGTH} characters.`);
  return {kind, collection: RECORD_KINDS[kind], recordId, message: message.trim(), includePhoto: includePhoto === true};
}

/// Why a record can't be posted right now, or null when it can. Drafts and
/// archived campaigns aren't public; cancelled events would advertise
/// something that isn't happening.
function recordPostBlockedReason(kind, record) {
  if (kind === 'campaign') {
    if (record.status === 'draft') return 'Publish this campaign before sharing it.';
    if (record.status === 'archived') return 'Archived campaigns can no longer be shared.';
  }
  if (kind === 'event' && record.status === 'cancelled') return 'Cancelled events can no longer be shared.';
  if (kind === 'referral' && record.status !== 'referred') return 'Refer this case before sharing it.';
  return null;
}

/// The photo a record post may carry, always read from the record itself:
/// a campaign or event's cover, or a referred case's first report photo.
function recordPhotoUrl(kind, record) {
  const url = kind === 'referral' ?
    (Array.isArray(record.photoUrls) ? record.photoUrls[0] : null) :
    record.imageUrl;
  return typeof url === 'string' && /^https:\/\//i.test(url) ? url : null;
}

/// Why [organizationId]'s Page can't carry this record, or null. A record
/// must belong to that organization, except a referral of a report no
/// organization owns yet (in the shared review pool): staff of any
/// organization that can see it may post it on their own Page.
function recordPostOrgProblem(kind, record, organizationId) {
  const owner = (record && record.organizationId) || '';
  if (owner === organizationId) return null;
  if (!owner && kind === 'referral') return null;
  return owner ?
    `This ${kind} belongs to another organization.` :
    `This ${kind} is not linked to an organization yet. Ask an admin to run the organization backfill.`;
}

module.exports = {
  MAX_RECORDS,
  MAX_PHOTOS,
  MAX_CAPTION_LENGTH,
  MAX_MESSAGE_LENGTH,
  RECORD_KINDS,
  normalizePublishItems,
  normalizeRecordPost,
  recordPostBlockedReason,
  recordPostOrgProblem,
  recordPhotoUrl,
};
