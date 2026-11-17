// Pure helpers for the active sponsor count on a sponsorship listing
// (campaigns/{id}.activeSponsorCount). Used by functions/sponsor_counts.js.
// No Firebase here, so `node --test` checks them.

/// A sponsorship record still covers the animal: paid ('active'), or the
/// sponsor chose to stop ('cancelled') but the paid 30 days haven't run out.
function coversNow(d, nowMs) {
  if (!d || d.type !== 'sponsorship') return false;
  if (!['active', 'cancelled'].includes(d.sponsorshipStatus)) return false;
  const until = d.nextChargeDate && typeof d.nextChargeDate.toMillis === 'function' ?
    d.nextChargeDate.toMillis() : (typeof d.nextChargeDateMs === 'number' ? d.nextChargeDateMs : null);
  return until !== null && until > nowMs;
}

/// People currently sponsoring: distinct sponsors with a record that still
/// covers the animal (a renewal is a second record for the same person).
function countActiveSponsors(records, nowMs) {
  const people = new Set();
  for (const d of records) {
    if (coversNow(d, nowMs) && typeof d.userId === 'string' && d.userId) people.add(d.userId);
  }
  return people.size;
}

module.exports = {coversNow, countActiveSponsors};
