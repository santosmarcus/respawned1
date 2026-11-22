// Collar ID tags for shelter animals.
//
// Every animal record has a collar tag at collarTags/animal-{animalId}: the
// same document shape as a pet owner's tag (collar_tag_data_model.dart), so
// the QR code (AppLinks.tagUrl), an NFC chip written with that link, the
// in-app scanner and public/tag/index.html all open the same collar tag
// view. The app creates the tag when the record is saved
// (AnimalCollarTagRepository.sync); this trigger keeps it in step with
// every later change to the record, from any screen or function.
//
// Only the fields copied from the record are written (merge), so a tag's
// lost/found state (status, lastSeen*, activeRescueSessionId) is kept.
// Deleting the record deletes its tag.
//
// Mirrored by hand in lib/core/repos/animal_collar_tag_repository.dart.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const tagIdFor = (animalId) => `animal-${animalId}`;

const str = (v) => (typeof v === 'string' ? v.trim() : v == null ? '' : String(v));
const isUrl = (v) => typeof v === 'string' && /^https?:\/\//.test(v);

function firstPhoto(data) {
  for (const key of ['photoUrls', 'images', 'imageUrls']) {
    const list = Array.isArray(data[key]) ? data[key].filter(isUrl) : [];
    if (list.length > 0) return list[0];
  }
  for (const key of ['photoUrl', 'imageUrl', 'profileImage']) {
    if (isUrl(data[key])) return data[key];
  }
  return '';
}

function joinNonEmpty(parts, sep) {
  return parts.map(str).filter((p) => p.length > 0).join(sep);
}

/// The collar tag fields for an animal record and its organization.
function collarTagOf(animalId, data, org) {
  const o = org || {};
  const specialNeeds = Array.isArray(data.specialNeedsTypes) ? data.specialNeedsTypes : [];
  return {
    animalId,
    organizationId: str(data.organizationId),
    source: 'animal_record',
    petImageUrl: firstPhoto(data),
    name: str(data.name),
    // Shelter animals have an age, not a birthday; the views label it "Age"
    // when animalId is set.
    birthday: str(data.age),
    sex: str(data.sex),
    breed: str(data.breed) || str(data.species),
    colorMarkings: joinNonEmpty(
      [data.species, data.size, data.coatLength ? `${str(data.coatLength)} coat` : ''],
      ' · ',
    ),
    briefDescription: str(data.description),
    isSpayedNeutered: data.spayedNeutered === true,
    isVaccinated: data.vaccinated === true,
    allergies: str(data.allergies),
    medicalCondition: joinNonEmpty([data.chronicConditions, ...specialNeeds], ', '),
    ownerName: str(o.name),
    ownerMobile: str(o.contactNumber) || str(o.phone),
    ownerEmail: str(o.email),
    ownerFacebookLink: str(o.facebookUrl),
    // Staff-issued tags need no QR approval.
    qrEnabled: true,
    archived: data.archived === true || data.status === 'deceased',
  };
}

function sameFields(existing, fields) {
  return Object.keys(fields).every((k) => existing[k] === fields[k]);
}

exports.tagIdFor = tagIdFor;
exports.collarTagOf = collarTagOf;

exports.syncAnimalCollarTag = onDocumentWritten('animals/{animalId}', async (event) => {
  const animalId = event.params.animalId;
  const db = admin.firestore();
  const ref = db.collection('collarTags').doc(tagIdFor(animalId));
  const after = event.data && event.data.after.exists ? event.data.after.data() : null;
  if (!after) {
    await ref.delete();
    return;
  }

  let org = null;
  const orgId = str(after.organizationId);
  if (orgId) {
    const orgSnap = await db.collection('organizations').doc(orgId).get();
    org = orgSnap.exists ? orgSnap.data() : null;
  }

  const fields = collarTagOf(animalId, after, org);
  const existing = await ref.get();
  if (existing.exists && sameFields(existing.data(), fields)) return;
  await ref.set(
    {
      ...fields,
      ...(existing.exists ? {} : {status: 'active', createdAt: admin.firestore.FieldValue.serverTimestamp()}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
});
