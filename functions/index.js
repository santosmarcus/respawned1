const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

exports.getOrCreateRescueSession = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const {tagId, location} = request.data || {};
  if (!tagId) {
    throw new HttpsError('invalid-argument', 'tagId is required.');
  }

  const tagRef = db.collection('collarTags').doc(tagId);
  const tagSnap = await tagRef.get();
  if (!tagSnap.exists) {
    throw new HttpsError('not-found', 'This tag is not registered.');
  }
  const tagData = tagSnap.data();

  const lat = location && typeof location.lat === 'number' ? location.lat : null;
  const lng = location && typeof location.lng === 'number' ? location.lng : null;
  const address = location && typeof location.address === 'string' ? location.address : null;

  // Reuse the existing session if this tag already has one that's still
  // active, instead of spawning a new one on every re-scan of an
  // already-lost pet.
  const existingSessionId = tagData.activeRescueSessionId;
  if (existingSessionId) {
    const existingRef = db.collection('rescueSessions').doc(existingSessionId);
    const existingSnap = await existingRef.get();
    if (existingSnap.exists && existingSnap.data().status !== 'resolved') {
      // Keep the location fresh on every re-scan — a later scan (better
      // GPS fix, a successful reverse-geocode where an earlier one failed,
      // or the animal having moved somewhere new) shouldn't be stuck
      // showing whatever the very first scan happened to save.
      if (lat !== null && lng !== null) {
        await existingRef.set(
          {
            lat,
            lng,
            ...(address !== null ? {address} : {}),
            lastScannedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        const tagRescanUpdate = {
          lastSeenLat: lat,
          lastSeenLng: lng,
          ...(address !== null ? {lastSeenAddress: address} : {}),
        };
        await tagRef.set(tagRescanUpdate, {merge: true});
        const rescanOwnerId = tagData.ownerId;
        if (rescanOwnerId) {
          await db
            .collection('users')
            .doc(rescanOwnerId)
            .collection('collarTags')
            .doc(tagId)
            .set(tagRescanUpdate, {merge: true});
        }
      }

      return {sessionId: existingSessionId};
    }
  }

  const sessionRef = db.collection('rescueSessions').doc();
  await sessionRef.set({
    tagId,
    status: 'active',
    chatEnabledByOwner: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(lat !== null ? {lat} : {}),
    ...(lng !== null ? {lng} : {}),
    ...(address !== null ? {address} : {}),
  });

  const tagUpdate = {
    status: 'lost',
    activeRescueSessionId: sessionRef.id,
    lostAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(lat !== null ? {lastSeenLat: lat} : {}),
    ...(lng !== null ? {lastSeenLng: lng} : {}),
    ...(address !== null ? {lastSeenAddress: address} : {}),
  };

  await tagRef.set(tagUpdate, {merge: true});

  const ownerId = tagData.ownerId;
  if (ownerId) {
    await db
      .collection('users')
      .doc(ownerId)
      .collection('collarTags')
      .doc(tagId)
      .set(tagUpdate, {merge: true});
  }

  return {sessionId: sessionRef.id};
});
const UNCONFIRMED_THRESHOLD_MINUTES = 15;
const NUDGE_COOLDOWN_MINUTES = 20;
const RADIUS_KM = 5;

const CASES_SCAN_LIMIT = 300;

// Statuses that mean a case is no longer active and shouldn't trigger
// nearby-user push notifications. Keep in sync with the client-side
// `_kDismissedCaseStatuses` in nearby_report.dart.
const DISMISSED_STATUSES = ['dismissed', 'cancelled', 'withdrawn', 'rejected'];

const PICKED_UP_STATUSES = [
  'treatment',
  'dropoff',
  'searching_clinic',
  'in_transit_shelter',
  'completed',
  'ended',
];

function haversineKm(lat1, lng1, lat2, lng2) {
  const earthRadiusKm = 6371.0;
  const deg2rad = (deg) => (deg * Math.PI) / 180.0;
  const dLat = deg2rad(lat2 - lat1);
  const dLng = deg2rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function isFinalStatus(status) {
  const s = (status || '').toLowerCase();
  return s === 'closed' || s.includes('completed') || s.includes('ended');
}

function hasBeenPickedUp(c) {
  const s = (c.status || '').toLowerCase();
  return PICKED_UP_STATUSES.includes(s);
}

function hasReceivedResponse(c, communityReportsCount) {
  const status = (c.status || '').toLowerCase();
  if (status && status !== 'pending' && status !== 'open') return true;
  if (c.riderId || c.assignedVolunteerId) return true;
  if (communityReportsCount > 0) return true;
  if (hasBeenPickedUp(c)) return true;
  return false;
}

async function notifyUser({uid, title, body, data}) {
  if (!uid) return false;
  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists) return false;
  const token = userDoc.data().fcmToken;
  if (!token) return false;

  await admin.messaging().send({
    token,
    notification: {title, body},
    data,
  });
  return true;
}

async function notifyNearbyUsers({lat, lng, excludeUid, title, body, data}) {
  const latDeltaDeg = RADIUS_KM / 111; // ~111km per degree of latitude
  const lngDeltaDeg = RADIUS_KM / (111 * Math.cos((lat * Math.PI) / 180));

  const usersSnap = await db
    .collection('users')
    .where('lastLat', '>=', lat - latDeltaDeg)
    .where('lastLat', '<=', lat + latDeltaDeg)
    .get();

  const tokens = [];
  usersSnap.forEach((userDoc) => {
    if (userDoc.id === excludeUid) return;
    const u = userDoc.data();
    if (!u.fcmToken || u.lastLng == null) return;
    if (Math.abs(u.lastLng - lng) > lngDeltaDeg) return;
    if (haversineKm(lat, lng, u.lastLat, u.lastLng) <= RADIUS_KM) {
      tokens.push(u.fcmToken);
    }
  });

  if (tokens.length === 0) return 0;

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {title, body},
    data,
  });

  return tokens.length;
}

// 1. Immediate alert the moment a new case is reported.
exports.notifyNewCaseReported = onDocumentCreated(
  'cases/{caseId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const c = snap.data();

    if (c.lat == null || c.lng == null) return;

    const status = (c.status || '').toLowerCase();
    if (DISMISSED_STATUSES.includes(status)) return;

    await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      title: 'New rescue report near you',
      body: 'A rescue report just came in nearby — tap to see if you can help.',
      data: {
        type: 'new_case_nearby',
        caseId: event.params.caseId,
      },
    });
  },
);

exports.notifyUnconfirmedReports = onSchedule('every 5 minutes', async () => {
  const now = admin.firestore.Timestamp.now();

  const casesSnap = await db
    .collection('cases')
    .orderBy('createdAt', 'desc')
    .limit(CASES_SCAN_LIMIT)
    .get();

  for (const caseDoc of casesSnap.docs) {
    const c = caseDoc.data();
    const status = (c.status || '').toLowerCase();

    if (DISMISSED_STATUSES.includes(status)) continue;
    if (isFinalStatus(status)) continue;
    if (c.lat == null || c.lng == null) continue;

    const reportsSnap = await caseDoc.ref
      .collection('communityReports')
      .orderBy('timestamp', 'desc')
      .limit(1)
      .get();


    if (hasReceivedResponse(c, reportsSnap.size)) continue;

    const lastNudge = c.lastNudgeSentAt;

    if (!lastNudge) {

      const createdMs = c.createdAt ? c.createdAt.toMillis() : 0;
      const minutesSinceCreated = (now.toMillis() - createdMs) / 60000;
      if (minutesSinceCreated < UNCONFIRMED_THRESHOLD_MINUTES) continue;
    } else {

      const minutesSinceLastNudge =
        (now.toMillis() - lastNudge.toMillis()) / 60000;
      if (minutesSinceLastNudge < NUDGE_COOLDOWN_MINUTES) continue;
    }

    const notifiedCount = await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      title: 'A nearby report still needs a responder',
      body: 'This report is still awaiting a pet transporter — is the animal present or not? Tap to confirm.',
      data: {
        type: 'community_nudge',
        caseId: caseDoc.id,
      },
    });

    if (notifiedCount === 0) continue;

    await caseDoc.ref.update({
      lastNudgeSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

const REPORTER_NOTIFY_STATUSES = {
  unable_to_locate: {
    title: 'Update on your rescue report',
    body: "The transporter couldn't find the animal at the location you "
      + 'reported. Can you confirm or update the location?',
  },
  awaiting_reporter_response: {
    title: 'Update on your rescue report',
    body: 'The transporter could not find the animal and could not reach '
      + 'you. Please respond with an updated location if you can.',
  },
  pickup_attempt_unsuccessful: {
    title: 'We tried to reach you',
    body: 'A pickup attempt was made for your rescue report, but we '
      + "couldn't reach you. Please respond so we can reschedule.",
  },
  needs_specialized_assistance: {
    title: 'Update on your rescue report',
    body: 'Pickup was postponed because the animal could not be safely '
      + 'handled. Our team is arranging specialized assistance.',
  },
};


exports.notifyOnEndReasonStatus = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after || before.status === after.status) return;

    const config = REPORTER_NOTIFY_STATUSES[after.status];
    if (!config) return;

    await notifyUser({
      uid: after.reporterId,
      title: config.title,
      body: config.body,
      data: {
        type: 'case_status_update',
        caseId: event.params.caseId,
        status: after.status,
      },
    });

    if (after.status === 'needs_specialized_assistance') {
      await db.collection('adminAlerts').add({
        type: 'needs_specialized_assistance',
        caseId: event.params.caseId,
        reason: after.endReason || null,
        notes: after.endReasonNotes || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      });
    }
  },
);


const REPORTER_RESPONSE_TIMEOUT_HOURS = 48;

exports.expireStaleReporterResponses = onSchedule('every 60 minutes', async () => {
  const cutoffMs = Date.now() - REPORTER_RESPONSE_TIMEOUT_HOURS * 60 * 60 * 1000;

  const casesSnap = await db
    .collection('cases')
    .where('status', 'in', [
      'unable_to_locate',
      'awaiting_reporter_response',
      'pickup_attempt_unsuccessful',
    ])
    .get();

  for (const caseDoc of casesSnap.docs) {
    const c = caseDoc.data();
    const awaitingSince = c.awaitingReporterSince;
    if (!awaitingSince) continue;
    if (awaitingSince.toMillis() > cutoffMs) continue;

    await caseDoc.ref.update({
      status: 'cancelled',
      statusHistory: admin.firestore.FieldValue.arrayUnion([
        {
          status: `Case automatically closed after ${REPORTER_RESPONSE_TIMEOUT_HOURS}h with no reporter response.`,
          timestamp: admin.firestore.Timestamp.now(),
        },
      ]),
      awaitingReporterSince: admin.firestore.FieldValue.delete(),
    });
  }
});