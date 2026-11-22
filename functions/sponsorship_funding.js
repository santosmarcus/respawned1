// Keeps a sponsorship listing's funding status current (see
// sponsorship_funding_rules.js). Runs on every write to campaigns/{id}, so
// any money change (donation, refund, reversal, expense, void, cash-out,
// transfer, monthly amount edit) re-evaluates it. Writes only when
// something changed, so its own write doesn't loop.
//
// Mirrors the result onto animals/{animalId}.sponsorshipFunding (copied to
// publicAnimals by public_animals.js) so the animal record and its public
// profile show the same status as the listing.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const rules = require('./sponsorship_funding_rules');

exports.syncSponsorshipFunding = onDocumentWritten('campaigns/{campaignId}', async (event) => {
  const after = event.data && event.data.after.exists ? event.data.after.data() : null;
  const before = event.data && event.data.before.exists ? event.data.before.data() : null;
  const c = after || before;
  if (!c || (c.type || 'donation') !== 'sponsorship') return;
  const db = admin.firestore();
  const campaignId = event.params.campaignId;
  const now = admin.firestore.FieldValue.serverTimestamp();

  if (after) {
    const update = rules.listingFundingUpdate(after);
    if (update) {
      const changedStatus = after.fundingStatus !== update.fundingStatus;
      await event.data.after.ref.update({
        ...update,
        ...(changedStatus ? {fundingStatusChangedAt: now} : {}),
      });
    }
  }

  const animalId = (after && after.animalId) || (before && before.animalId);
  if (typeof animalId !== 'string' || !animalId) return;
  const animalRef = db.collection('animals').doc(animalId);
  const summary = after ? rules.animalFundingSummary(campaignId, after) : null;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(animalRef);
    if (!snap.exists) return;
    const current = snap.get('sponsorshipFunding');
    if (summary) {
      const same = current && current.campaignId === summary.campaignId && current.status === summary.status &&
        current.target === summary.target && current.available === summary.available;
      if (!same) tx.update(animalRef, {sponsorshipFunding: {...summary, updatedAt: now}});
    } else if (current && current.campaignId === campaignId) {
      // This listing ended or was deleted: the animal has no live sponsorship.
      tx.update(animalRef, {sponsorshipFunding: admin.firestore.FieldValue.delete()});
    }
  });
});
