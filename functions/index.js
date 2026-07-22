

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
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