// Adoption checks that need to read other people's applications.
//
// firestore.rules lets a user read only their own adoption applications
// (plus the owning organization's staff). Checking whether an animal can
// still take a new application, and closing everyone else's applications
// once it is reserved or adopted, both need every applicant's application,
// so they run here with admin access.
//
// Policy (pending the organization's confirmation): several people may
// apply for the same animal at once and staff choose between them. The
// reservation is the lock — once staff reserve the animal for one
// applicant, or release it to an adopter, nobody else can apply and the
// other open applications are closed.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();

// Raw application statuses that are still being worked on (canonical and
// legacy values, see AdoptionStatus.queryValues in adoption_application.dart).
const OPEN_STATUSES = new Set([
  'pending', 'pending_appointment',
  'interview', 'under_review',
  'approved', 'appointment_confirmed',
]);
// An adoption that went through (it may have a return in progress).
const ADOPTED_STATUSES = new Set(['adopted', 'completed', 'return_requested', 'return_approved']);

// The adoption ended in a return: the animal came back and went to Intake.
function returnedToIntake(d) {
  const r = d.returnRequest;
  return !!r && r.status === 'intake';
}

/// Why the animal can't take a new application from [uid], or null when it
/// can. Mirrors availabilityFromAnimalState in
/// lib/core/repos/adoption_application_repository.dart, which the Adopt
/// button uses, so the button and Submit agree. Other people's open
/// applications never block.
function animalBlockReason(a, uid) {
  if (!a) return 'unavailable';
  if (a.archived === true || a.publicProfileHidden === true) return 'unavailable';
  if (a.status === 'deceased' || a.adoptionStatus === 'deceased') return 'unavailable';
  switch (a.adoptionStatus) {
    case 'adoptable':
      return null;
    case 'reserved':
      return a.reservedForUserId === uid ? null : 'reserved';
    case 'adopted':
      return 'adopted';
    default:
      return 'unavailable'; // not_ready or unknown
  }
}

/// Applications saved before animal records existed only carry the legacy
/// personal.animalId, so there is no animal doc to read: someone else's
/// reservation or completed (not returned) adoption blocks.
function legacyBlockReason(snap, uid) {
  for (const doc of snap.docs) {
    const d = doc.data();
    const status = String(d.status || '');
    if ((d.personal || {}).adopterId === uid) continue;
    if (ADOPTED_STATUSES.has(status) && !returnedToIntake(d)) return 'adopted';
    if (OPEN_STATUSES.has(status) && d.reservedAt) return 'reserved';
  }
  return null;
}

/// { animalId?: string, animalRecordId?: string }
///   -> { blocked: boolean, reason: 'reserved' | 'adopted' | 'unavailable' | null }
/// animalId is the legacy personal.animalId key; animalRecordId is the real
/// animals/{id} document id. Either may be empty.
exports.hasBlockingAdoption = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const data = request.data || {};
  const animalId = typeof data.animalId === 'string' ? data.animalId.trim() : '';
  const animalRecordId = typeof data.animalRecordId === 'string' ? data.animalRecordId.trim() : '';
  if (!animalId && !animalRecordId) {
    throw new HttpsError('invalid-argument', 'animalId or animalRecordId is required.');
  }
  if (animalId.length > 200 || animalRecordId.length > 200 || animalRecordId.includes('/')) {
    throw new HttpsError('invalid-argument', 'Invalid animal id.');
  }

  let reason;
  if (animalRecordId) {
    const animal = await db.collection('animals').doc(animalRecordId).get();
    reason = animalBlockReason(animal.exists ? animal.data() : null, uid);
  } else {
    const legacy = await db.collection('adoptions').where('personal.animalId', '==', animalId).get();
    reason = legacyBlockReason(legacy, uid);
  }
  return {blocked: reason !== null, reason};
});

// ---- Close the other applications once the animal is taken ---------------

const CLOSED_REASON = 'Animal no longer available';

// The application the animal was just reserved for or adopted through, or
// null when this update didn't take the animal.
function takenBy(before, after) {
  if (after.adoptionStatus === 'reserved' && before.adoptionStatus !== 'reserved') {
    return {event: 'reserved', applicationId: after.reservedApplicationId || null};
  }
  if (after.adoptionStatus === 'adopted' && before.adoptionStatus !== 'adopted') {
    return {event: 'adopted', applicationId: after.adoptedApplicationId || null};
  }
  return null;
}

async function pushTo(uid, {title, body, data}) {
  if (!uid) return;
  try {
    const user = await db.collection('users').doc(uid).get();
    const token = user.exists ? user.get('fcmToken') : null;
    if (!token) return;
    await admin.messaging().send({token, notification: {title, body}, data});
  } catch (e) {
    console.warn('[closeOtherAdoptionApplications] push failed', uid, e.message);
  }
}

// When staff reserve an animal for one applicant, or release it as
// adopted, every other open application for it is closed as rejected with
// the reason "Animal no longer available", the applicant is told (push and
// in-app notification), and each closure is written to auditLogs.
// Unreserving does not reopen anything; people can apply again.
exports.closeOtherAdoptionApplications = onDocumentUpdated('animals/{animalId}', async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  const taken = takenBy(before, after);
  if (!taken) return;

  const {animalId} = event.params;
  const animalName = after.name || 'The animal';
  const apps = await db.collection('adoptions').where('personal.animalRecordId', '==', animalId).get();

  for (const doc of apps.docs) {
    if (doc.id === taken.applicationId) continue;
    const d = doc.data();
    if (!OPEN_STATUSES.has(String(d.status || ''))) continue;

    const now = admin.firestore.Timestamp.now();
    const closed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || !OPEN_STATUSES.has(String(fresh.get('status') || ''))) return false;
      tx.update(doc.ref, {
        status: 'rejected',
        rejectionReasons: [CLOSED_REASON],
        rejectedAt: now,
        rejectedBy: 'System',
        closedReason: 'animal_unavailable',
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: `Application closed: ${CLOSED_REASON} (${taken.event === 'adopted' ? 'adopted by another applicant' : 'reserved for another applicant'}).`,
          timestamp: now,
        }),
      });
      return true;
    });
    if (!closed) continue;

    const adopterId = (d.personal || {}).adopterId || null;
    const title = 'Adoption application closed';
    const body = `${animalName} is no longer available for adoption, so your application was closed. `
      + 'Thank you for applying. You are welcome to apply for another animal.';
    if (adopterId) {
      try {
        await db.collection('users').doc(adopterId).collection('notifications').add({
          title,
          message: body,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          type: 'adoption_application_closed',
          adoptionId: doc.id,
        });
      } catch (e) {
        console.warn('[closeOtherAdoptionApplications] in-app notification failed', adopterId, e.message);
      }
      await pushTo(adopterId, {
        title,
        body,
        data: {type: 'adoption_application_closed', adoptionId: doc.id},
      });
    }

    try {
      await db.collection('auditLogs').add({
        category: 'adoptions',
        action: 'Application closed — animal no longer available',
        actorName: 'System',
        ...(d.organizationId ? {organizationId: d.organizationId} : {}),
        targetType: 'AdoptionApplication',
        targetId: doc.id,
        oldValues: {status: d.status || null},
        newValues: {status: 'rejected', reasons: [CLOSED_REASON]},
        metadata: {animalId, trigger: taken.event, keptApplicationId: taken.applicationId},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[closeOtherAdoptionApplications] audit log write failed', doc.id, e);
    }
  }
});
