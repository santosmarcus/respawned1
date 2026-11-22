import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:respawnd1/core/services/geofence_service.dart';
import 'package:respawnd1/core/services/notification_service.dart';
import 'package:respawnd1/features/generalhome/push_token_service.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';

ValueNotifier<AuthService> authService = ValueNotifier (AuthService());

/// An email belongs to one account: thrown when a phone sign-up adds an
/// email that another ResPAWnd account already uses.
class EmailTakenException implements Exception {
  final String message;
  const EmailTakenException._(this.message);

  static const instance = EmailTakenException._(
      'This email already has a ResPAWnd account. Log out and sign in with '
      'your email instead, or use a different email.');

  @override
  String toString() => message;
}

/// A mobile number belongs to one account. Thrown when the number someone
/// verified is already on another ResPAWnd account; [message] says which
/// (masked email) and what to do.
class PhoneTakenException implements Exception {
  final String message;
  const PhoneTakenException(this.message);

  /// The number is verified on another account (Firebase Auth refused it).
  static const linkedElsewhere = PhoneTakenException(
      'This number already has a ResPAWnd account. Log out and sign in with '
      'your number instead, or use a different number.');

  /// A new sign-up's number is listed on an existing account.
  factory PhoneTakenException.listedOn(String? accountHint) => PhoneTakenException(
      (accountHint != null && accountHint.isNotEmpty)
          ? 'This number is already on the ResPAWnd account $accountHint. '
              'Sign in with that account instead.'
          : 'This number is already on another ResPAWnd account. '
              'Sign in with that account instead.');

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogRepository _auditLog = AuditLogRepository();

  User? get currentUser => firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  /// Best-effort only (spec: audit writes never block/affect the real
  /// action) — called AFTER the credential is already established, so a
  /// failure here can never prevent or roll back a successful sign-in.
  ///
  /// Carries the user's organization (users/{uid}.organizationId): the Audit
  /// page only lists its own organization's entries, so logins written
  /// without it (every method, Google and phone included) never showed.
  Future<void> _logLogin(User? user, {required String method}) async {
    if (user == null) return;
    String? organizationId;
    String? role;
    String? name;
    try {
      final data = (await _firestore.collection('users').doc(user.uid).get()).data();
      organizationId = data?['organizationId'] as String?;
      role = data?['role'] as String?;
      final first = (data?['firstName'] as String?)?.trim() ?? '';
      final last = (data?['lastName'] as String?)?.trim() ?? '';
      name = '$first $last'.trim();
    } catch (_) {
      // Logged without the organization rather than not at all.
    }
    await _auditLog.log(
      category: AuditCategory.logins,
      action: 'Successful login',
      actorId: user.uid,
      actorEmail: user.email ?? user.phoneNumber,
      actorName: (name != null && name.isNotEmpty) ? name : (user.displayName ?? user.phoneNumber),
      actorRole: role,
      organizationId: organizationId,
      metadata: {
        'method': method,
        if (user.phoneNumber != null) 'phone': user.phoneNumber,
      },
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await firebaseAuth.signInWithEmailAndPassword(
        email: email, password: password);
    await _logLogin(credential.user, method: 'email_password');
    return credential;
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
    //required String name,
  }) async {
    final credential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email, password: password);

    //await credential.user!.updateDisplayName(name);

    try {
      // CREATE the doc with set() not update()
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'name': '',
        'firstName': '',
        'lastName': '',
        'email': email,
        'phone': '',
        'role': '',               // filled during onboarding
        'isVerified': false,
        'photoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The Auth account was created successfully — that's the part that
      // matters here. Don't fail the whole sign-up over a Firestore write
      // hiccup (e.g. a transient network error or rules check). AuthWrapper
      // treats a missing user doc exactly like an empty role and routes to
      // onboarding, where the profile gets written anyway. Swallowing this
      // also prevents the "email-already-in-use on every retry" loop that
      // happens when this used to throw and strand a role-less account.
    }

    // Best-effort: VerifyEmailScreen (shown by AuthWrapper until the address
    // is confirmed) can always resend it.
    try {
      await credential.user!.sendEmailVerification();
    } catch (e) {
      debugPrint('sendEmailVerification failed (non-fatal): $e');
    }

    return credential;
  }

  static bool _hasPassword(User user) => user.providerData.any((p) => p.providerId == 'password');

  /// The app-wide gate (AuthWrapper): email/password accounts must confirm
  /// their address before using the app. Google accounts arrive verified.
  /// Accounts that also sign in with a verified number aren't held here, so
  /// a mistyped email added to a phone account can still be corrected in
  /// Profile; Your Details waits for new phone sign-ups to confirm theirs.
  static bool needsEmailVerification(User user) =>
      !user.emailVerified && _hasPassword(user) && (user.phoneNumber ?? '').isEmpty;

  /// The account has an email sign-in whose address isn't confirmed yet.
  static bool hasUnconfirmedEmail(User user) => !user.emailVerified && _hasPassword(user);

  Future<void> sendEmailVerification() async {
    await firebaseAuth.currentUser?.sendEmailVerification();
  }

  /// Re-reads the signed-in user from Firebase Auth (emailVerified only
  /// changes after a reload) and reports whether verification is still owed.
  Future<bool> reloadAndCheckVerified() async {
    final user = firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    final fresh = firebaseAuth.currentUser;
    return fresh != null && !hasUnconfirmedEmail(fresh);
  }

  /// Sends a confirmation link to [newEmail]; the account's email only
  /// changes once that link is opened. Throws FirebaseAuthException
  /// 'requires-recent-login' when the session is too old — callers
  /// re-authenticate with [reauthenticateWithPassword] and retry.
  Future<void> requestEmailChange(String newEmail) async {
    final user = firebaseAuth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    await user.verifyBeforeUpdateEmail(newEmail);
  }

  Future<void> reauthenticateWithPassword(String password) async {
    final user = firebaseAuth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw StateError('Not signed in with an email.');
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Set when someone uses "Continue with Google" on the login screen with
  /// a Google account that has no finished ResPAWnd account yet (value: the
  /// account's email). EnterDetailsScreen shows "No account yet" once and
  /// clears it. A notifier because AuthWrapper may show that screen before
  /// sign-in returns here.
  static final ValueNotifier<String?> noAccountNotice = ValueNotifier(null);

  /// [fromLogin]: called from the login screen, where a missing account is
  /// reported ([noAccountNotice]) before leading on to create one.
  Future<UserCredential?> signInWithGoogle({bool fromLogin = false}) async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
    await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await firebaseAuth.signInWithCredential(credential);
    final user = userCredential.user!;
    final data = await _createUserDocIfNew(user);
    if (fromLogin && !hasCompletedOnboarding(data)) {
      noAccountNotice.value = (user.email?.isNotEmpty ?? false) ? user.email : 'this Google account';
    }
    await _logLogin(userCredential.user, method: 'google');
    return userCredential;
  }

  // Step 1: Send OTP
  Future<void> sendOtp({
    required String phoneNumber, // format: +639XXXXXXXXX
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    Function(UserCredential)? onAutoVerified,
  }) async {
    await firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verified on some Android devices without the user typing an
        // OTP. This callback fires later, outside the caller's try/catch,
        // so anything thrown in here must be caught locally and routed
        // through onError — otherwise it becomes an unhandled async
        // exception that only shows up in logcat, never on screen.
        try {
          final userCredential =
          await firebaseAuth.signInWithCredential(credential);
          await _afterPhoneSignIn(userCredential.user!);
          await _logLogin(userCredential.user, method: 'phone_otp');
          onAutoVerified?.call(userCredential);
        } on PhoneTakenException catch (e) {
          onError(e.message);
        } on FirebaseAuthException catch (e) {
          onError(e.message ?? 'Verification failed.');
        } catch (e) {
          onError('Something went wrong verifying your number. Please try again.');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'Verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // Step 2: Verify OTP
  Future<UserCredential?> verifyOtp({
    required String verificationId,
    required String otp,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    final userCredential = await firebaseAuth.signInWithCredential(credential);
    await _afterPhoneSignIn(userCredential.user!);
    await _logLogin(userCredential.user, method: 'phone_otp');
    return userCredential;
  }

  /// A phone sign-in that hasn't finished onboarding is a new sign-up: if an
  /// existing account already lists the number, the server removes this
  /// empty account and the person is pointed to the existing one. Throws
  /// [PhoneTakenException] (signed out) in that case.
  Future<void> _afterPhoneSignIn(User user) async {
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    if (!hasCompletedOnboarding(snapshot.data())) {
      String? hint;
      try {
        hint = await _checkSignUpPhone();
      } catch (_) {
        // Can't confirm the number is free: don't open a new account on it.
        await _signOutQuietly();
        rethrow;
      }
      if (hint != null) {
        await _signOutQuietly();
        throw PhoneTakenException.listedOn(hint);
      }
    }
    if (!snapshot.exists) await _createUserDoc(user);
  }

  Future<void> _signOutQuietly() async {
    try {
      await firebaseAuth.signOut();
    } catch (_) {}
  }

  /// functions/phone_accounts.js checkSignUpPhone. Returns null when the
  /// account may keep its number, else the other account's masked email
  /// ('' when it has none).
  Future<String?> _checkSignUpPhone() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('checkSignUpPhone')
        .call<Map<String, dynamic>>();
    final data = Map<String, dynamic>.from(result.data);
    if (data['ok'] == true) return null;
    return data['accountHint'] as String? ?? '';
  }

  /// Sends an SMS code to [phoneNumber] (+639XXXXXXXXX) to add it to the
  /// signed-in account. [onAutoVerified] gets the credential when Android
  /// reads the code itself; pass it to [addVerifiedPhone].
  Future<void> sendPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    await firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onAutoVerified,
      verificationFailed: (e) => onError(e.message ?? 'Verification failed.'),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  static PhoneAuthCredential phoneCredential(String verificationId, String code) =>
      PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);

  /// Makes the verified number this account's mobile number (and a way to
  /// sign in to it). Firebase Auth keeps a number on one account, so a
  /// number another account has fails with [PhoneTakenException]; so does a
  /// new sign-up's number that an existing account lists. On success the ID
  /// token is refreshed, since the profile rules only accept the number in
  /// it. Other failures are FirebaseAuthException (e.g.
  /// invalid-verification-code, session-expired).
  Future<String> addVerifiedPhone(PhoneAuthCredential credential) async {
    final user = firebaseAuth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    try {
      await user.updatePhoneNumber(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'account-exists-with-different-credential') {
        throw PhoneTakenException.linkedElsewhere;
      }
      rethrow;
    }
    final hint = await _checkSignUpPhone();
    try {
      await user.getIdToken(true);
      await user.reload();
    } on FirebaseAuthException {
      // The server removed this (empty, phone-only) account.
      await _signOutQuietly();
    }
    if (hint != null) throw PhoneTakenException.listedOn(hint);
    return firebaseAuth.currentUser?.phoneNumber ?? '';
  }

  /// Phone sign-ups add an email and password, so the account can sign in
  /// either way and the email, like the number, belongs to this account
  /// only (Firebase Auth refuses an email another account has:
  /// [EmailTakenException]). The address is confirmed by link afterwards
  /// (a verification email is sent; VerifyEmailScreen waits for it). Other
  /// failures are FirebaseAuthException (e.g. weak-password, invalid-email).
  Future<void> addEmailSignIn({required String email, required String password}) async {
    final user = firebaseAuth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final hasPassword = user.providerData.any((p) => p.providerId == 'password');
    if (hasPassword && (user.email ?? '').toLowerCase() == email.toLowerCase()) {
      return; // Already added (came back to this screen).
    }
    try {
      // A different address entered after coming back: replace it. Only
      // happens before onboarding is finished.
      if (hasPassword) await user.unlink('password');
      await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: password));
    } on FirebaseAuthException catch (e) {
      if (const {'email-already-in-use', 'credential-already-in-use', 'account-exists-with-different-credential'}
          .contains(e.code)) {
        throw EmailTakenException.instance;
      }
      rethrow;
    }
    await user.reload();
    await _firestore.collection('users').doc(user.uid).set({'email': email}, SetOptions(merge: true));
    try {
      await firebaseAuth.currentUser?.sendEmailVerification();
    } catch (e) {
      debugPrint('sendEmailVerification failed (non-fatal): $e');
    }
  }

  static String emailErrorMessage(Object e) {
    if (e is EmailTakenException) return e.message;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-email' => 'Please enter a valid email address.',
        'weak-password' => 'Please choose a stronger password.',
        'requires-recent-login' => 'Please log out and sign in again, then retry.',
        'too-many-requests' => 'Too many tries. Please wait a while and try again.',
        _ => e.message ?? 'Could not add your email. Please try again.',
      };
    }
    return 'Could not add your email. Please try again.';
  }

  static String phoneErrorMessage(Object e) {
    if (e is PhoneTakenException) return e.message;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-verification-code' => 'Invalid code. Please try again.',
        'session-expired' || 'code-expired' => 'That code expired. Send a new one.',
        'invalid-phone-number' => 'Please enter a valid mobile number.',
        'too-many-requests' => 'Too many tries. Please wait a while and try again.',
        'requires-recent-login' => 'Please sign out and sign in again, then retry.',
        _ => e.message ?? 'Could not verify your number. Please try again.',
      };
    }
    if (e is FirebaseFunctionsException) {
      return 'Could not check your number. Please try again.';
    }
    return 'Could not verify your number. Please try again.';
  }



  Future<void> signOut() async {
    final googleSignIn = GoogleSignIn();
    // signOut() clears the cached session Google Play Services uses to
    // silently reauth on the next sign-in attempt (this is what actually
    // controls whether the account picker reappears vs. the same account
    // getting reused automatically). disconnect() additionally revokes the
    // app's OAuth grant. Run both independently — previously disconnect()
    // was gated behind isSignedIn() and any failure was silently swallowed,
    // so if it ever threw, neither ran and Play Services kept the account
    // cached, which looked like "always defaults to the last account" even
    // after signing out.
    try {
      await googleSignIn.signOut();
    } catch (e) {
      debugPrint('GoogleSignIn.signOut failed (non-fatal): $e');
    }
    try {
      await googleSignIn.disconnect();
    } catch (e) {
      debugPrint('GoogleSignIn.disconnect failed (non-fatal): $e');
    }

    // The Facebook login used to connect a Page; the Page itself stays
    // connected (its token is on the server).
    try {
      final fbStatus = await FacebookAuth.instance.accessToken;
      if (fbStatus != null) {
        await FacebookAuth.instance.logOut();
      }
    } catch (e) {
      debugPrint('Facebook sign-out cleanup failed (non-fatal): $e');
    }

    // Stop geofence alerts and pushes for this account on this device
    // before the session ends (needs the still-signed-in user).
    NotificationService.markSignedOut();
    await GeofenceService.stop();
    await PushTokenService.unregister();

    await firebaseAuth.signOut();
  }

  /// Returns the profile as it now stands (`{role: ''}` for a new one).
  Future<Map<String, dynamic>?> _createUserDocIfNew(User user) async {
    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await _createUserDoc(user);
      return const {'role': ''};
    }
    return snapshot.data();
  }

  Future<void> _createUserDoc(User user) async {
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      // No role until onboarding (Your Details -> account type) sets one:
      // AuthWrapper sends role-less accounts there instead of to the
      // general home, so a first Google/phone sign-in creates an account
      // properly rather than silently becoming a General User.
      'role': '',
      'isVerified': false,
      'photoUrl': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static bool hasCompletedOnboarding(Map<String, dynamic>? userData) {
    final role = userData?['role'];
    return role is String && role.isNotEmpty;
  }

  Future<bool> isNewUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return true;
    final role = doc.data()?['role'];
    return role == null || role == '';
  }
}