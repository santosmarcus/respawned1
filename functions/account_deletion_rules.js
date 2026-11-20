// Pure checks for account removal (functions/account_deletion.js), kept free
// of Firestore so they can be unit tested.

/**
 * Why this account can't be deleted yet, or null when it can.
 *
 * @param {object} s
 * @param {Array<{name: string, status: string, kind?: string,
 *   activeCaseCount?: number, animalsInCareCount?: number}>} s.ownedOrgs
 *   organizations whose ownerId is this account (kind 'independent': an
 *   independent rescuer, with its open cases and animals in care)
 * @param {boolean} s.isOrgAdmin this account is an active Admin of its org
 * @param {number} s.activeAdminCount active Admins in that org (this one included)
 * @param {string|null} s.transportStatus status of this account's newest
 *   transport offer (users/{uid}.transportStatus.status), if any
 * @param {string} s.subject 'self' (deleting your own) or 'other' (a system admin)
 * @return {string|null}
 */
function deletionBlocker({
  ownedOrgs = [], isOrgAdmin = false, activeAdminCount = 0, transportStatus = null, subject = 'self',
}) {
  const self = subject === 'self';
  const live = ownedOrgs.filter((o) => o.status !== 'draft');
  // An independent rescuer still holding cases or animals must hand them
  // over first, whoever asks; it is then closed by a system admin.
  const holding = live.find((o) => o.kind === 'independent' &&
    ((o.activeCaseCount || 0) > 0 || (o.animalsInCareCount || 0) > 0));
  if (holding) {
    return `${self ? 'You still have' : 'This rescuer still has'} ${holding.activeCaseCount || 0} active case(s) ` +
      `and ${holding.animalsInCareCount || 0} animal(s) in care. Refer the cases and transfer or rehome the ` +
      'animals first, then a system admin can close the account.';
  }
  if (live.length > 0) {
    return `${self ? 'You own' : 'This account owns'} ${live.map((o) => o.name || 'an organization').join(', ')}. ` +
      'An organization owner\'s account can\'t be deleted from the app.';
  }
  if (isOrgAdmin && activeAdminCount <= 1) {
    return self ?
      'You are your organization\'s only Admin. Make another member an Admin first.' :
      'This account is its organization\'s only Admin. Another member must be made an Admin first.';
  }
  if (transportStatus === 'accepted' || transportStatus === 'pending') {
    return self ?
      'You have an active or pending transport. Finish it or decline it first.' :
      'This account has an active or pending transport. Disable it instead, or wait until it ends.';
  }
  return null;
}

module.exports = {deletionBlocker};
