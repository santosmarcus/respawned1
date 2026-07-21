/**
 * Community-report "check in?" nudge.
 *
 * Every 10 minutes, looks at every open report where the animal hasn't
 * been picked up yet — regardless of urgency — and, once it's gone 15
 * minutes without any community confirmation, pushes a notification to
 * users known to be nearby asking them to confirm whether the animal is
 * still present. Re-nudges every 20 minutes (subject to the cooldown
 * below) for as long as the report is still awaiting pickup, and stops
 * for good the moment the assigned transporter has picked up the animal
 * (case status moves into/past the 'treatment' stage).
 *
 * SETUP REQUIRED before this will run:
 *   1. `firebase init functions` in the project root if you don't already
 *      have a `functions/` directory wired into firebase.json.
 *   2. `npm install firebase-admin firebase-functions` inside `functions/`.
 *   3. Scheduled functions require the Blaze (pay-as-you-go) plan — the
 *      Spark plan mentioned in the proposal doesn't support Cloud
 *      Scheduler, which this relies on.
 *   4. Deploy with `firebase deploy --only functions`.
 *   5. Firestore needs a single-field index on `users.lastLat` (usually
 *      created automatically on first query failure — check the Firestore
 *      console for an index-creation prompt/link if this errors out).
 *
 * Client side, this depends on two things already wired up in the Flutter
 * app: `users/{uid}.lastLat/lastLng` (written from explore_reports_map.dart
 * whenever the map gets the user's location) and `users/{uid}.fcmToken`
 * (written from push_token_service.dart on login).
 */

const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DISMISSED_STATUSES = ['dismissed', 'cancelled', 'withdrawn', 'rejected'];
const UNCONFIRMED_THRESHOLD_MINUTES = 15;
const NUDGE_COOLDOWN_MINUTES = 20;
const RADIUS_KM = 5;
// Bounds how many cases we scan per run — cases are checked most-recent
// first, so this only matters for orgs with a very large volume of
// simultaneously open reports.
const CASES_SCAN_LIMIT = 300;

// Case `status` values (see transit_progress_page.dart) from the moment
// the animal is physically picked up onward — 'accepted' (rider assigned
// but not yet there) and 'ongoing'/'arrived' (en route / on scene but not
// yet picked up) are deliberately NOT in this list, since the report is
// still effectively awaiting pickup at those stages.
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

exports.notifyUnconfirmedReports = onSchedule('every 10 minutes', async () => {
  const now = admin.firestore.Timestamp.now();

  const casesSnap = await db
    .collection('cases')
    .orderBy('serverCreatedAt', 'desc')
    .limit(CASES_SCAN_LIMIT)
    .get();

  for (const caseDoc of casesSnap.docs) {
    const c = caseDoc.data();
    const status = (c.status || '').toLowerCase();

    if (DISMISSED_STATUSES.includes(status)) continue;
    if (isFinalStatus(status)) continue;
    if (c.lat == null || c.lng == null) continue;

    // Stop nudging once the animal has actually been picked up
    if (hasBeenPickedUp(c)) continue;


    const lastNudge = c.lastNudgeSentAt;
    if (
      lastNudge &&
      (now.toMillis() - lastNudge.toMillis()) / 60000 < NUDGE_COOLDOWN_MINUTES
    ) {
      continue;
    }


    let lastActivityMs = c.createdAt ? c.createdAt.toMillis() : 0;
    const reportsSnap = await caseDoc.ref
      .collection('communityReports')
      .orderBy('timestamp', 'desc')
      .limit(1)
      .get();
    if (!reportsSnap.empty) {
      const r = reportsSnap.docs[0].data();
      if (r.timestamp) lastActivityMs = Math.max(lastActivityMs, r.timestamp.toMillis());
    }

    const minutesSinceActivity = (now.toMillis() - lastActivityMs) / 60000;
    if (minutesSinceActivity < UNCONFIRMED_THRESHOLD_MINUTES) continue;

    const latDeltaDeg = RADIUS_KM / 111; // ~111km per degree of latitude
    const lngDeltaDeg = RADIUS_KM / (111 * Math.cos((c.lat * Math.PI) / 180));

    const usersSnap = await db
      .collection('users')
      .where('lastLat', '>=', c.lat - latDeltaDeg)
      .where('lastLat', '<=', c.lat + latDeltaDeg)
      .get();

    const tokens = [];
    usersSnap.forEach((userDoc) => {
      if (userDoc.id === c.reporterId) return; // skip the original reporter
      const u = userDoc.data();
      if (!u.fcmToken || u.lastLng == null) return;
      if (Math.abs(u.lastLng - c.lng) > lngDeltaDeg) return;
      if (haversineKm(c.lat, c.lng, u.lastLat, u.lastLng) <= RADIUS_KM) {
        tokens.push(u.fcmToken);
      }
    });

    if (tokens.length === 0) continue;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'A nearby report still needs a responder',
        body: 'This report is still awaiting a pet transporter — is the animal present or not? Tap to confirm.',
      },
      data: {
        type: 'community_nudge',
        caseId: caseDoc.id,
      },
    });

    await caseDoc.ref.update({
      lastNudgeSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});