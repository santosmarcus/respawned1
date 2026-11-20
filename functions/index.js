const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const {orgMemberUids, requireOrgPermission} = require('./org_access');
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

  // Only a pet its owner has marked lost gets a rescue session. Previously
  // any scan created one AND flipped the tag to status 'lost' below, so
  // scanning a pet that wasn't lost marked it lost and opened the lost-pet
  // chat.
  if (tagData.status !== 'lost') {
    throw new HttpsError('failed-precondition', 'This pet is not marked as lost.');
  }

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

      try {
        await notifyTagScan({
          tagId,
          tagData,
          sessionId: existingSessionId,
          scannerUid: request.auth.uid,
          lat,
          lng,
          address,
          isNewSession: false,
        });
      } catch (e) {
        console.warn('notifyTagScan failed', e.message);
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

  try {
    await notifyTagScan({
      tagId,
      tagData,
      sessionId: sessionRef.id,
      scannerUid: request.auth.uid,
      lat,
      lng,
      address,
      isNewSession: true,
    });
  } catch (e) {
    console.warn('notifyTagScan failed', e.message);
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

// ---- Geofence notifications -------------------------------------------
//
// A geofence here is a circle of `radiusKm` around a case/alert's lat/lng.
// Every user whose last known location (users/{uid}.lastLat/lastLng) is
// inside that circle gets the push. Responders (volunteers, transporters,
// organizations) get a wider geofence than the general public so cases
// reach the people who can act on them first.
// Pet transporters are NOT nearby-alert recipients: they only get pushes for
// their own assignments, rescue-location updates and clinic changes (see
// notifyTransporterAssignment / notifyTransporterCaseChanges below).
const TRANSPORTER_ROLE = 'pet_transporter';
const RESPONDER_ROLES = ['rescue_volunteer', 'organization'];
const RESPONDER_RADIUS_KM = 10;
// Users can pick their own alert radius (location_sharing_page.dart); it
// is clamped to this so the bounding-box query stays small.
const MAX_USER_ALERT_RADIUS_KM = 10;
const FCM_MULTICAST_LIMIT = 500;

// Notification categories a user can mute in Location Sharing settings.
// Keep in sync with GeofencePrefs.categories in geofence_prefs.dart.
const NOTIFY_CATEGORY = {
  newCase: 'new_case',
  caseUpdate: 'case_update',
  petAlert: 'pet_alert',
  tagScan: 'tag_scan',
};

// Effective alert radius for one user: their own setting if they chose
// one, otherwise the radius of the geofence being checked.
function userAlertRadiusKm(u, defaultKm) {
  const prefs = u.geofencePrefs || {};
  const r = Number(prefs.radiusKm);
  if (!Number.isFinite(r) || r <= 0) return defaultKm;
  return Math.min(r, MAX_USER_ALERT_RADIUS_KM);
}

function userWantsCategory(u, category) {
  const prefs = u.geofencePrefs || {};
  if (prefs.enabled === false) return false;
  const muted = Array.isArray(prefs.mutedCategories) ? prefs.mutedCategories : [];
  return !category || !muted.includes(category);
}

// FCM `data` values must all be strings.
function toFcmData(data) {
  const out = {};
  Object.entries(data || {}).forEach(([k, v]) => {
    if (v !== null && v !== undefined) out[k] = String(v);
  });
  return out;
}

// notifyUser that never throws (a stale token shouldn't stop the
// geofence notifications that follow it).
async function safeNotifyUser(args) {
  try {
    return await notifyUser({...args, data: toFcmData(args.data)});
  } catch (e) {
    console.warn('notifyUser failed', args.uid, e.message);
    return false;
  }
}

async function notifyNearbyUsers({
  lat,
  lng,
  excludeUid,
  excludeUids = [],
  roles = null, // only these roles (null = any role)
  excludeRoles = null, // never these roles
  radiusKm = RADIUS_KM,
  category = null, // one of NOTIFY_CATEGORY; users can mute categories
  title,
  body,
  data,
}) {
  const skip = new Set([excludeUid, ...excludeUids].filter(Boolean));
  // Search wide enough for users who picked a bigger personal radius.
  const searchKm = Math.max(radiusKm, MAX_USER_ALERT_RADIUS_KM);
  const latDeltaDeg = searchKm / 111; // ~111km per degree of latitude
  const lngDeltaDeg = searchKm / (111 * Math.cos((lat * Math.PI) / 180));

  const usersSnap = await db
    .collection('users')
    .where('lastLat', '>=', lat - latDeltaDeg)
    .where('lastLat', '<=', lat + latDeltaDeg)
    .get();

  const tokens = new Set();
  usersSnap.forEach((userDoc) => {
    if (skip.has(userDoc.id)) return;
    const u = userDoc.data();
    if (!u.fcmToken || u.lastLng == null) return;
    const role = u.role || '';
    if (role === TRANSPORTER_ROLE) return;
    if (roles && !roles.includes(role)) return;
    if (excludeRoles && excludeRoles.includes(role)) return;
    if (!userWantsCategory(u, category)) return;
    if (Math.abs(u.lastLng - lng) > lngDeltaDeg) return;
    if (haversineKm(lat, lng, u.lastLat, u.lastLng) <= userAlertRadiusKm(u, radiusKm)) {
      tokens.add(u.fcmToken);
    }
  });

  if (tokens.size === 0) return 0;

  const list = [...tokens];
  for (let i = 0; i < list.length; i += FCM_MULTICAST_LIMIT) {
    await admin.messaging().sendEachForMulticast({
      tokens: list.slice(i, i + FCM_MULTICAST_LIMIT),
      notification: {title, body},
      data: toFcmData(data),
    });
  }

  return list.length;
}

// ---- Organization coverage geofences ------------------------------------
//
// Each organization's serviceAreas[] entry carries {lat, lng, radiusKm}
// (from the Places viewport, see LocalityResult / ServiceArea). A new
// case is tagged with every approved organization whose coverage
// contains it, and that organization's staff are notified directly.
// Cases outside every coverage area are flagged for admins (they can be
// referred to the LGU from the case page).

function orgCoversPoint(org, lat, lng) {
  const areas = Array.isArray(org.serviceAreas) ? org.serviceAreas : [];
  return areas.some((a) =>
    typeof a.lat === 'number' &&
    typeof a.lng === 'number' &&
    typeof a.radiusKm === 'number' &&
    haversineKm(lat, lng, a.lat, a.lng) <= a.radiusKm);
}

async function assignCaseToServiceAreas({caseRef, caseId, c, isCritical}) {
  const orgsSnap = await db
    .collection('organizations')
    .where('verificationStatus', '==', 'approved')
    .get();

  const matched = orgsSnap.docs
    .filter((d) => orgCoversPoint(d.data(), c.lat, c.lng))
    .map((d) => d.id);

  await caseRef.update({
    areaOrgIds: matched,
    outsideServiceArea: matched.length === 0,
  });

  if (matched.length === 0) {
    await db.collection('adminAlerts').add({
      type: 'outside_service_area',
      caseId,
      lat: c.lat,
      lng: c.lng,
      address: c.address || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
    });
    return;
  }

  // Staff of the matched organizations who handle rescues.
  const uids = new Set();
  for (const orgId of matched) {
    for (const uid of await orgMemberUids(db, orgId, {anyOf: ['rescue']})) uids.add(uid);
  }
  uids.delete(c.reporterId);
  const tokens = new Set();
  const refs = [...uids].map((uid) => db.collection('users').doc(uid));
  for (let i = 0; i < refs.length; i += 100) {
    const docs = await db.getAll(...refs.slice(i, i + 100));
    docs.forEach((u) => {
      const d = u.exists ? u.data() : null;
      if (!d || !d.fcmToken || !userWantsCategory(d, NOTIFY_CATEGORY.newCase)) return;
      tokens.add(d.fcmToken);
    });
  }
  if (tokens.size === 0) return;

  const list = [...tokens];
  for (let i = 0; i < list.length; i += FCM_MULTICAST_LIMIT) {
    await admin.messaging().sendEachForMulticast({
      tokens: list.slice(i, i + FCM_MULTICAST_LIMIT),
      notification: {
        title: isCritical ? 'URGENT: Critical case in your service area' : 'New case in your service area',
        body: 'A rescue report was filed inside your organization\'s coverage area. Tap to review it.',
      },
      data: toFcmData({type: 'new_case_service_area', caseId}),
    });
  }
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

    const caseId = event.params.caseId;
    const isCritical = c.urgency === 'Critical';

    // Which organizations' coverage geofences contain this case?
    await assignCaseToServiceAreas({caseRef: snap.ref, caseId, c, isCritical});

    // Responders: wider geofence + "view and accept" wording.
    await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      roles: RESPONDER_ROLES,
      radiusKm: RESPONDER_RADIUS_KM,
      category: NOTIFY_CATEGORY.newCase,
      title: isCritical ? 'URGENT: Critical rescue near you' : 'Rescue needed near you',
      body: 'A new rescue report is inside your area. Tap to view and accept the case.',
      data: {
        type: 'new_case_nearby_responder',
        caseId,
      },
    });

    // General public inside the standard geofence (responders excluded
    // so nobody gets two pushes for the same case).
    await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      excludeRoles: [...RESPONDER_ROLES, TRANSPORTER_ROLE],
      category: NOTIFY_CATEGORY.newCase,
      title: 'New rescue report near you',
      body: 'A rescue report just came in nearby — tap to see if you can help.',
      data: {
        type: 'new_case_nearby',
        caseId,
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
      category: NOTIFY_CATEGORY.newCase,
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


// ---- Case geofence events (rescue progress + rescue completed) ---------
//
// When a case moves to one of these statuses, the reporter is told
// directly, and (where `nearby` is set) everyone inside the case's
// geofence is told too — e.g. "a rescue near you was completed".
const CASE_COMPLETED_MESSAGE = {
  reporter: {
    title: 'Rescue completed',
    body: 'The rescue for the animal you reported has been completed. Thank you for reporting!',
  },
  nearby: {
    title: 'A rescue near you was completed',
    body: 'A rescue case in your area was just completed by a volunteer or organization. Tap to see the outcome.',
  },
};

const CASE_GEOFENCE_EVENTS = {
  // Set automatically by the transporter's pickup geofence
  // (transit_progress_page.dart) or by the "Arrived" button.
  arrived: {
    reporter: {
      title: 'The transporter has arrived',
      body: 'The pet transporter has reached the location you reported.',
    },
  },
  treatment: {
    reporter: {
      title: 'The animal has been picked up',
      body: 'A transporter has rescued the animal you reported and is taking it for treatment.',
    },
    nearby: {
      title: 'An animal near you was rescued',
      body: 'A reported animal in your area has been picked up — no need to report it again.',
    },
  },
  dropoff: {
    reporter: {
      title: 'Arrived for treatment',
      body: 'The animal you reported has been brought to a clinic for treatment.',
    },
  },
  in_transit_shelter: {
    reporter: {
      title: 'On the way to the shelter',
      body: 'The animal you reported is now being transported to the shelter.',
    },
  },
  completed: CASE_COMPLETED_MESSAGE,
  closed: CASE_COMPLETED_MESSAGE,
};

// completed and closed share one key so a case that goes
// completed -> closed only announces its completion once.
function geofenceEventKey(status) {
  return status === 'completed' || status === 'closed' ? 'final' : status;
}

exports.notifyCaseGeofenceEvents = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after || before.status === after.status) return;

    const status = (after.status || '').toLowerCase();
    const config = CASE_GEOFENCE_EVENTS[status];
    if (!config) return;

    const key = geofenceEventKey(status);
    const alreadySent = after.geofenceNotified || {};
    if (alreadySent[key]) return;

    const caseId = event.params.caseId;

    if (config.reporter && after.reporterId) {
      await safeNotifyUser({
        uid: after.reporterId,
        title: config.reporter.title,
        body: config.reporter.body,
        data: {type: 'case_status_update', caseId, status},
      });
    }

    if (config.nearby && after.lat != null && after.lng != null) {
      await notifyNearbyUsers({
        lat: after.lat,
        lng: after.lng,
        excludeUids: [after.reporterId, after.riderId, after.assignedVolunteerId],
        category: NOTIFY_CATEGORY.caseUpdate,
        title: config.nearby.title,
        body: config.nearby.body,
        data: {type: 'case_geofence_event', caseId, status},
      });
    }

    // Status is unchanged by this write, so this trigger won't loop.
    await event.data.after.ref.update({
      [`geofenceNotified.${key}`]: admin.firestore.FieldValue.serverTimestamp(),
    });
  },
);

// ---- Lost / found pet alerts --------------------------------------------
//
// New lost-pet and found-animal alerts notify everyone inside the alert's
// geofence. A found report with several animals creates several petAlerts
// docs; only the first one has groupId == null at creation, so the group
// produces a single push.
exports.notifyPetAlertNearby = onDocumentCreated(
  'petAlerts/{alertId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const a = snap.data();

    if (a.lat == null || a.lng == null) return;
    if (a.groupId) return; // not the first doc of its group
    // A found report linked to a rescue case is already announced by
    // notifyNewCaseReported.
    if (a.linkedCaseId) return;

    const species = (a.species || 'pet').toString().toLowerCase();
    let title;
    let body;
    if (a.type === 'lost') {
      title = 'Lost pet alert near you';
      body = a.petName
        ? `${a.petName} (${species}) was reported lost nearby. Keep an eye out!`
        : `A lost ${species} was reported nearby. Keep an eye out!`;
    } else if (a.type === 'found') {
      title = 'Found animal near you';
      body = `Someone found a ${species} nearby — could it be yours?`;
    } else {
      return;
    }

    await notifyNearbyUsers({
      lat: a.lat,
      lng: a.lng,
      excludeUid: a.reporterId,
      category: NOTIFY_CATEGORY.petAlert,
      title,
      body,
      data: {
        type: 'pet_alert_nearby',
        alertId: event.params.alertId,
        alertType: a.type,
      },
    });
  },
);

// Collar tag scans: the owner hears about every scan of their lost pet;
// people nearby are alerted only when a scan opens a new rescue session
// (re-scans don't re-alert the neighbourhood).
async function notifyTagScan({tagId, tagData, sessionId, scannerUid, lat, lng, address, isNewSession}) {
  const petName = tagData.name || 'Your pet';
  const ownerId = tagData.ownerId;

  if (ownerId && ownerId !== scannerUid) {
    await safeNotifyUser({
      uid: ownerId,
      title: `${petName} was just scanned!`,
      body: address
        ? `Someone scanned ${petName}'s tag near ${address}. Tap to open the chat.`
        : `Someone scanned ${petName}'s tag. Tap to open the chat.`,
      data: {type: 'tag_scanned', tagId, sessionId},
    });
  }

  if (isNewSession && lat !== null && lng !== null) {
    await notifyNearbyUsers({
      lat,
      lng,
      excludeUids: [ownerId, scannerUid],
      category: NOTIFY_CATEGORY.tagScan,
      title: 'Lost pet spotted near you',
      body: tagData.name
        ? `${tagData.name}, a lost pet, was just spotted nearby. Keep an eye out!`
        : 'A lost pet was just spotted nearby. Keep an eye out!',
      data: {type: 'tag_scanned_nearby', tagId, sessionId},
    });
  }
}

// ---- Pet transporter notifications ----------------------------------------
//
// Transporters are notified about exactly three things:
//   1. a new assignment offer for them
//   2. the rescue (pickup) location of their case changing
//   3. the clinic address of their case changing
const TRANSPORTER_ACTIVE_STATUSES = [
  'assigned', 'accepted', 'ongoing', 'arrived', 'treatment', 'dropoff',
  'searching_clinic', 'in_transit_shelter', 'awaiting_adopter_pickup',
];

exports.notifyTransporterAssignment = onDocumentCreated(
  'cases/{caseId}/transportAssignments/{assignmentId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const a = snap.data();
    if (a.status !== 'pending' || !a.riderId) return;

    const caseSnap = await db.collection('cases').doc(event.params.caseId).get();
    const c = caseSnap.data() || {};
    await safeNotifyUser({
      uid: a.riderId,
      title: 'New rescue assignment',
      body: c.address
        ? `You've been assigned a rescue at ${c.address}. Tap to accept or decline.`
        : 'You have a new rescue transport assignment. Tap to accept or decline.',
      data: {
        type: 'transporter_assignment',
        caseId: event.params.caseId,
        assignmentId: event.params.assignmentId,
      },
    });
  },
);

// ---- Transport offer expiry and staff alerts ------------------------------
//
// An offer's wait depends on the case's urgency (transportOfferTtlFor in
// lib/core/models/rescue/transport_assignment.dart) and is stored on the
// offer as expiresAt. Until now an unanswered offer only expired when a
// staff screen happened to read it (reconcileStaleOffer). This job expires
// it on time, doing exactly what reconcileStaleOffer does; the client
// reconcile stays as a fallback. Whichever path marks an offer rejected or
// expired, notifyStaffOfOfferOutcome tells the organization's staff to
// choose another transporter.

const OFFER_EXPIRY_BATCH_LIMIT = 200;

// Same writes as TransportAssignmentRepository.reconcileStaleOffer.
async function expireOfferIfStale(offerRef) {
  const caseRef = offerRef.parent.parent;
  return db.runTransaction(async (tx) => {
    const [offerSnap, caseSnap] = await Promise.all([tx.get(offerRef), tx.get(caseRef)]);
    if (!offerSnap.exists) return false;
    const o = offerSnap.data();
    if (o.status !== 'pending') return false;
    if (!o.expiresAt || o.expiresAt.toMillis() >= Date.now()) return false;
    const now = admin.firestore.Timestamp.now();
    tx.update(offerRef, {status: 'expired', respondedAt: now});
    if (caseSnap.exists && caseSnap.get('currentAssignmentId') === offerRef.id) {
      tx.update(caseRef, {currentAssignmentId: admin.firestore.FieldValue.delete()});
    }
    return true;
  });
}

// Runs every minute so a Critical case's 5-minute offer doesn't sit
// expired for long. Needs the transportAssignments (status, expiresAt)
// collection-group index in firestore.indexes.json.
exports.expireTransportOffers = onSchedule('every 1 minutes', async () => {
  const snap = await db
    .collectionGroup('transportAssignments')
    .where('status', '==', 'pending')
    .where('expiresAt', '<=', admin.firestore.Timestamp.now())
    .limit(OFFER_EXPIRY_BATCH_LIMIT)
    .get();
  for (const doc of snap.docs) {
    try {
      await expireOfferIfStale(doc.ref);
    } catch (e) {
      console.error('[expireTransportOffers] could not expire', doc.ref.path, e);
    }
  }
});

// Who to tell in an organization (functions/org_access.js orgMemberUids):
// the owner, active Admins, and active Staff holding any of [anyOf] (every
// active member when [anyOf] is empty). With adminsOnly, the owner and
// active Admins only.
async function orgStaffUids(orgId, {adminsOnly = false, anyOf = []} = {}) {
  return orgMemberUids(db, orgId, {adminsOnly, anyOf});
}

// Push plus in-app notification to each uid, once.
async function notifyStaff(uids, {title, body, data}) {
  for (const uid of new Set(uids.filter(Boolean))) {
    try {
      await db.collection('users').doc(uid).collection('notifications').add({
        title,
        message: body,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        type: data.type,
        caseId: data.caseId || null,
      });
    } catch (e) {
      console.warn('[notifyStaff] in-app notification failed', uid, e.message);
    }
    await safeNotifyUser({uid, title, body, data});
  }
}

// After this many declined or expired offers on a Critical case, every
// organization admin is alerted too (Assign Transporter shows the
// "No transporter available" choices at the same point). Keep equal to
// kNoTransporterAttemptLimit in transport_assignment_rules.dart.
const NO_TRANSPORTER_ATTEMPT_LIMIT = 3;

const OFFER_OUTCOME_COPY = {
  rejected: (rider) => ({
    title: 'Transporter declined',
    body: `${rider} declined the transport offer. Choose another transporter for this case.`,
  }),
  expired: (rider) => ({
    title: 'Transport offer expired',
    body: `${rider} did not respond in time. Choose another transporter for this case.`,
  }),
};

exports.notifyStaffOfOfferOutcome = onDocumentUpdated(
  'cases/{caseId}/transportAssignments/{assignmentId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after || before.status === after.status) return;
    if (before.status !== 'pending') return;
    const copyFor = OFFER_OUTCOME_COPY[after.status];
    if (!copyFor) return;
    // Demo riders (debug builds) answer in seconds; don't page anyone.
    if (after.isDemo === true) return;

    const {caseId, assignmentId} = event.params;
    const caseSnap = await db.collection('cases').doc(caseId).get();
    if (!caseSnap.exists) return;
    const c = caseSnap.data();
    // The case moved on (a newer offer is already out): nothing to choose.
    if (c.currentAssignmentId && c.currentAssignmentId !== assignmentId) return;

    const rider = after.riderName || 'The transporter';
    const copy = copyFor(rider);

    // Case timeline entry (staff only; nothing for the reporter).
    await db.collection('cases').doc(caseId).collection('activityLogs').add({
      action: after.status === 'rejected' ? 'transporter_offer_rejected' : 'transporter_offer_expired',
      actorUid: after.status === 'rejected' ? (after.riderId || null) : null,
      actorName: after.status === 'rejected' ? rider : 'System',
      actorRole: after.status === 'rejected' ? 'transporter' : null,
      details: {
        assignmentId,
        riderId: after.riderId || null,
        riderName: rider,
        reason: after.rejectionReason || null,
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const recipients = [after.offeredBy, ...(await orgStaffUids(c.organizationId, {anyOf: ['rescue']}))];
    let {title, body} = copy;

    if (c.urgency === 'Critical') {
      const failed = await db.collection('cases').doc(caseId).collection('transportAssignments')
        .where('status', 'in', ['rejected', 'expired'])
        .get();
      if (failed.size >= NO_TRANSPORTER_ATTEMPT_LIMIT) {
        recipients.push(...(await orgStaffUids(c.organizationId, {adminsOnly: true})));
        title = 'URGENT: No transporter for a Critical case';
        body = `${failed.size} transport offers for this Critical case were declined or expired. `
          + 'Refer the case, have the organization transport it, or offer it to another transporter.';
      }
    }

    await notifyStaff(recipients, {
      title,
      body,
      data: {type: 'transport_offer_outcome', caseId, assignmentId, status: after.status},
    });
  },
);

// ---- Transporter ended the trip -------------------------------------------
//
// End Reasons Vehicle breakdown, Animal Deceased and Other (transit_rules.dart
// resolveEndReason) end the transporter's trip and stamp endReasonKind +
// transitEndedAt. Breakdown sends the case back to Assign Transporter;
// Deceased and Other leave it in transit_ended for a staff decision. Staff
// get a push and in-app notification, and an adminAlerts entry is written
// (same shape as needs_specialized_assistance above). The reporter is told
// about a breakdown or other stop, but not about a reported death until
// staff confirm it.
const TRANSIT_END_COPY = {
  vehicle_breakdown: {
    staffTitle: 'Transporter vehicle breakdown',
    staffBody: 'The transporter had a vehicle breakdown. The case is back in Assign Transporter: '
      + 'choose another transporter.',
    reporter: {
      title: 'Update on your rescue report',
      body: 'The transporter had a vehicle problem. The rescue team is arranging another transporter.',
    },
  },
  deceased: {
    staffTitle: 'Animal reported deceased in transit',
    staffBody: 'The transporter reported that the animal died in transit. Open the case to confirm.',
    reporter: null,
  },
  other: {
    staffTitle: 'Transporter stopped the trip',
    staffBody: 'The transporter stopped the trip. Open the case to decide the next step.',
    reporter: {
      title: 'Update on your rescue report',
      body: 'The transport was interrupted. The rescue team is deciding the next step.',
    },
  },
};

exports.notifyStaffOfTransitEnd = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    const endedAt = millisOf(after.transitEndedAt);
    if (!endedAt || endedAt === millisOf(before.transitEndedAt)) return;
    const copy = TRANSIT_END_COPY[after.endReasonKind];
    if (!copy) return;

    const caseId = event.params.caseId;
    const reasonNote = after.endReasonNotes ? ` Note: ${after.endReasonNotes}` : '';

    await db.collection('adminAlerts').add({
      type: `transit_${after.endReasonKind}`,
      caseId,
      organizationId: after.organizationId || null,
      reason: after.endReason || null,
      notes: after.endReasonNotes || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
    });

    await notifyStaff(await orgStaffUids(after.organizationId, {anyOf: ['rescue']}), {
      title: copy.staffTitle,
      body: `${copy.staffBody}${reasonNote}`,
      data: {type: 'transit_ended_staff', caseId, kind: after.endReasonKind},
    });

    if (copy.reporter && after.reporterId) {
      await safeNotifyUser({
        uid: after.reporterId,
        title: copy.reporter.title,
        body: copy.reporter.body,
        data: {type: 'case_status_update', caseId, status: after.status || ''},
      });
    }
  },
);

// ---- Shelter leg blocked: no shelter pin ------------------------------------
//
// TransitCaseService (transporter app) stops before the shelter leg when the
// organization has no saved shelter location (there is no default shelter)
// and stamps cases/{id}.shelterLocationMissing. Each new stamp alerts the
// organization's staff and admins once, with an adminAlerts entry, so an
// admin sets the pin in Organization Profile and the transporter can go on.
exports.notifyStaffOfMissingShelterPin = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    const at = millisOf((after.shelterLocationMissing || {}).at);
    if (!at || at === millisOf((before.shelterLocationMissing || {}).at)) return;
    const caseId = event.params.caseId;
    const orgId = after.organizationId || null;

    await db.collection('adminAlerts').add({
      type: 'shelter_location_missing',
      caseId,
      organizationId: orgId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
    });
    const recipients = [
      ...(await orgStaffUids(orgId, {anyOf: ['rescue']})),
      ...(await orgStaffUids(orgId, {adminsOnly: true})),
    ];
    await notifyStaff(recipients, {
      title: 'Set your shelter location',
      body: 'A transporter can\'t take an animal to the shelter because your organization has no shelter '
        + 'location saved. An admin needs to set it in Organization Profile, then the transporter can continue.',
      data: {type: 'shelter_location_missing', caseId},
    });
  },
);

// ---- Report verification ------------------------------------------------
//
// Before a report is accepted, staff may ask the reporter for a fresh photo
// (cases/{id}.liveProofRequest) or send a rider to check the location
// (cases/{id}.verification.riderId). Each gets one push when it happens.
function millisOf(ts) {
  return ts && typeof ts.toMillis === 'function' ? ts.toMillis() : 0;
}

exports.notifyCaseVerificationEvents = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    const caseId = event.params.caseId;

    const askedBefore = millisOf((before.liveProofRequest || {}).requestedAt);
    const askedAfter = millisOf((after.liveProofRequest || {}).requestedAt);
    if (askedAfter && askedAfter !== askedBefore) {
      await safeNotifyUser({
        uid: after.reporterId,
        title: 'A new photo is needed',
        body: 'The rescue team asked for a new photo or video of the animal you reported. '
          + 'Open the case to send one.',
        data: {type: 'case_live_proof_requested', caseId},
      });
    }

    const vBefore = before.verification || {};
    const vAfter = after.verification || {};
    const newVisit = vAfter.riderId && !vAfter.riderOutcome && (
      vAfter.riderId !== vBefore.riderId ||
      millisOf(vAfter.riderAssignedAt) !== millisOf(vBefore.riderAssignedAt)
    );
    if (newVisit) {
      await safeNotifyUser({
        uid: vAfter.riderId,
        title: 'Location check requested',
        body: after.address
          ? `Please check whether the reported animal is at ${after.address}.`
          : 'An organization asked you to check a reported location.',
        data: {type: 'verification_visit', caseId},
      });
    }
  },
);

function clinicAddressOf(c) {
  return (c.dropoffAddress || c.vetClinicAddress || '').trim();
}

exports.notifyTransporterCaseChanges = onDocumentUpdated(
  'cases/{caseId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const riderId = after.riderId || after.assignedVolunteerId;
    if (!riderId) return;
    if (!TRANSPORTER_ACTIVE_STATUSES.includes((after.status || '').toLowerCase())) return;
    // The rider's own clinic reroute (transit_progress_page.dart) changes
    // the clinic too, but they already know — don't push it back to them.
    const reroutedByRider = (before.status || '') === 'searching_clinic';

    const caseId = event.params.caseId;

    const locationChanged =
      before.lat !== after.lat || before.lng !== after.lng ||
      (before.address || '') !== (after.address || '');
    if (locationChanged && after.lat != null && after.lng != null) {
      await safeNotifyUser({
        uid: riderId,
        title: 'Rescue location updated',
        body: after.address
          ? `The pick up location changed to ${after.address}.`
          : 'The pick up location for your rescue was updated.',
        data: {type: 'transporter_location_updated', caseId},
      });
    }

    const beforeClinic = clinicAddressOf(before);
    const afterClinic = clinicAddressOf(after);
    if (afterClinic && beforeClinic !== afterClinic && !reroutedByRider) {
      await safeNotifyUser({
        uid: riderId,
        title: 'Clinic address changed',
        body: `Your drop off clinic is now ${afterClinic}.`,
        data: {type: 'transporter_clinic_changed', caseId},
      });
    }
  },
);

// ---- Adoption follow-up reminders -----------------------------------------
//
// Every morning: the adopter is reminded on a follow-up's due date and again
// 3 days later, and the organization's staff are alerted once it is 7 days
// overdue (timings in follow_up_reminder_rules.js, pending the
// organization's confirmation). Staff can still send a reminder by hand
// (AdoptionApplicationRepository.sendFollowUpReminder).
//
// Duplicate guard: each reminder is claimed in a transaction by stamping
// followUps/{id}.autoReminders.<stage> before anything is sent, so a retry
// or an overlapping run never sends it twice. The stamps are tied to the
// due date (autoReminders.forDate); rescheduling starts them over.
// Needs the followUps (status, scheduledDate) collection-group index.
const {remindersDue} = require('./follow_up_reminder_rules');

const OPEN_FOLLOW_UP_STATUSES = ['scheduled', 'reminderSent'];

async function claimReminders(followUpRef, nowMs) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(followUpRef);
    if (!snap.exists) return [];
    const f = snap.data();
    if (!OPEN_FOLLOW_UP_STATUSES.includes(f.status) || !f.scheduledDate) return [];
    const scheduledMs = f.scheduledDate.toMillis();
    const sent = f.autoReminders || null;
    const stages = remindersDue({scheduledMs, nowMs, sent: sent && {
      ...sent,
      forDate: millisOf(sent.forDate),
    }});
    if (stages.length === 0) return [];

    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const sameDate = sent && millisOf(sent.forDate) === scheduledMs;
    const update = {
      autoReminders: {
        ...(sameDate ? sent : {}),
        forDate: f.scheduledDate,
        ...Object.fromEntries(stages.map((s) => [s, now])),
      },
    };
    if (stages.some((s) => s !== 'staff')) {
      // Same fields the manual reminder writes.
      update.reminderSentAt = now;
      update.reminderCount = (Number(f.reminderCount) || 0) + 1;
      if (f.status === 'scheduled') update.status = 'reminderSent';
    }
    tx.update(followUpRef, update);
    return stages;
  });
}

exports.sendFollowUpReminders = onSchedule(
  {schedule: 'every day 08:00', timeZone: 'Asia/Manila'},
  async () => {
    const nowMs = Date.now();
    const snap = await db
      .collectionGroup('followUps')
      .where('status', 'in', OPEN_FOLLOW_UP_STATUSES)
      .where('scheduledDate', '<=', admin.firestore.Timestamp.fromMillis(nowMs))
      .get();

    const adoptions = new Map();
    for (const doc of snap.docs) {
      const adoptionRef = doc.ref.parent.parent;
      if (!adoptionRef) continue;
      try {
        if (!adoptions.has(adoptionRef.id)) {
          const a = await adoptionRef.get();
          adoptions.set(adoptionRef.id, a.exists ? a.data() : null);
        }
        const app = adoptions.get(adoptionRef.id);
        // Follow-ups only matter while the adoption is live: not after the
        // animal came back (return reached Intake) or monitoring ended.
        if (!app || app.postAdoptionStatus === 'completed') continue;
        if (app.returnRequest && app.returnRequest.status === 'intake') continue;

        const stages = await claimReminders(doc.ref, nowMs);
        if (stages.length === 0) continue;

        const personal = app.personal || {};
        const animalName = personal.animalName || 'your adopted animal';
        const adoptionId = adoptionRef.id;

        if (stages.includes('due') || stages.includes('overdue')) {
          const overdue = stages.includes('overdue');
          const title = overdue ? 'Follow-up check-in overdue' : 'Follow-up check-in due today';
          const body = overdue
            ? `Your check-in for ${animalName} is overdue. Please send it from the app so the organization knows how they're doing.`
            : `Your check-in for ${animalName} is due today. Open the app to send an update.`;
          if (personal.adopterId) {
            try {
              await db.collection('users').doc(personal.adopterId).collection('notifications').add({
                title,
                message: body,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
                type: 'follow_up_reminder',
                adoptionId,
              });
            } catch (e) {
              console.warn('[sendFollowUpReminders] in-app notification failed', adoptionId, e.message);
            }
            await safeNotifyUser({
              uid: personal.adopterId,
              title,
              body,
              data: {type: 'follow_up_reminder', adoptionId, followUpId: doc.id},
            });
          }
          await adoptionRef.update({
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: overdue ? 'Automatic reminder sent: follow-up overdue.' : 'Automatic reminder sent: follow-up due today.',
              timestamp: admin.firestore.Timestamp.fromMillis(nowMs),
            }),
          });
        }

        if (stages.includes('staff')) {
          await db.collection('adminAlerts').add({
            type: 'follow_up_overdue',
            adoptionId,
            followUpId: doc.id,
            organizationId: app.organizationId || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            resolved: false,
          });
          const adopter = personal.adopterName || 'The adopter';
          await notifyStaff(await orgStaffUids(app.organizationId, {anyOf: ['adoptions']}), {
            title: 'Adoption follow-up overdue',
            body: `${adopter} has not sent the check-in for ${personal.animalName || 'their adopted animal'} `
              + 'for over a week. Contact them or record the follow-up.',
            data: {type: 'follow_up_overdue_staff', adoptionId, followUpId: doc.id},
          });
        }
      } catch (e) {
        console.error('[sendFollowUpReminders] failed for', doc.ref.path, e);
      }
    }
  },
);

// ---- Referrals to another organization ------------------------------------
//
// CaseReferralRepository (the app) refers a case: status 'referred', the
// target in cases/{id}.referredToOrgId and a summary in `referral`, plus a
// cases/{id}/referrals/{rid} record. Only the target organization's staff
// see and answer it (firestore.rules isReferralTarget). Accept makes them
// the owner (case to their Rescue Review); Decline sends it back to the
// referring organization's Rescue Review with the reason.
//
// notifyCaseReferralCreated tells the target's staff a referral arrived;
// notifyCaseReferralOutcome tells the referring organization's staff (and
// whoever sent it) when it is accepted, declined or returned unanswered.
// followUpCaseReferrals (hourly) reminds the target once at 24 hours and
// returns the case to the referring organization at 48 hours (timings in
// referral_rules.js, pending the organization's confirmation). Each step is
// claimed in a transaction that re-checks the case still waits on the same
// referral, so a retry or an answer in the meantime never double-sends or
// undoes it. LGU/barangay referrals are one-way notifications and are left
// alone (they have no referredToOrgId).
const {referralStepDue, REFERRAL_REMINDER_HOURS, REFERRAL_RETURN_HOURS} = require('./referral_rules');

exports.notifyCaseReferralCreated = onDocumentCreated(
  'cases/{caseId}/referrals/{referralId}',
  async (event) => {
    const r = event.data && event.data.data();
    if (!r || r.type !== 'anotherOrganization' || !r.targetOrgId) return;
    const {caseId, referralId} = event.params;
    const from = r.fromOrgName || 'Another organization';
    await notifyStaff(await orgStaffUids(r.targetOrgId, {anyOf: ['rescue']}), {
      title: 'New case referral',
      body: `${from} referred a rescue case to your organization. Open it to accept or decline.`,
      data: {type: 'case_referral', caseId, referralId},
    });
  },
);

const REFERRAL_OUTCOME_COPY = {
  accepted: (r) => ({
    title: 'Referral accepted',
    body: `${r.targetOrgName || 'The organization'} accepted your referral and took over the case.`,
  }),
  declined: (r) => ({
    title: 'Referral declined',
    body: `${r.targetOrgName || 'The organization'} declined your referral`
      + `${r.declineReason ? `: ${r.declineReason}` : '.'} The case is back in your Rescue Review.`,
  }),
  expired: (r) => ({
    title: 'Referral not answered',
    body: `${r.targetOrgName || 'The organization'} did not answer your referral within `
      + `${REFERRAL_RETURN_HOURS} hours. The case is back in your Rescue Review.`,
  }),
};

exports.notifyCaseReferralOutcome = onDocumentUpdated(
  'cases/{caseId}/referrals/{referralId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after || before.status === after.status) return;
    if (before.status !== 'referredPending' || after.type !== 'anotherOrganization') return;
    const copyFor = REFERRAL_OUTCOME_COPY[after.status];
    if (!copyFor) return;
    const {caseId, referralId} = event.params;
    const {title, body} = copyFor(after);
    const recipients = [after.createdByUid, ...(await orgStaffUids(after.fromOrgId, {anyOf: ['rescue']}))];
    await notifyStaff(recipients, {
      title,
      body,
      data: {type: 'case_referral', caseId, referralId, status: after.status},
    });
  },
);

// Re-reads the case inside the transaction: still referred, to the same
// organization, for the same referral.
function stillWaitingOn(snap, c) {
  if (!snap.exists) return null;
  const d = snap.data();
  const r = d.referral || {};
  if (d.status !== 'referred' || d.referredToOrgId !== c.referredToOrgId) return null;
  if (!r.referralId || r.referralId !== (c.referral || {}).referralId) return null;
  return d;
}

exports.followUpCaseReferrals = onSchedule('every 60 minutes', async () => {
  const nowMs = Date.now();
  const snap = await db.collection('cases').where('status', '==', 'referred').get();
  for (const doc of snap.docs) {
    const c = doc.data();
    const r = c.referral || {};
    if (!c.referredToOrgId || !r.referralId) continue; // LGU or older referrals
    try {
      const step = referralStepDue({
        referredAtMs: r.referredAt ? millisOf(r.referredAt) : undefined,
        nowMs,
        reminded: Boolean(r.reminderSentAt),
      });
      if (!step) continue;

      if (step === 'remind') {
        const claimed = await db.runTransaction(async (tx) => {
          const d = stillWaitingOn(await tx.get(doc.ref), c);
          if (!d || d.referral.reminderSentAt) return false;
          tx.update(doc.ref, {'referral.reminderSentAt': admin.firestore.Timestamp.fromMillis(nowMs)});
          return true;
        });
        if (!claimed) continue;
        await notifyStaff(await orgStaffUids(c.referredToOrgId, {anyOf: ['rescue']}), {
          title: 'Referral waiting for your answer',
          body: `${r.fromOrgName || 'Another organization'} referred a case to you ${REFERRAL_REMINDER_HOURS} hours ago. `
            + `Accept or decline it; with no answer it goes back to them after ${REFERRAL_RETURN_HOURS} hours.`,
          data: {type: 'case_referral', caseId: doc.id, referralId: r.referralId},
        });
        continue;
      }

      // step === 'return': same writes as a decline, marked 'expired'.
      await db.runTransaction(async (tx) => {
        const d = stillWaitingOn(await tx.get(doc.ref), c);
        if (!d) return;
        const referralRef = doc.ref.collection('referrals').doc(r.referralId);
        const referralSnap = await tx.get(referralRef);
        const now = admin.firestore.Timestamp.fromMillis(nowMs);
        const target = r.targetOrgName || 'The receiving organization';
        const from = r.fromOrgName || 'the referring organization';
        tx.update(doc.ref, {
          status: 'pending',
          referredToOrgId: admin.firestore.FieldValue.delete(),
          referralOutcome: {
            status: 'expired',
            referralId: r.referralId,
            targetOrgId: c.referredToOrgId,
            targetOrgName: r.targetOrgName || null,
            fromOrgId: r.fromOrgId || null,
            fromOrgName: r.fromOrgName || null,
            reason: `No answer within ${REFERRAL_RETURN_HOURS} hours`,
            byUid: null,
            byName: 'System',
            at: now,
          },
          statusHistory: admin.firestore.FieldValue.arrayUnion({
            status: `${target} did not answer the referral in time. The case is back with ${from} for review.`,
            timestamp: now,
          }),
        });
        if (referralSnap.exists && referralSnap.get('status') === 'referredPending') {
          tx.update(referralRef, {status: 'expired', respondedAt: now, respondedByName: 'System'});
        }
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'referral_expired',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          details: {
            referralId: r.referralId,
            targetOrgId: c.referredToOrgId,
            targetOrgName: r.targetOrgName || null,
            hours: REFERRAL_RETURN_HOURS,
          },
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      console.error('[followUpCaseReferrals] failed for', doc.ref.path, e);
    }
  }
});

// ---- Rescue timers: quarantine end and intake completion ------------------
//
// These used to happen only when staff opened the case
// (CaseIntakeRepository.checkAndCompleteQuarantineIfDue and
// checkAndCompleteIntakeIfDue, which stay as the in-app fallback). Every 30
// minutes the server makes the same writes, each re-checked inside a
// transaction so a run never repeats or undoes what the app already did.
// Decisions in rescue_timer_rules.js.
//   - Quarantine: quarantineStatus 'completed', quarantineEndedAt = the
//     scheduled end, the same automatic reason; plus an activity-log entry,
//     and the organization's staff are told (push + in-app notification).
//     Needs the cases (quarantineStatus, quarantineScheduledEndAt) index.
//   - Intake: once the animal is received and every animal has its record,
//     status 'completed' + intakeCompletedAt with the same status line and
//     activity-log entry. Cases whose animals follow separate
//     post-treatment paths are completed per animal in the app.
const {
  quarantineDue,
  intakeCompletionDue,
  animalsDueForIntakeCompletion,
  stageSummary,
  derivedCaseStatus,
} = require('./rescue_timer_rules');

const QUARANTINE_AUTO_REASON = 'Automatic — scheduled duration elapsed.';

function caseAnimalLabel(c) {
  const animals = Array.isArray(c.animals) ? c.animals : [];
  const names = animals.map((a) => a && (a.name || a.species)).filter(Boolean);
  if (names.length) return names.slice(0, 3).join(', ');
  return c.animalName || c.animalType || c.species || 'The animal';
}

exports.completeDueQuarantines = onSchedule('every 30 minutes', async () => {
  const nowMs = Date.now();
  const snap = await db.collection('cases')
    .where('quarantineStatus', '==', 'active')
    .where('quarantineScheduledEndAt', '<=', admin.firestore.Timestamp.fromMillis(nowMs))
    .get();
  for (const doc of snap.docs) {
    try {
      const ended = await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists) return null;
        const c = s.data();
        const endMs = millisOf(c.quarantineScheduledEndAt) || null;
        if (!quarantineDue({status: c.quarantineStatus, scheduledEndMs: endMs, nowMs})) return null;
        tx.update(doc.ref, {
          quarantineStatus: 'completed',
          quarantineEndedAt: c.quarantineScheduledEndAt,
          quarantineEndReason: QUARANTINE_AUTO_REASON,
        });
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'quarantine_completed',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          details: {reason: QUARANTINE_AUTO_REASON, scheduledEndAt: c.quarantineScheduledEndAt},
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        return c;
      });
      if (!ended) continue;
      await notifyStaff(await orgStaffUids(ended.organizationId, {anyOf: ['rescue', 'animals', 'care']}), {
        title: 'Quarantine ended',
        body: `${caseAnimalLabel(ended)} finished the scheduled quarantine. Check on them and plan the next step.`,
        data: {type: 'quarantine_ended', caseId: doc.id},
      });
    } catch (e) {
      console.error('[completeDueQuarantines] failed for', doc.ref.path, e);
    }
  }
});

exports.completeDueIntakes = onSchedule('every 30 minutes', async () => {
  const snap = await db.collection('cases').where('status', '==', 'intake').get();
  for (const doc of snap.docs) {
    const first = doc.data();
    if (!first.intakeReceivedAt) continue;
    try {
      const records = await db.collection('animals').where('linkedCaseId', '==', doc.id).get();
      const indexes = records.docs
        .map((r) => r.get('sourceAnimalIndex'))
        .filter((i) => typeof i === 'number')
        .map((i) => Math.trunc(i));
      if (!intakeCompletionDue(first, indexes)) continue;
      await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists || !intakeCompletionDue(s.data(), indexes)) return;
        const now = admin.firestore.Timestamp.now();
        tx.update(doc.ref, {
          status: 'completed',
          intakeCompletedAt: now,
          statusHistory: admin.firestore.FieldValue.arrayUnion({
            status: 'Intake completed — all animal records created.',
            timestamp: now,
          }),
        });
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'intake_completed',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      console.error('[completeDueIntakes] failed for', doc.ref.path, e);
    }
  }
  await completeDueAnimalIntakes();
});

async function linkedRecordIndexes(caseId) {
  const records = await db.collection('animals').where('linkedCaseId', '==', caseId).get();
  return records.docs
    .map((r) => r.get('sourceAnimalIndex'))
    .filter((i) => typeof i === 'number')
    .map((i) => Math.trunc(i));
}

// Multi-animal cases whose animals took separate post-treatment paths: each
// animal sent to Intake is completed once it was received and has its
// record, with the same writes as CaseIntakeRepository.completeIntakeForAnimals.
// The case may still read in_treatment while another animal is in
// treatment, so these are found by their Intake stage, not their status.
async function completeDueAnimalIntakes() {
  const snap = await db.collection('cases').where('activeAnimalStages', 'array-contains', 'intake').get();
  for (const doc of snap.docs) {
    try {
      const indexes = await linkedRecordIndexes(doc.id);
      if (!animalsDueForIntakeCompletion(doc.data(), indexes).length) continue;
      await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists) return;
        const c = s.data();
        const due = animalsDueForIntakeCompletion(c, indexes);
        if (!due.length) return;
        const now = admin.firestore.Timestamp.now();
        const animals = c.animals.map((a, i) => (due.includes(i) ? {...a, intakeCompletedAt: now} : a));
        const update = {
          animals,
          ...stageSummary(animals),
          status: derivedCaseStatus(animals) || c.status || 'intake',
          statusHistory: admin.firestore.FieldValue.arrayUnion({
            status: 'Intake completed for the selected animal(s).',
            timestamp: now,
          }),
        };
        tx.update(doc.ref, update);
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'intake_completed',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          details: {animalIndexes: due},
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      console.error('[completeDueAnimalIntakes] failed for', doc.ref.path, e);
    }
  }
}

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

// ---- Zoom interview meetings -------------------------------------------
//
// Zoom interview spec — meeting creation/reschedule/cancel is only ever
// done from here, never client-side, so the Zoom Server-to-Server OAuth
// client secret is never shipped to the Flutter app. Uses the
// `defineSecret` Secret Manager params API this file already imported
// (see the top of this file) but never actually called until now.
//
// Deploy-time setup this code depends on (not done by this code — an
// operator action per organization):
//   firebase functions:secrets:set ZOOM_ACCOUNT_ID
//   firebase functions:secrets:set ZOOM_CLIENT_ID
//   firebase functions:secrets:set ZOOM_CLIENT_SECRET
// (a Zoom Server-to-Server OAuth app's Account ID/Client ID/Client
// Secret — the current officially-supported Zoom integration method,
// JWT apps having been retired). Until those are set, createOrUpdateZoomMeeting
// throws 'failed-precondition' and the Flutter side shows "Online meeting
// setup is unavailable for this organization." rather than silently
// pretending a meeting was created.
//
// Multi-organization support: only a single global Zoom connection is
// wired up right now (one set of secrets). zoomProviderOrganizationId is
// already stored per meeting so a future per-organization secret lookup
// (e.g. reading connection info from `organizations/{orgId}/zoomConnection`
// instead of the global secrets) is additive, not a breaking change to the
// stored shape.
const zoomAccountId = defineSecret('ZOOM_ACCOUNT_ID');
const zoomClientId = defineSecret('ZOOM_CLIENT_ID');
const zoomClientSecret = defineSecret('ZOOM_CLIENT_SECRET');

async function getZoomAccessToken() {
  const basic = Buffer.from(`${zoomClientId.value()}:${zoomClientSecret.value()}`).toString('base64');
  const res = await fetch(
    `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${encodeURIComponent(zoomAccountId.value())}`,
    {method: 'POST', headers: {Authorization: `Basic ${basic}`}},
  );
  if (!res.ok) {
    throw new Error(`Zoom OAuth token request failed: ${res.status}`);
  }
  const data = await res.json();
  return data.access_token;
}

// Idempotent by (applicationId, appointmentRevision) — the Flutter caller
// bumps appointmentRevision only when the interview is actually
// rescheduled (see interview_scheduling.dart / adoption_process.dart's
// appointment-save flow), so a Firestore listener rebuild, a re-opened
// page, or a duplicate save with the SAME revision always returns the
// existing meeting instead of creating a second one.
exports.createOrUpdateZoomMeeting = onCall(
  {secrets: [zoomAccountId, zoomClientId, zoomClientSecret]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const {applicationId, appointmentRevision, topic, startTimeIso, durationMinutes} = request.data || {};
    if (!applicationId || !appointmentRevision || !startTimeIso) {
      throw new HttpsError('invalid-argument', 'applicationId, appointmentRevision, and startTimeIso are required.');
    }

    const appRef = db.collection('adoptions').doc(applicationId);
    const appSnap = await appRef.get();
    if (!appSnap.exists) {
      throw new HttpsError('not-found', 'Application not found.');
    }
    // Staff who handle adoptions for the application's organization.
    await requireOrgPermission(db, request, {
      organizationId: appSnap.get('organizationId') || undefined,
      anyOf: ['adoptions'],
    });
    const existing = appSnap.data().zoom;

    if (existing && existing.appointmentRevision === appointmentRevision && existing.zoomMeetingId) {
      return {zoomMeetingId: existing.zoomMeetingId, zoomJoinUrl: existing.zoomJoinUrl, reused: true};
    }

    let accessToken;
    try {
      accessToken = await getZoomAccessToken();
    } catch (e) {
      // Zoom not configured for this deployment yet — never blocks saving
      // an on-site appointment; the Flutter caller only invokes this
      // function at all when the interview type is Online.
      throw new HttpsError('failed-precondition', 'Online meeting setup is unavailable for this organization.');
    }

    // Reschedule: try to update the existing meeting in place first.
    if (existing && existing.zoomMeetingId) {
      try {
        const patchRes = await fetch(`https://api.zoom.us/v2/meetings/${existing.zoomMeetingId}`, {
          method: 'PATCH',
          headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'},
          body: JSON.stringify({topic: topic || 'Adoption Interview', start_time: startTimeIso, duration: durationMinutes || 30}),
        });
        if (patchRes.ok || patchRes.status === 204) {
          const updated = {
            zoomMeetingId: existing.zoomMeetingId,
            zoomJoinUrl: existing.zoomJoinUrl,
            zoomCreatedAt: existing.zoomCreatedAt || admin.firestore.FieldValue.serverTimestamp(),
            zoomUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            zoomMeetingStatus: 'active',
            zoomProviderOrganizationId: existing.zoomProviderOrganizationId || null,
            appointmentRevision,
          };
          await appRef.update({
            zoom: updated,
            statusHistory: admin.firestore.FieldValue.arrayUnion([
              {status: 'Online interview rescheduled — Zoom meeting updated.', timestamp: admin.firestore.Timestamp.now()},
            ]),
          });
          return {zoomMeetingId: updated.zoomMeetingId, zoomJoinUrl: updated.zoomJoinUrl, reused: false, updated: true};
        }
        // Update failed (meeting may have been deleted directly in Zoom) —
        // fall through and create a replacement, invalidating the old link.
      } catch (e) {
        // fall through to create a replacement
      }
    }

    const createRes = await fetch('https://api.zoom.us/v2/users/me/meetings', {
      method: 'POST',
      headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({
        topic: topic || 'Adoption Interview',
        type: 2, // scheduled meeting
        start_time: startTimeIso,
        duration: durationMinutes || 30,
        settings: {join_before_host: true, waiting_room: true},
      }),
    });
    if (!createRes.ok) {
      throw new HttpsError('internal', 'Could not create the Zoom meeting. You can retry from the appointment screen.');
    }
    const meeting = await createRes.json();

    // Safe metadata only, written to the shared application doc both admin
    // and adopter can read. The host start URL is sensitive (lets anyone
    // start the meeting as host) and is deliberately kept out of this doc.
    const zoomData = {
      zoomMeetingId: `${meeting.id}`,
      zoomJoinUrl: meeting.join_url,
      zoomCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
      zoomUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      zoomMeetingStatus: 'active',
      zoomProviderOrganizationId: null,
      appointmentRevision,
    };
    await appRef.update({
      zoom: zoomData,
      statusHistory: admin.firestore.FieldValue.arrayUnion([
        {status: 'Online interview scheduled — Zoom meeting created.', timestamp: admin.firestore.Timestamp.now()},
      ]),
    });
    // Host-only info lives in a separate, admin-only collection — never
    // merged into the adopter-readable adoptions/{id} doc.
    await db.collection('zoomMeetingHostInfo').doc(applicationId).set({
      hostStartUrl: meeting.start_url,
      zoomMeetingId: `${meeting.id}`,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {zoomMeetingId: zoomData.zoomMeetingId, zoomJoinUrl: zoomData.zoomJoinUrl, reused: false};
  },
);

// Cancellation spec — invalidates the Zoom meeting remotely (best-effort;
// meeting history is retained locally either way for audit) and flips the
// stored status so the Flutter UI stops showing the join link as active,
// without deleting the record of the meeting having existed.
exports.cancelZoomMeeting = onCall({secrets: [zoomAccountId, zoomClientId, zoomClientSecret]}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const {applicationId} = request.data || {};
  if (!applicationId) {
    throw new HttpsError('invalid-argument', 'applicationId is required.');
  }
  const appRef = db.collection('adoptions').doc(applicationId);
  const appSnap = await appRef.get();
  if (!appSnap.exists) return {cancelled: false};
  await requireOrgPermission(db, request, {
    organizationId: appSnap.get('organizationId') || undefined,
    anyOf: ['adoptions'],
  });
  const existing = appSnap.data()?.zoom;
  if (!existing || !existing.zoomMeetingId || existing.zoomMeetingStatus === 'cancelled') {
    return {cancelled: false};
  }

  try {
    const accessToken = await getZoomAccessToken();
    await fetch(`https://api.zoom.us/v2/meetings/${existing.zoomMeetingId}`, {
      method: 'DELETE',
      headers: {Authorization: `Bearer ${accessToken}`},
    });
  } catch (e) {
    // Zoom-side delete failed/unreachable — the local status flip below is
    // what actually hides the join link from the UI; audit history (the
    // meeting's prior existence) is never deleted either way.
  }

  await appRef.update({
    'zoom.zoomMeetingStatus': 'cancelled',
    'zoom.zoomUpdatedAt': admin.firestore.FieldValue.serverTimestamp(),
    statusHistory: admin.firestore.FieldValue.arrayUnion([
      {status: 'Interview cancelled — Zoom meeting invalidated.', timestamp: admin.firestore.Timestamp.now()},
    ]),
  });
  return {cancelled: true};
});

// Facebook Page Sharing spec — Animal Records → Facebook Page publishing.
// See functions/facebook.js for the full implementation; kept in its own
// module rather than growing this file further, same reasoning as every
// other self-contained integration here (Zoom, rescue sessions).
const facebook = require('./facebook');
exports.facebookConnectPage = facebook.facebookConnectPage;
exports.facebookConfirmPageSelection = facebook.facebookConfirmPageSelection;
exports.facebookTestConnection = facebook.facebookTestConnection;
exports.facebookDisconnectPage = facebook.facebookDisconnectPage;
exports.facebookPublishAnimalRecords = facebook.facebookPublishAnimalRecords;
exports.facebookSetPublisher = facebook.facebookSetPublisher;

// PayMongo donations & sponsorships — see functions/paymongo.js.
Object.assign(exports, require('./paymongo'));

// Active sponsor count on each sponsorship listing — see functions/sponsor_counts.js.
//Object.assign(exports, require('./sponsor_counts'));

// Admin campaign/sponsorship management, allocations & reallocation — see functions/campaigns.js.
Object.assign(exports, require('./campaigns'));

// Cross-applicant adoption checks (reads the client can't do) — see functions/adoptions.js.
Object.assign(exports, require('./adoptions'));
// Organization stamp on case/animal logs for the Audit page — see functions/audit_logs.js.
Object.assign(exports, require('./audit_logs'));
// Member access (Admin/Staff and permissions) — see functions/org_members.js.
Object.assign(exports, require('./org_members'));
// Shareable referral links (public/referral/index.html) — see functions/referral_shares.js.
Object.assign(exports, require('./referral_shares')({notifyStaff, orgStaffUids}));
// Public copy of each animal for non-staff readers — see functions/public_animals.js.
exports.syncPublicAnimal = require('./public_animals').syncPublicAnimal;

// ---- Organization verification review ------------------------------------
//
// Platform staff (users/{uid}.role 'admin' or 'ngo_staff') and system admins
// ('system_admin', the approvals console) approve, reject or
// ask for changes on an organization that submitted its documents
// (verificationStatus 'pending'). firestore.rules blocks every client from
// setting these fields, so each decision goes through here, is logged to
// auditLogs, and reaches the owner as a push and an in-app notification.
const ORG_REVIEW_DECISIONS = {
  approved: {
    title: 'Organization approved',
    body: (name) => `${name} is approved. You can now use the admin tools.`,
  },
  rejected: {
    title: 'Organization not approved',
    body: (name) => `${name} was not approved. Open the app to see why.`,
  },
  requiresChanges: {
    title: 'Changes needed',
    body: (name) => `${name} needs changes to its documents before it can be approved.`,
  },
};

exports.reviewOrganization = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
  const reviewer = await db.collection('users').doc(uid).get();
  const reviewerData = reviewer.exists ? reviewer.data() : {};
  if (!['admin', 'ngo_staff', 'system_admin'].includes(reviewerData.role)) {
    throw new HttpsError('permission-denied', 'Only platform staff can review organizations.');
  }

  const d = request.data || {};
  const organizationId = typeof d.organizationId === 'string' ? d.organizationId.trim() : '';
  if (!organizationId || organizationId.includes('/')) {
    throw new HttpsError('invalid-argument', 'organizationId is required.');
  }
  const decision = d.decision;
  if (!Object.prototype.hasOwnProperty.call(ORG_REVIEW_DECISIONS, decision)) {
    throw new HttpsError('invalid-argument', 'Choose approve, reject or ask for changes.');
  }
  const note = typeof d.note === 'string' ? d.note.trim() : '';
  if (decision !== 'approved' && !note) {
    throw new HttpsError('invalid-argument', 'Say what is wrong or what needs to change.');
  }
  if (note.length > 1000) throw new HttpsError('invalid-argument', 'Keep the note under 1,000 characters.');

  const reviewerName = reviewerData.name || reviewerData.fullName || reviewerData.email || 'Platform staff';
  const orgRef = db.collection('organizations').doc(organizationId);
  const org = await db.runTransaction(async (tx) => {
    const snap = await tx.get(orgRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Organization not found.');
    const data = snap.data();
    if (data.verificationStatus !== 'pending') {
      throw new HttpsError('failed-precondition', 'This organization is not waiting for review.');
    }
    tx.update(orgRef, {
      verificationStatus: decision,
      verificationRejectionReason: decision === 'approved' ? admin.firestore.FieldValue.delete() : note,
      verificationReviewedBy: uid,
      verificationReviewedByName: reviewerName,
      verificationReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return data;
  });

  const name = org.name || 'Your organization';
  try {
    await db.collection('auditLogs').add({
      category: 'organizationVerification',
      action: `organization_${decision}`,
      actorId: uid,
      actorName: reviewerName,
      organizationId,
      targetType: 'Organization',
      targetId: organizationId,
      previousValues: {verificationStatus: 'pending'},
      newValues: {verificationStatus: decision, note: note || null},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error('[reviewOrganization] audit log write failed', e);
  }

  const ownerId = org.ownerId;
  if (ownerId) {
    const copy = ORG_REVIEW_DECISIONS[decision];
    const body = copy.body(name);
    try {
      await db.collection('users').doc(ownerId).collection('notifications').add({
        title: copy.title,
        message: note ? `${body}\n\n${note}` : body,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        type: 'organization_review',
        organizationId,
      });
    } catch (e) {
      console.error('[reviewOrganization] notification write failed', e);
    }
    await safeNotifyUser({
      uid: ownerId,
      title: copy.title,
      body,
      data: {type: 'organization_review', organizationId, decision},
    });
  }
  return {ok: true};
});

// Volunteer attendance counts and badges on users/{uid}.volunteerStats — see functions/volunteer_stats.js.
exports.syncVolunteerStats = require('./volunteer_stats').syncVolunteerStats;
// Public copy of each rescue report for non-participants — see functions/public_cases.js.
exports.syncPublicCase = require('./public_cases').syncPublicCase;
// Each rider's newest offer status on their user doc, for staff of every organization — see functions/rider_status.js.
exports.syncRiderTransportStatus = require('./rider_status').syncRiderTransportStatus;

// ---- Rescue adoptions (Rescue gaps 6 and 10) ----------------------------
//
// The interested adopter (the reporter who said yes to adopting, or a user
// who registered interest on Track Case) sends an adoption request:
// adoptions/{id} with source 'rescue_case' and caseId, accepting the vet-fee,
// obligations and pickup-window agreements. The organization confirms it on
// Rescue Details. Decisions live in functions/rescue_adoption_rules.js.

const rescueAdoption = require('./rescue_adoption_rules');

async function notifyAdopter(uid, {title, body, data}) {
  if (!uid) return;
  try {
    await db.collection('users').doc(uid).collection('notifications').add({
      title,
      message: body,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false,
      type: data.type,
      caseId: data.caseId || null,
    });
  } catch (e) {
    console.warn('[notifyAdopter] in-app notification failed', uid, e.message);
  }
  await safeNotifyUser({uid, title, body, data});
}

function caseStaffOrgId(c) {
  if (c.organizationId) return c.organizationId;
  return Array.isArray(c.areaOrgIds) && c.areaOrgIds.length ? c.areaOrgIds[0] : null;
}

// Mirrors each request onto its case (cases/{id}.adoptionRequest), which the
// transporter flow, Track Case and Rescue Details read, and tells the right
// people about each step.
exports.syncRescueAdoptionRequest = onDocumentWritten('adoptions/{adoptionId}', async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const app = after || before;
  if (!app || app.source !== rescueAdoption.RESCUE_ADOPTION_SOURCE || !app.caseId) return;
  if (!after) return;
  const caseRef = db.collection('cases').doc(app.caseId);
  const id = event.params.adoptionId;
  const mirror = rescueAdoption.caseAdoptionRequestOf(id, after);
  const statusChanged = !before || before.status !== after.status;

  const caseData = await db.runTransaction(async (tx) => {
    const snap = await tx.get(caseRef);
    if (!snap.exists) return null;
    const c = snap.data();
    if (!rescueAdoption.shouldMirrorRequest(c.adoptionRequest, id, mirror.status)) return null;
    if (statusChanged || !c.adoptionRequest || c.adoptionRequest.applicationId !== id) {
      const label = {
        pending: `${mirror.adopterName} sent an adoption request.`,
        approved: `${mirror.adopterName} was confirmed as the adopter.`,
        rejected: `${mirror.adopterName}'s adoption request was not approved.`,
        withdrawn: `${mirror.adopterName}'s adoption request was closed.`,
        adopted: `Adoption completed with ${mirror.adopterName}.`,
      }[mirror.status];
      tx.update(caseRef, {
        adoptionRequest: {...mirror, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        ...(label ? {statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: label, timestamp: admin.firestore.Timestamp.now(),
        })} : {}),
      });
    }
    return c;
  });
  if (!caseData || !statusChanged) return;

  const data = {type: 'rescue_adoption_request', caseId: app.caseId};
  if (mirror.status === 'pending' && !before) {
    await notifyStaff(await orgStaffUids(caseStaffOrgId(caseData), {anyOf: ['adoptions', 'rescue']}), {
      title: 'New adoption request',
      body: `${mirror.adopterName} wants to adopt a rescued animal and accepted the vet-fee and pickup agreements. ` +
        'Review it on Rescue Details.',
      data,
    });
  } else if (mirror.status === 'approved') {
    await notifyAdopter(mirror.adopterId, {
      title: 'You are confirmed as the adopter',
      body: 'The organization confirmed your adoption request. As agreed, you cover the vet fees from now on. ' +
        `We will tell you when the animal is ready; you then have ${rescueAdoption.PICKUP_WINDOW_HOURS} hours to collect it.`,
      data,
    });
  } else if (mirror.status === 'rejected') {
    await notifyAdopter(mirror.adopterId, {
      title: 'Adoption request not approved',
      body: mirror.closedReason || 'The organization did not approve your adoption request.',
      data,
    });
  }
});

// Case-side follow-through: an organization accepting an unowned case takes
// over its pending request, and the adopter is told when the animal is
// ready for pickup.
exports.onRescueAdoptionCaseUpdate = onDocumentUpdated('cases/{caseId}', async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  const request = after.adoptionRequest;
  if (!request || !request.applicationId) return;

  if (after.organizationId && after.organizationId !== before.organizationId) {
    const appRef = db.collection('adoptions').doc(request.applicationId);
    try {
      const app = await appRef.get();
      if (app.exists && ['pending', 'approved'].includes(app.get('status')) &&
          app.get('organizationId') !== after.organizationId) {
        await appRef.update({organizationId: after.organizationId});
      }
    } catch (e) {
      console.error('[onRescueAdoptionCaseUpdate] stamping the request failed', request.applicationId, e);
    }
  }

  const readyBefore = millisOf((before.adopterPickup || {}).readyAt);
  const pickup = after.adopterPickup || {};
  const readyAfter = millisOf(pickup.readyAt);
  if (readyAfter && readyAfter !== readyBefore) {
    const deadline = new Date(millisOf(pickup.deadline));
    await notifyAdopter(pickup.adopterId || request.adopterId, {
      title: 'Ready for pickup',
      body: `The animal you are adopting is ready at ${pickup.place || 'the clinic'}. Please collect it by ` +
        `${deadline.toLocaleString('en-PH', {timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short'})}. ` +
        'Bring a valid ID and be ready to settle the vet fees.',
      data: {type: 'rescue_adoption_ready', caseId: event.params.caseId},
    });
  }
});

async function shelterCapacityOf(orgId) {
  if (!orgId) return null;
  const own = await db.collection('organizations').doc(orgId).collection('settings').doc('shelter').get();
  const legacy = own.exists ? null : await db.collection('settings').doc('shelter').get();
  const v = own.exists ? own.get('maxCapacity') : (legacy && legacy.exists ? legacy.get('maxCapacity') : null);
  return typeof v === 'number' ? v : null;
}

async function housedCountOf(orgId) {
  if (!orgId) return 0;
  const snap = await db.collection('animals').where('organizationId', '==', orgId).get();
  return snap.docs.filter((d) => rescueAdoption.isCurrentlyHoused(d.data())).length;
}

// Every 30 minutes: remind the confirmed adopter a day before the pickup
// window closes; once it has closed, close the request and send the animal
// to the shelter if it has room, or flag it for referral if the shelter is
// full (Rescue Details shows a Refer button).
exports.followUpAdopterPickups = onSchedule('every 30 minutes', async () => {
  const nowMs = Date.now();
  const snap = await db.collection('cases')
    .where('adopterPickup.collectedAt', '==', null)
    .where('adopterPickup.missedAt', '==', null)
    .get();
  for (const doc of snap.docs) {
    const c = doc.data();
    const p = c.adopterPickup || {};
    const step = rescueAdoption.pickupStep({...p, deadlineMs: millisOf(p.deadline) || null}, nowMs);
    try {
      if (step === 'remind') {
        await doc.ref.update({'adopterPickup.reminderSentAt': admin.firestore.FieldValue.serverTimestamp()});
        await notifyAdopter(p.adopterId, {
          title: 'Pickup reminder',
          body: `Please collect the animal at ${p.place || 'the clinic'} within ${rescueAdoption.PICKUP_REMINDER_HOURS} hours, ` +
            'or your adoption request will be closed.',
          data: {type: 'rescue_adoption_pickup_reminder', caseId: doc.id},
        });
        continue;
      }
      if (step !== 'missed') continue;

      const orgId = c.organizationId || null;
      const incoming = Array.isArray(p.animalIndexes) && p.animalIndexes.length ? p.animalIndexes.length : 1;
      const outcome = rescueAdoption.missedPickupOutcome({
        capacity: await shelterCapacityOf(orgId),
        housed: await housedCountOf(orgId),
        incoming,
      });
      const done = await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists) return false;
        const fresh = s.data();
        const fp = fresh.adopterPickup || {};
        if (rescueAdoption.pickupStep({...fp, deadlineMs: millisOf(fp.deadline) || null}, Date.now()) !== 'missed') return false;
        const now = admin.firestore.Timestamp.now();
        const animals = rescueAdoption.animalsAfterMissedPickup(fresh.animals, fp.animalIndexes || null, outcome, now);
        const line = outcome === 'shelter' ?
          'The adopter did not collect the animal in time. It goes to the shelter (Intake).' :
          'The adopter did not collect the animal in time and the shelter is full. Refer the animal to another organization.';
        tx.update(doc.ref, {
          'adopterPickup.missedAt': now,
          'adopterPickup.missedOutcome': outcome,
          'status': rescueAdoption.caseStatusAfterMissedPickup(animals, outcome),
          ...(animals.length ? {animals, ...rescueAdoption.stageSummary(animals)} : {}),
          ...(outcome === 'refer' ? {needsReferral: {reason: 'adopter_pickup_missed_shelter_full', at: now}} : {}),
          statusHistory: admin.firestore.FieldValue.arrayUnion({status: line, timestamp: now}),
        });
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'adopter_pickup_missed',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          details: {outcome, applicationId: fp.applicationId || null},
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (fp.applicationId) {
          tx.update(db.collection('adoptions').doc(fp.applicationId), {
            status: 'withdrawn',
            withdrawnAt: now,
            withdrawnBy: 'system',
            withdrawalReason: `Not collected within the ${rescueAdoption.PICKUP_WINDOW_HOURS}-hour pickup window.`,
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: 'Closed: the animal was not collected within the pickup window.', timestamp: now,
            }),
          });
        }
        return true;
      });
      if (!done) continue;
      await notifyAdopter(p.adopterId, {
        title: 'Adoption request closed',
        body: `The animal was not collected within ${rescueAdoption.PICKUP_WINDOW_HOURS} hours, so your adoption request was closed.`,
        data: {type: 'rescue_adoption_closed', caseId: doc.id},
      });
      await notifyStaff(await orgStaffUids(orgId, {anyOf: ['adoptions', 'rescue']}), {
        title: outcome === 'shelter' ? 'Pickup missed: animal goes to the shelter' : 'Pickup missed: shelter full, refer',
        body: outcome === 'shelter' ?
          'The adopter did not collect the animal in time. Arrange its intake to the shelter on Intake Details.' :
          'The adopter did not collect the animal in time and the shelter is full. Refer it from Rescue Details.',
        data: {type: 'rescue_adoption_pickup_missed', caseId: doc.id},
      });
    } catch (e) {
      console.error('[followUpAdopterPickups] failed for', doc.ref.path, e);
    }
  }
});

// ---- Critical reports left unreviewed ---------------------
//
// Every 5 minutes: a Critical report still in review after the threshold
// (organizations/{orgId}/settings/shelter.criticalEscalationMinutes, default
// 30) pushes every admin of the organizations covering it, once, suggesting
// they review it now or refer it. Decisions in critical_escalation_rules.js.
// Index: cases (urgency, status, createdAt).

const criticalEscalation = require('./critical_escalation_rules');

exports.escalateCriticalReports = onSchedule('every 5 minutes', async () => {
  const nowMs = Date.now();
  const snap = await db.collection('cases')
    .where('urgency', '==', 'Critical')
    .where('status', 'in', criticalEscalation.REVIEW_STATUSES)
    .where('createdAt', '<=', admin.firestore.Timestamp.fromMillis(nowMs - 60 * 1000))
    .get();
  const thresholds = new Map();
  async function thresholdOf(orgId) {
    if (!thresholds.has(orgId)) {
      const s = await db.collection('organizations').doc(orgId).collection('settings').doc('shelter').get();
      thresholds.set(orgId, criticalEscalation.escalationMinutes(s.exists ? s.get('criticalEscalationMinutes') : null));
    }
    return thresholds.get(orgId);
  }
  for (const doc of snap.docs) {
    const c = doc.data();
    const orgIds = criticalEscalation.escalationOrgIds(c);
    if (!orgIds.length) continue;
    const minutes = Math.min(...(await Promise.all(orgIds.map(thresholdOf))));
    const createdAtMs = millisOf(c.createdAt);
    if (!criticalEscalation.escalationDue(c, {createdAtMs, nowMs, thresholdMinutes: minutes})) continue;
    try {
      const claimed = await db.runTransaction(async (tx) => {
        const s = await tx.get(doc.ref);
        if (!s.exists || !criticalEscalation.escalationDue(s.data(), {createdAtMs, nowMs, thresholdMinutes: minutes})) {
          return false;
        }
        tx.update(doc.ref, {criticalEscalatedAt: admin.firestore.FieldValue.serverTimestamp()});
        tx.set(doc.ref.collection('activityLogs').doc(), {
          action: 'critical_report_escalated',
          actorUid: null,
          actorName: 'System',
          actorRole: null,
          details: {waitedMinutes: Math.round((nowMs - createdAtMs) / 60000), organizationIds: orgIds},
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) continue;
      const admins = (await Promise.all(orgIds.map((id) => orgStaffUids(id, {adminsOnly: true})))).flat();
      await notifyStaff(admins, {
        title: 'URGENT: critical report not reviewed',
        body: `A critical rescue report has waited ${Math.round((nowMs - createdAtMs) / 60000)} minutes without review. ` +
          'Review it now, or refer it to another organization.',
        data: {type: 'critical_report_escalated', caseId: doc.id},
      });
    } catch (e) {
      console.error('[escalateCriticalReports] failed for', doc.ref.path, e);
    }
  }
});

// ---- Community Adoption check-in (Adoption gap 10) ------------------------
//
// Community Adoption stays light, but each claim gets one check-in two
// weeks later (communityAdoptionCheckIns/{id}, same id as the claim). The
// adopter answers from Home with a photo and a line; staff of the
// organizations in the area see every claim and its check-in under
// Adoptions → Community adoptions. Decisions in community_checkin_rules.js.

const communityCheckIn = require('./community_checkin_rules');

exports.scheduleCommunityAdoptionCheckIn = onDocumentCreated('communityAdoptions/{adoptionId}', async (event) => {
  const a = event.data && event.data.data();
  if (!a || !a.adopterId) return;
  const caseSnap = a.sourceCaseId ? await db.collection('cases').doc(a.sourceCaseId).get() : null;
  const claimedAtMs = millisOf(a.createdAt) || Date.now();
  await db.collection('communityAdoptionCheckIns').doc(event.params.adoptionId).set({
    communityAdoptionId: event.params.adoptionId,
    caseId: a.sourceCaseId || null,
    adopterId: a.adopterId,
    adopterName: a.adopterName || null,
    animalName: a.name || null,
    species: a.species || null,
    address: a.address || null,
    organizationIds: communityCheckIn.checkInOrgIds(caseSnap && caseSnap.exists ? caseSnap.data() : null, a),
    status: 'scheduled',
    dueAt: admin.firestore.Timestamp.fromMillis(communityCheckIn.checkInDueAtMs(claimedAtMs)),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

// Daily 09:30 Manila: ask each adopter whose check-in is due.
// Index: communityAdoptionCheckIns (status, dueAt).
exports.sendCommunityAdoptionCheckIns = onSchedule({schedule: '30 9 * * *', timeZone: 'Asia/Manila'}, async () => {
  const nowMs = Date.now();
  const snap = await db.collection('communityAdoptionCheckIns')
    .where('status', '==', 'scheduled')
    .where('dueAt', '<=', admin.firestore.Timestamp.fromMillis(nowMs))
    .get();
  for (const doc of snap.docs) {
    const c = doc.data();
    if (!communityCheckIn.checkInRequestDue({...c, dueAtMs: millisOf(c.dueAt)}, nowMs)) continue;
    try {
      await doc.ref.update({status: 'requested', requestedAt: admin.firestore.FieldValue.serverTimestamp()});
      await db.collection('users').doc(c.adopterId).collection('notifications').add({
        title: 'How is your adopted animal doing?',
        message: 'It has been two weeks since your Community Adoption. Please send a quick check-in with a photo from Home.',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        type: 'community_adoption_checkin',
        caseId: c.caseId || null,
      });
      await safeNotifyUser({
        uid: c.adopterId,
        title: 'How is your adopted animal doing?',
        body: 'Please send a quick check-in with a photo from the Home screen.',
        data: {type: 'community_adoption_checkin', checkInId: doc.id},
      });
    } catch (e) {
      console.error('[sendCommunityAdoptionCheckIns] failed for', doc.ref.path, e);
    }
  }
});

// ---- Dashboard digest, critical pushes, monthly analytics summaries ------
// (Dashboard gaps 6 and 7, Analytics gap 6). See functions/dashboard_ops.js.
Object.assign(exports, require('./dashboard_ops')({
  db,
  orgStaffUids,
  notifyStaff,
  openFollowUpStatuses: OPEN_FOLLOW_UP_STATUSES,
}));

// ---- Lost/found pet matching ---------------------------------------------
// Scores new lost/found reports against open ones and saves possibleMatches.
// See functions/pet_matching.js and functions/pet_match_rules.js.
Object.assign(exports, require('./pet_matching')({db, safeNotifyUser}));
