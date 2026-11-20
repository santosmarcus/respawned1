// One mobile number, one account.
//
// Firebase Auth already keeps an email or a verified phone number on a
// single account: email sign-ups fail with email-already-in-use, and the
// app now verifies the number typed during onboarding with an SMS code and
// adds it to the account (updatePhoneNumber), which fails with
// credential-already-in-use when another account has it. Signing in with
// that number later opens the same account.
//
// Older profiles listed a number nobody verified (users/{uid}.phone). A new
// sign-up must not take a number such an account already lists, or the
// same person ends up with two accounts:
//
// checkSignUpPhone: called by the app right after a number is verified on
// an account that hasn't finished onboarding. When another finished account
// lists the number, a phone-only sign-up is removed (it has no data yet)
// and an email/Google sign-up loses the number; the result names the other
// account's masked email so the person can sign in there instead.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {phoneVariants, phoneSignUpDecision} = require('./phone_account_rules');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();

function finished(data) {
  const role = data && data.role;
  return typeof role === 'string' && role !== '';
}

exports.checkSignUpPhone = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in again.');

  const authUser = await admin.auth().getUser(uid);
  const phone = authUser.phoneNumber || '';
  const variants = phoneVariants(phone);
  if (variants.length === 0) return {ok: true};

  const userRef = db.collection('users').doc(uid);
  const me = await userRef.get();
  const callerFinished = me.exists && finished(me.data());
  if (callerFinished) return {ok: true};

  const snap = await db.collection('users').where('phone', 'in', variants).limit(10).get();
  const holders = snap.docs
      .filter((d) => d.id !== uid && finished(d.data()))
      .map((d) => ({email: d.get('email') || ''}));

  const decision = phoneSignUpDecision({
    callerFinished,
    callerProviders: authUser.providerData.map((p) => p.providerId),
    holders,
  });
  if (decision.action === 'keep') return {ok: true};

  if (decision.action === 'deleteAccount') {
    await db.recursiveDelete(userRef);
    await admin.auth().deleteUser(uid);
  } else {
    await admin.auth().updateUser(uid, {phoneNumber: null});
    if (me.exists && me.get('phone')) await userRef.update({phone: ''});
  }
  return {ok: false, removed: decision.action === 'deleteAccount', accountHint: decision.hint};
});
