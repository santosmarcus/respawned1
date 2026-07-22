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
      await messaging.requestPermission(alert: true, badge: true, sound: true);

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

  static Future<void> _saveToken(String uid, String token) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    ).catchError((_) {});
  }
}