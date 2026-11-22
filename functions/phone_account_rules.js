// Pure helpers for one-number-one-account (functions/phone_accounts.js),
// kept free of Firestore so they can be unit tested.

/**
 * The ways a Philippine mobile number may be stored in users/{uid}.phone
 * (onboarding saved '+639XXXXXXXXX'; older profile edits saved what was
 * typed). Returns [] for anything that isn't a PH mobile number.
 *
 * @param {string} phone
 * @return {string[]}
 */
function phoneVariants(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  let local = null; // 9XXXXXXXXX
  if (/^9\d{9}$/.test(digits)) local = digits;
  else if (/^09\d{9}$/.test(digits)) local = digits.slice(1);
  else if (/^639\d{9}$/.test(digits)) local = digits.slice(2);
  if (!local) return [];
  return [`+63${local}`, `63${local}`, `0${local}`, local, `+63 ${local}`];
}

/**
 * Enough of an email for its owner to recognise it, e.g. 'ma***@gmail.com'.
 *
 * @param {string} email
 * @return {string}
 */
function maskEmail(email) {
  const e = String(email || '').trim();
  const at = e.indexOf('@');
  if (at < 1) return '';
  const name = e.slice(0, at);
  return `${name.slice(0, Math.min(2, name.length))}***${e.slice(at)}`;
}

/**
 * What to do with a signed-in account whose verified number is P.
 *
 * @param {object} s
 * @param {boolean} s.callerFinished the caller's profile has a role
 * @param {string[]} s.callerProviders the caller's Auth provider ids
 * @param {Array<{email: string}>} s.holders other finished accounts whose
 *   profile lists P
 * @return {{action: 'keep'|'unlinkPhone'|'deleteAccount', hint?: string}}
 */
function phoneSignUpDecision({callerFinished, callerProviders = [], holders = []}) {
  // Only a new sign-up is stopped; an existing account keeps a number it
  // verified (older profiles listed numbers nobody confirmed).
  if (callerFinished || holders.length === 0) return {action: 'keep'};
  const hint = holders.map((h) => maskEmail(h.email)).find((m) => m) || '';
  const phoneOnly = callerProviders.length > 0 && callerProviders.every((p) => p === 'phone');
  return {action: phoneOnly ? 'deleteAccount' : 'unlinkPhone', hint};
}

module.exports = {phoneVariants, maskEmail, phoneSignUpDecision};
