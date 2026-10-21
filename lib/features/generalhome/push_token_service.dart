import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class PushTokenService {
  static bool _listenerAttached = false;
  static String? _registeredForUid;

  static Future<void> register() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_registeredForUid == uid) return; // already handled this session
    _registeredForUid = uid;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }
      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }

      if (!_listenerAttached) {
        _listenerAttached = true;
        messaging.onTokenRefresh.listen((newToken) {
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          if (currentUid != null) _saveToken(currentUid, newToken);
        });
      }
    } catch (_) {
    }
  }

  static Future<void> unregister() async {
    _registeredForUid = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
      if (token == null) return;
      final doc = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await doc.get().timeout(const Duration(seconds: 5));
      // Only clear it if it's still this device's token — another device
      // the same user signed into later may have overwritten it.
      if (snap.data()?['fcmToken'] == token) {
        await doc
            .update({'fcmToken': FieldValue.delete()})
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
    }
  }

  static Future<void> _saveToken(String uid, String token) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    ).catchError((_) {});
  }
}