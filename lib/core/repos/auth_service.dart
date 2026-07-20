import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

ValueNotifier<AuthService> authService = ValueNotifier (AuthService());

class AuthService {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await firebaseAuth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
    //required String name,
  }) async {
    final credential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email, password: password);

    //await credential.user!.updateDisplayName(name);

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

    return credential;
  }

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
    await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await firebaseAuth.signInWithCredential(credential);
    await _createUserDocIfNew(userCredential.user!);
    return userCredential;
  }

  Future<UserCredential?> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status != LoginStatus.success) return null; // user cancelled

    final OAuthCredential credential =
    FacebookAuthProvider.credential(result.accessToken!.tokenString);

    final userCredential =
    await firebaseAuth.signInWithCredential(credential);
    await _createUserDocIfNew(userCredential.user!);
    return userCredential;
  }

  /*// Step 1: Send OTP
  Future<void> sendOtp({
    required String phoneNumber, // format: +639XXXXXXXXX
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verified on some Android devices
        await _auth.signInWithCredential(credential);
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
    final userCredential = await _auth.signInWithCredential(credential);
    await _createUserDocIfNew(userCredential.user!);
    return userCredential;
  }*/


  Future<void> signOut() async {
    await GoogleSignIn().disconnect();
    await FacebookAuth.instance.logOut();
    await firebaseAuth.signOut();
  }

  Future<void> _createUserDocIfNew(User user) async {
    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await _createUserDoc(user);
    }
  }

  Future<void> _createUserDoc(User user) async {
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      'role': 'general',        // default role — NGO staff change this manually
      'isVerified': false,
      'photoUrl': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isNewUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return true;
    final role = doc.data()?['role'];
    return role == null || role == '';
  }
}