// How many people sponsor each animal right now, kept on the listing as
// campaigns/{id}.activeSponsorCount. Donation records are private to each
// donor, so the app can't count other sponsors itself; Sponsorship Details
// reads this number instead.
//
// Not a functions module: no new Cloud Function is deployed for it.
// paymongo.js calls recountActiveSponsors right after a sponsorship payment
// is recorded, and lapseExpiredSponsorships (the existing daily job) calls
// recountAllSponsorships so sponsorships that ran out, were stopped or were
// refunded drop off within a day.
// Index: donations (campaignId, type, nextChargeDate).

const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const {countActiveSponsors} = require('./sponsor_count_rules');

// index.js calls admin.initializeApp() before requiring paymongo.js.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

async function recountActiveSponsors(campaignId) {
  if (typeof campaignId !== 'string' || !campaignId) return;
  const now = Date.now();
  const snap = await db.collection('donations')
      .where('campaignId', '==', campaignId)
      .where('type', '==', 'sponsorship')
      .where('nextChargeDate', '>', Timestamp.fromMillis(now))
      .get();
  const count = countActiveSponsors(snap.docs.map((d) => d.data()), now);
  const ref = db.collection('campaigns').doc(campaignId);
  const current = await ref.get();
  if (!current.exists || current.get('activeSponsorCount') === count) return;
  await ref.update({activeSponsorCount: count, activeSponsorCountAt: FieldValue.serverTimestamp()});
}

async function recountAllSponsorships() {
  const listings = await db.collection('campaigns').where('type', '==', 'sponsorship').get();
  for (const c of listings.docs) {
    try {
      await recountActiveSponsors(c.id);
    } catch (e) {
      logger.error('recountActiveSponsors failed', {campaignId: c.id, message: e.message});
    }
  }
}

module.exports = {recountActiveSponsors, recountAllSponsorships};
