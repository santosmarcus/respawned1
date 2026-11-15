// Volunteer recognition.
//
// Organization staff mark attendance on `events/{eventId}/registrations/{uid}`
// (VolunteerEventRepository.setAttendance). Whenever a registration changes,
// this recounts the volunteer's attended events and writes
// `users/{uid}.volunteerStats`: counts, dates and the badges earned. The
// app shows the badges in History and on the volunteer's profile.
//
// Only staff-written registrations count. The volunteer's own copy under
// users/{uid}/volunteerRegistrations is used just to find which events to
// check, since any signed-in user can write that subcollection.
// firestore.rules stops users from writing volunteerStats themselves and
// from creating a registration that is already marked attended.
//
// Existing volunteers: scripts/backfill_volunteer_stats.js.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// Keep in step with VolunteerBadge in
// lib/core/models/volunteer/volunteer_stats.dart (labels live there).
const EVENT_BADGES = [
  {id: 'first_event', minEvents: 1},
  {id: 'helping_paw', minEvents: 5},
  {id: 'regular', minEvents: 10},
  {id: 'champion', minEvents: 25},
];
const COMMUNITY_BADGE = {id: 'community_helper', minOrganizations: 3};

/// Badge ids earned for these counts, lowest tier first.
function badgesFor({attendedCount, organizationCount}) {
  const out = EVENT_BADGES.filter((b) => attendedCount >= b.minEvents).map((b) => b.id);
  if (organizationCount >= COMMUNITY_BADGE.minOrganizations) out.push(COMMUNITY_BADGE.id);
  return out;
}

/// Recounts one volunteer from the staff-written registrations and returns
/// the volunteerStats map.
async function computeVolunteerStats(db, uid, extraEventIds = []) {
  const copies = await db.collection('users').doc(uid).collection('volunteerRegistrations').get();
  const eventIds = new Set([...copies.docs.map((d) => d.id), ...extraEventIds]);
  const orgs = new Set();
  let attendedCount = 0;
  let first = null;
  let last = null;
  for (const eventId of eventIds) {
    const eventRef = db.collection('events').doc(eventId);
    const [reg, event] = await Promise.all([eventRef.collection('registrations').doc(uid).get(), eventRef.get()]);
    if (!reg.exists || reg.get('attended') !== true || !event.exists) continue;
    attendedCount++;
    const orgId = event.get('organizationId');
    if (typeof orgId === 'string' && orgId) orgs.add(orgId);
    const startAt = event.get('startAt');
    const at = startAt && typeof startAt.toMillis === 'function' ? startAt : null;
    if (at) {
      if (!first || at.toMillis() < first.toMillis()) first = at;
      if (!last || at.toMillis() > last.toMillis()) last = at;
    }
  }
  const organizationCount = orgs.size;
  return {
    attendedCount,
    organizationCount,
    firstAttendedAt: first,
    lastAttendedAt: last,
    badges: badgesFor({attendedCount, organizationCount}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

exports.badgesFor = badgesFor;
exports.computeVolunteerStats = computeVolunteerStats;

exports.syncVolunteerStats = onDocumentWritten('events/{eventId}/registrations/{uid}', async (event) => {
  const before = event.data && event.data.before.exists ? event.data.before.get('attended') : undefined;
  const after = event.data && event.data.after.exists ? event.data.after.get('attended') : undefined;
  // Sign-ups and edits that don't touch attendance change nothing.
  if (before === after) return;
  const {uid, eventId} = event.params;
  const db = admin.firestore();
  const user = db.collection('users').doc(uid);
  if (!(await user.get()).exists) return;
  const stats = await computeVolunteerStats(db, uid, [eventId]);
  await user.set({volunteerStats: stats}, {merge: true});
});
