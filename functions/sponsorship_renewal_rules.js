// Monthly auto-renewal of sponsorships. Pure rules (no Firebase) so
// `node --test` can check them; paymongo.js and campaigns.js use them.
//
// Payments go through PayMongo checkout (GCash, Maya, card, ...) with no
// saved payment method, so nothing is charged without the sponsor. An
// auto-renewing sponsorship instead continues month after month by default:
// `noticeDays` before each month ends the sponsor is sent that month's
// payment (no "continue?" question), and it only ends if the payment is
// still missing `graceDays` after the month ended, or the sponsor stops it.
// Listings set this on the admin sponsorship form
// (donation_admin_create.dart); listings saved before have it on with the
// defaults below.

const DAY_MS = 86400000;

const NOTICE_DAY_CHOICES = [1, 3, 5, 7];
const GRACE_DAY_CHOICES = [0, 3, 5, 7];
const DEFAULT_NOTICE_DAYS = 3;
const DEFAULT_GRACE_DAYS = 3;
/// The renewal reminder query looks this far ahead; per listing it is
/// narrowed to that listing's own notice days.
const MAX_NOTICE_DAYS = Math.max(...NOTICE_DAY_CHOICES);

/// A listing's renewal settings, with defaults for listings saved before
/// the settings existed. A listing that doesn't auto-renew asks the
/// sponsor whether to continue and has no grace period.
function renewalSettings(campaign) {
  const c = campaign || {};
  const autoRenew = c.autoRenew !== false;
  const noticeDays = NOTICE_DAY_CHOICES.includes(c.renewalNoticeDays) ? c.renewalNoticeDays : DEFAULT_NOTICE_DAYS;
  const graceDays = !autoRenew ? 0 :
    GRACE_DAY_CHOICES.includes(c.renewalGraceDays) ? c.renewalGraceDays : DEFAULT_GRACE_DAYS;
  return {autoRenew, noticeDays, graceDays};
}

/// Checks the admin form's settings for saveCampaign. Returns {value} or
/// {error}.
function parseRenewalSettings(data) {
  const d = data || {};
  if (d.autoRenew !== undefined && typeof d.autoRenew !== 'boolean') return {error: 'Choose whether it renews monthly.'};
  const autoRenew = d.autoRenew !== false;
  const notice = d.renewalNoticeDays === undefined || d.renewalNoticeDays === null ?
    DEFAULT_NOTICE_DAYS : d.renewalNoticeDays;
  if (!NOTICE_DAY_CHOICES.includes(notice)) {
    return {error: `Send the payment notice ${NOTICE_DAY_CHOICES.join(', ')} days before the month ends.`};
  }
  const grace = d.renewalGraceDays === undefined || d.renewalGraceDays === null ?
    DEFAULT_GRACE_DAYS : d.renewalGraceDays;
  if (!GRACE_DAY_CHOICES.includes(grace)) {
    return {error: `Allow ${GRACE_DAY_CHOICES.join(', ')} days to pay after the month ends.`};
  }
  return {value: {autoRenew, renewalNoticeDays: notice, renewalGraceDays: autoRenew ? grace : 0}};
}

/// Whether the reminder for a month ending at `dueMs` goes out now.
function reminderDue({dueMs, nowMs, settings}) {
  return dueMs > nowMs && dueMs - nowMs <= settings.noticeDays * DAY_MS;
}

/// Whether a sponsorship whose month ended at `dueMs` lapses now: at the
/// end of the month, or once the grace period after it has passed.
function lapseDue({dueMs, nowMs, settings}) {
  return nowMs >= dueMs + settings.graceDays * DAY_MS;
}

/// Whether a payment made now continues a sponsorship whose month ends (or
/// ended) at `dueMs` — before it ends, or within the grace period after.
function continuesSponsorship({dueMs, nowMs, settings}) {
  return nowMs < dueMs + settings.graceDays * DAY_MS;
}

module.exports = {
  DAY_MS,
  NOTICE_DAY_CHOICES,
  GRACE_DAY_CHOICES,
  DEFAULT_NOTICE_DAYS,
  DEFAULT_GRACE_DAYS,
  MAX_NOTICE_DAYS,
  renewalSettings,
  parseRenewalSettings,
  reminderDue,
  lapseDue,
  continuesSponsorship,
};
