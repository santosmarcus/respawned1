import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:respawnd1/features/collartag/pet_found_chat.dart';
import 'package:respawnd1/features/pettransporter/rescue_request.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';
import 'package:respawnd1/features/rescue/lost_found_track_case.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';

/// Shows push notifications while the app is open, and opens the right
/// screen when any notification (push or local geofence alert) is tapped.
///
/// Every push sent by functions/index.js carries `data.type` plus an id
/// (`caseId`, `alertId`, or `tagId` + `sessionId`); [_open] maps those to
/// a screen.
class NotificationService {
  NotificationService._();

  static const String channelId = 'respawnd_alerts';
  static const String channelName = 'Rescue & geofence alerts';
  static const String channelDescription =
      'Rescue reports, lost pet alerts and rescue updates near you.';

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static bool _listenersAttached = false;

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _routerReady = false;
  static Map<String, dynamic>? _pending;

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    await _initLocal();

    if (_listenersAttached || kIsWeb) return;
    _listenersAttached = true;

    final messaging = FirebaseMessaging.instance;

    // iOS shows foreground pushes itself when told to; Android doesn't, so
    // there we re-post them as local notifications (see onMessage below).
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((message) {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      final n = message.notification;
      if (n == null) return;
      show(
        title: n.title ?? 'ResPAWnd',
        body: n.body ?? '',
        data: message.data,
      );
    });

    // Tapped a push while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));

    // Tapped a push while the app was terminated.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _open(initial.data);

    // Tapped a local notification (e.g. a background geofence alert)
    // while the app was terminated.
    final launch = await _local.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && launchPayload != null) {
      _open(_decode(launchPayload));
    }
  }

  static Future<void> _initLocal() async {
    if (_localReady || kIsWeb) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // PushTokenService.register() asks for permission after sign-in.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _open(_decode(r.payload!));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    ));
    _localReady = true;
  }

  /// Shows a local notification. Safe to call from the geofence background
  /// isolate (it initializes the plugin on first use).
  static Future<void> show({
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    int? id,
  }) async {
    if (kIsWeb) return;
    await _initLocal();
    await _local.show(
      id: id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }

  /// Called by the signed-in router once a home screen is showing, so a
  /// notification tapped during app launch opens on top of it.
  static void markRouterReady() {
    _routerReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(pending));
    }
  }

  static void markSignedOut() {
    _routerReady = false;
    _pending = null;
  }

  static Map<String, dynamic> _decode(String payload) {
    try {
      final v = jsonDecode(payload);
      return v is Map ? v.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _open(Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final nav = _navigatorKey?.currentState;
    if (nav == null || !_routerReady || FirebaseAuth.instance.currentUser == null) {
      _pending = data;
      return;
    }

    try {
      final page = await _pageFor(data);
      if (page == null) return;
      nav.push(MaterialPageRoute(builder: (_) => page));
    } catch (e) {
      debugPrint('NotificationService: could not open $data: $e');
    }
  }

  static Future<Widget?> _pageFor(Map<String, dynamic> data) async {
    final type = data['type'] as String? ?? '';
    final db = FirebaseFirestore.instance;

    switch (type) {
      case 'new_case_nearby':
      case 'new_case_nearby_responder':
      case 'new_case_service_area':
      case 'community_nudge':
      case 'case_status_update':
      case 'case_geofence_event':
      case 'geofence_case_nearby':
        final caseId = data['caseId'] as String?;
        if (caseId == null || caseId.isEmpty) return null;
        return _casePageFor(caseId);

    // Pet transporter pushes (functions/index.js).
      case 'transporter_assignment':
        final caseId = data['caseId'] as String?;
        if (caseId == null || caseId.isEmpty) return null;
        final caseDoc = await db.collection('cases').doc(caseId).get();
        return RescueRequest(
          caseId: caseId,
          data: caseDoc.data() ?? const {},
          assignmentId: data['assignmentId'] as String?,
        );

      case 'transporter_location_updated':
      case 'transporter_clinic_changed':
        final caseId = data['caseId'] as String?;
        if (caseId == null || caseId.isEmpty) return null;
        return TransitProgressPage(caseId: caseId);

      case 'pet_alert_nearby':
        final alertId = data['alertId'] as String?;
        if (alertId == null || alertId.isEmpty) return null;
        return LostFoundTrackCasePage(alertId: alertId);

      case 'tag_scanned':
        final tagId = data['tagId'] as String?;
        final sessionId = data['sessionId'] as String?;
        if (tagId == null || sessionId == null) return null;
        final tag = await db.collection('collarTags').doc(tagId).get();
        return PetFoundChatScreen(
          tagId: tagId,
          sessionId: sessionId,
          petName: tag.data()?['name'] as String? ?? 'Your pet',
          isOwner: true,
        );

      default:
      // e.g. tag_scanned_nearby: informational only, nothing to open.
        return null;
    }
  }

  /// Responders get the accept-case screen, organization staff get the
  /// admin case page, everyone else gets the public case tracker.
  static Future<Widget?> _casePageFor(String caseId) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final results = await Future.wait([
      db.collection('cases').doc(caseId).get(),
      db.collection('users').doc(uid).get(),
    ]);
    final caseData = results[0].data();
    if (caseData == null) return null;
    final role = results[1].data()?['role'] as String? ?? '';

    final isMine = caseData['reporterId'] == uid;
    if (!isMine && (role == 'pet_transporter' || role == 'rescue_volunteer')) {
      return RescueRequest(caseId: caseId, data: caseData);
    }
    if (!isMine && (role == 'admin' || role == 'ngo_staff' || role == 'organization')) {
      return RescueDetailPage(caseId: caseId, data: caseData);
    }
    return TrackCasePage(caseId: caseId);
  }
}
