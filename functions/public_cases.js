// Public rescue reports.
//
// `cases/{id}` holds the whole report: the reporter's name and phone,
// verification evidence, the rider's live location, notes and the status
// history. firestore.rules lets only the people working the case read it
// (staff, the reporter, the transporter or rider on it, the willing adopter,
// verified transporters) — plus anyone, for a report open to Community
// Adoption. Everyone else — the Explore map and feed, nearby reports and
// alerts, geofences, the transporter job board, duplicate checks — reads
// `publicCases/{id}`, a copy of the fields meant for the public, kept in
// step by this trigger. Clients can't write it.
//
// Surrender reports are filed from the owner's home, so their copy leaves
// out the address and rounds the location to about 100 m.
//
// Existing reports: scripts/backfill_public_cases.js.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// Copied as-is when present. The app parses the copy like a case document,
// so field names match `cases/{id}`.
const PUBLIC_FIELDS = [
  'animals', 'animalType', 'species', 'breed', 'sex', 'size', 'colorMarkings', 'condition',
  'biteRisk', 'escapeRisk', 'urgency', 'status', 'type', 'rescueType', 'groupId',
  'hiddenFromExplore', 'rejectionReason', 'photoUrls', 'videoUrls',
  'createdAt', 'serverCreatedAt', 'timestamp', 'reporterId', 'assignedVolunteerId',
  'claimedAnimalIndexes', 'dropoffAddress', 'vetClinicAddress', 'organizationId',
  'lat', 'lng', 'address',
  // Trip completion (transporter trip counts on staff screens).
  'transitCompletedAt', 'adopterPickupConfirmedAt',
  // The reporter's Community Adoption profile for each animal, shown on
  // the adoption page's Community Adoption section (community_profile.dart).
  'communityListing',
];

function isSurrender(data) {
  return String(data.rescueType || '').trim().toLowerCase() === 'surrender';
}

const round3 = (v) => (typeof v === 'number' ? Math.round(v * 1000) / 1000 : v);

/// The public copy of a case document, or null when it has none.
function publicCaseOf(data) {
  if (!data) return null;
  const out = {};
  for (const key of PUBLIC_FIELDS) {
    if (data[key] !== undefined) out[key] = data[key];
  }
  // Drop-off photos stay private; the public copy only says one exists.
  out.transitProofRecorded = Array.isArray(data.shelterVerificationUrls) && data.shelterVerificationUrls.length > 0;
  if (isSurrender(data)) {
    delete out.address;
    out.lat = round3(out.lat);
    out.lng = round3(out.lng);
  }
  return out;
}

exports.publicCaseOf = publicCaseOf;

exports.syncPublicCase = onDocumentWritten('cases/{caseId}', async (event) => {
  const after = event.data && event.data.after.exists ? event.data.after.data() : null;
  const ref = admin.firestore().collection('publicCases').doc(event.params.caseId);
  const copy = publicCaseOf(after);
  if (copy) {
    await ref.set(copy);
  } else {
    await ref.delete();
  }
});
