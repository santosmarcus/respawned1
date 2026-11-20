// Lost/found pet matching.
//
//  - scorePetAlertMatches: when a lost or found report (petAlerts) is
//    created, scores it against open reports of the opposite type and the
//    same species (functions/pet_match_rules.js), saves every pair at or
//    above MIN_SCORE to possibleMatches, and pushes the lost pet's owner
//    about strong matches.
//
// One possibleMatches doc per lost report / found report group, with the
// fixed ID `${lostAlertId}_${foundAlertId}`. A found report with several
// animals is one petAlerts doc per animal sharing a groupId; each animal is
// scored on its own and the group's match keeps the best animal's score.
// The tracking page opens a found report by its groupId, so foundAlertId is
// the groupId (foundAnimalAlertId names the animal that scored best).
//
// index.js passes in its helpers: db and safeNotifyUser.

const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const {scorePair, matchStrength, MAX_DAYS} = require('./pet_match_rules');

const DAY_MS = 24 * 60 * 60 * 1000;
const CANDIDATE_LIMIT = 300;

// The id the tracking page uses for a report: its group's first doc.
// Lost reports and the first animal of a found report have no groupId yet
// when they are created (the app backfills it), so they fall back to their
// own id, which is what the groupId becomes.
function reportId(id, data) {
  return data.groupId || id;
}

module.exports = ({db, safeNotifyUser}) => {
  const scorePetAlertMatches = onDocumentCreated('petAlerts/{alertId}', async (event) => {
    const snap = event.data;
    if (!snap) return;
    const me = snap.data();
    const myId = event.params.alertId;

    if (me.type !== 'lost' && me.type !== 'found') return;
    if (typeof me.lat !== 'number' || typeof me.lng !== 'number') return;
    if (!me.species) return;

    const opposite = me.type === 'lost' ? 'found' : 'lost';
    const since = admin.firestore.Timestamp.fromMillis(Date.now() - MAX_DAYS * DAY_MS);

    const pool = await db.collection('petAlerts')
      .where('type', '==', opposite)
      .where('status', '==', 'open')
      .where('species', '==', me.species)
      .where('createdAt', '>=', since)
      .limit(CANDIDATE_LIMIT)
      .get();

    // Best score per lost/found-group pair (several found animals in one
    // group can match the same lost pet).
    const best = new Map();
    for (const doc of pool.docs) {
      const other = doc.data();
      if (other.reporterId && other.reporterId === me.reporterId) continue;

      const lostSide = me.type === 'lost'
        ? {id: myId, data: me}
        : {id: doc.id, data: other};
      const foundSide = me.type === 'found'
        ? {id: myId, data: me}
        : {id: doc.id, data: other};

      const result = scorePair(lostSide.data, foundSide.data);
      if (!result) continue;
      const strength = matchStrength(result.score);
      if (!strength) continue;

      const lostAlertId = reportId(lostSide.id, lostSide.data);
      const foundAlertId = reportId(foundSide.id, foundSide.data);
      const key = `${lostAlertId}_${foundAlertId}`;
      const prev = best.get(key);
      if (prev && prev.score >= result.score) continue;

      best.set(key, {
        key,
        lostAlertId,
        foundAlertId,
        foundAnimalAlertId: foundSide.id,
        lostReporterId: lostSide.data.reporterId || null,
        foundReporterId: foundSide.data.reporterId || null,
        lostPetName: lostSide.data.petName || null,
        species: me.species,
        score: result.score,
        breakdown: result.breakdown,
        strength,
      });
    }

    for (const m of best.values()) {
      let notifyOwner = false;
      try {
        notifyOwner = await saveMatch(m);
      } catch (e) {
        console.error('[scorePetAlertMatches] could not save', m.key, e);
        continue;
      }
      if (notifyOwner) await notifyOwnerOfMatch(m);
    }
  });

  // Creates the match, or raises an existing one's score. Never lowers a
  // score and never touches a status staff already set. Returns true when
  // the match has just become strong (so the owner hears about it once).
  async function saveMatch(m) {
    const ref = db.collection('possibleMatches').doc(m.key);
    return db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      const now = admin.firestore.FieldValue.serverTimestamp();
      const fields = {
        lostAlertId: m.lostAlertId,
        foundAlertId: m.foundAlertId,
        foundAnimalAlertId: m.foundAnimalAlertId,
        lostReporterId: m.lostReporterId,
        foundReporterId: m.foundReporterId,
        species: m.species,
        score: m.score,
        breakdown: m.breakdown,
        strength: m.strength,
        scoredAt: now,
      };

      if (!existing.exists) {
        tx.set(ref, {
          ...fields,
          status: 'pending_review',
          createdAt: now,
          serverCreatedAt: now,
        });
        return m.strength === 'strong';
      }

      const prev = existing.data();
      if (typeof prev.score === 'number' && prev.score >= m.score) return false;
      tx.update(ref, fields);
      return m.strength === 'strong' && prev.strength !== 'strong';
    });
  }

  async function notifyOwnerOfMatch(m) {
    if (!m.lostReporterId) return;
    const species = (m.species || 'pet').toString().toLowerCase();
    const name = m.lostPetName || `your ${species}`;
    const title = 'Possible match for your lost pet';
    const body = m.breakdown && typeof m.breakdown.distanceKm === 'number'
      ? `A found ${species} ${m.breakdown.distanceKm} km away looks a lot like ${name}. Tap to compare.`
      : `A found ${species} looks a lot like ${name}. Tap to compare.`;

    try {
      await db.collection('users').doc(m.lostReporterId).collection('notifications').add({
        title,
        message: body,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        type: 'pet_match',
        alertId: m.lostAlertId,
        matchId: m.key,
      });
    } catch (e) {
      console.warn('[scorePetAlertMatches] in-app notification failed', m.lostReporterId, e.message);
    }

    await safeNotifyUser({
      uid: m.lostReporterId,
      title,
      body,
      data: {type: 'pet_match', alertId: m.lostAlertId, matchId: m.key},
    });
  }

  return {scorePetAlertMatches};
};
