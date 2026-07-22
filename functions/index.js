const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DISMISSED_STATUSES = ['dismissed', 'cancelled', 'withdrawn', 'rejected'];
const UNCONFIRMED_THRESHOLD_MINUTES = 15;
const NUDGE_COOLDOWN_MINUTES = 20;
const RADIUS_KM = 5;

const CASES_SCAN_LIMIT = 300;

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


// Lost/found chat for scanners who don't have the app

exports.getOrCreateRescueSession = onCall(async (request) => {
  const tagId = request.data && request.data.tagId;
  if (!tagId || typeof tagId !== 'string') {
    throw new HttpsError('invalid-argument', 'tagId is required.');
  }

  const tagRef = db.collection('collarTags').doc(tagId);
  const tagSnap = await tagRef.get();
  if (!tagSnap.exists) {
    throw new HttpsError('not-found', "This pet ID tag doesn't exist or was removed.");
  }
  const tag = tagSnap.data();
  if (!tag.qrEnabled) {
    throw new HttpsError(
      'failed-precondition',
      "This tag's QR code hasn't been approved for public viewing yet.",
    );
  }

  if (tag.activeRescueSessionId) {
    const existingSnap = await db
      .collection('rescueSessions')
      .doc(tag.activeRescueSessionId)
      .get();
    if (existingSnap.exists && existingSnap.data().status === 'active') {
      return {sessionId: existingSnap.id};
    }

  }

  const loc = request.data && request.data.location;
  const sessionRef = db.collection('rescueSessions').doc();
  await sessionRef.set({
    tagId,
    ownerId: tag.ownerId || null,
    finderId: request.auth ? request.auth.uid : null,
    status: 'active',
    chatEnabledByOwner: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lat: loc && typeof loc.lat === 'number' ? loc.lat : null,
    lng: loc && typeof loc.lng === 'number' ? loc.lng : null,
    address: loc && typeof loc.address === 'string' && loc.address.trim() !== ''
      ? loc.address.trim()
      : null,
  });
  await tagRef.set({activeRescueSessionId: sessionRef.id}, {merge: true});

  return {sessionId: sessionRef.id};
});

exports.sendRescueSessionMessage = onCall(async (request) => {
  const {sessionId, sender, text} = request.data || {};
  if (!sessionId || typeof sessionId !== 'string') {
    throw new HttpsError('invalid-argument', 'sessionId is required.');
  }
  const trimmed = (text || '').toString().trim();
  if (!trimmed) {
    throw new HttpsError('invalid-argument', 'A non-empty message is required.');
  }

  const sessionRef = db.collection('rescueSessions').doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('not-found', 'This rescue session no longer exists.');
  }

  await sessionRef.collection('messages').add({
    sender: sender === 'owner' ? 'owner' : 'finder',
    text: trimmed,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {ok: true};
});