// Adoption checks that need to read other people's applications.
//
// firestore.rules lets a user read only their own adoption applications
// (plus the owning organization's staff). Checking whether an animal
// already has an active or completed adoption means looking at every
// applicant's application, so it runs here with admin access and returns
// only a yes/no, never the applications themselves.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();

// Mirrors AdoptionApplicationService.hasBlockingApplication's old client
// check: anything that isn't rejected or withdrawn blocks a new application.
const NON_BLOCKING = new Set(['rejected', 'withdrawn']);

function blocks(snap) {
  return snap.docs.some((d) => !NON_BLOCKING.has(String(d.get('status') || '')));
}

/// { animalId?: string, animalRecordId?: string } -> { blocked: boolean }
/// animalId is the legacy personal.animalId key; animalRecordId is the real
/// animals/{id} document id. Either may be empty.
exports.hasBlockingAdoption = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const data = request.data || {};
  const animalId = typeof data.animalId === 'string' ? data.animalId.trim() : '';
  const animalRecordId = typeof data.animalRecordId === 'string' ? data.animalRecordId.trim() : '';
  if (!animalId && !animalRecordId) {
    throw new HttpsError('invalid-argument', 'animalId or animalRecordId is required.');
  }
  if (animalId.length > 200 || animalRecordId.length > 200) {
    throw new HttpsError('invalid-argument', 'Invalid animal id.');
  }

  const adoptions = db.collection('adoptions');
  const [legacy, byRecord] = await Promise.all([
    animalId ? adoptions.where('personal.animalId', '==', animalId).get() : null,
    animalRecordId ? adoptions.where('personal.animalRecordId', '==', animalRecordId).get() : null,
  ]);

  return {blocked: (legacy !== null && blocks(legacy)) || (byRecord !== null && blocks(byRecord))};
});
