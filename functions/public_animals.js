// Public animal profiles.
//
// `animals/{id}` holds the full shelter record (health details, who it is
// reserved for or adopted by, the rescue case it came from, ...) and is
// readable only by the owning organization's staff and carers, platform
// staff, and the animal's own reserver/adopter (firestore.rules).
// Everyone else — the adoption list, an animal's public page, a scanned
// QR tag, a sponsor's or donor's view — reads `publicAnimals/{id}`, a copy
// of the fields meant for the public, kept in step by this trigger.
// Clients can't write it.
//
// A public copy exists while the animal is not archived, not hidden by
// staff (publicProfileHidden) and not deceased; otherwise it is deleted.
// Health is a yes/no summary only (vaccinated, spayed/neutered, dewormed,
// special needs and their types) — no notes, medications or vet details.
//
// Existing animals: scripts/backfill_public_animals.js.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// Copied as-is when present. The app parses the copy with
// AnimalRecord.fromMap, so field names match `animals/{id}`.
const PUBLIC_FIELDS = [
  'name', 'age', 'species', 'breed', 'sex', 'size', 'coatLength',
  'description', 'keyCharacteristics', 'rescueBackground', 'tags',
  'vaccinated', 'spayedNeutered', 'dewormed', 'specialNeeds', 'specialNeedsTypes',
  'adoptionStatus', 'status', 'currentStatus', 'organizationId', 'qrTagId',
  'createdAt', 'updatedAt',
];

// Legacy photo field names AnimalRecord falls back to; only download URLs
// are copied, always as `photoUrls`.
const PHOTO_LIST_FIELDS = ['photoUrls', 'images', 'imageUrls'];
const PHOTO_SINGLE_FIELDS = ['photoUrl', 'imageUrl', 'profileImage'];

const isUrl = (v) => typeof v === 'string' && /^https?:\/\//.test(v);

function photosOf(data) {
  for (const key of PHOTO_LIST_FIELDS) {
    const list = Array.isArray(data[key]) ? data[key].filter(isUrl) : [];
    if (list.length > 0) return list;
  }
  for (const key of PHOTO_SINGLE_FIELDS) {
    if (isUrl(data[key])) return [data[key]];
  }
  return [];
}

function isPublic(data) {
  if (!data) return false;
  if (data.archived === true || data.publicProfileHidden === true) return false;
  if (data.status === 'deceased' || data.adoptionStatus === 'deceased') return false;
  return true;
}

/// The public copy of an animal document, or null when it shouldn't have one.
function publicAnimalOf(data) {
  if (!isPublic(data)) return null;
  const out = {};
  for (const key of PUBLIC_FIELDS) {
    if (data[key] !== undefined) out[key] = data[key];
  }
  out.photoUrls = photosOf(data);
  return out;
}

exports.publicAnimalOf = publicAnimalOf;

exports.syncPublicAnimal = onDocumentWritten('animals/{animalId}', async (event) => {
  const after = event.data && event.data.after.exists ? event.data.after.data() : null;
  const ref = admin.firestore().collection('publicAnimals').doc(event.params.animalId);
  const copy = publicAnimalOf(after);
  if (copy) {
    await ref.set(copy);
  } else {
    await ref.delete();
  }
});
