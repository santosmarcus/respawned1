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
const ORG_STAFF_ROLES = ['organization', 'ngo_staff', 'admin'];

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

  // Firestore `in` accepts at most 30 values.
  const tokens = new Set();
  for (let i = 0; i < matched.length; i += 30) {
    const staffSnap = await db
      .collection('users')
      .where('organizationId', 'in', matched.slice(i, i + 30))
      .get();
    staffSnap.forEach((u) => {
      const d = u.data();
      if (u.id === c.reporterId) return;
      if (!ORG_STAFF_ROLES.includes(d.role)) return;
      if (!d.fcmToken || !userWantsCategory(d, NOTIFY_CATEGORY.newCase)) return;
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

// Admin campaign/sponsorship management, allocations & reallocation — see functions/campaigns.js.
Object.assign(exports, require('./campaigns'));