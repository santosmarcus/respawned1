import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:respawnd1/core/geofence/geofence_config.dart';
import 'package:respawnd1/core/services/notification_service.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/firebase_options.dart';

const String _caseFencePrefix = 'case_';
const String _selfAreaFenceId = 'self_area';

/// Runs in a background isolate whenever the OS reports a geofence
/// event — including when the app is closed (Google Play services
/// GeofencingClient on Android, CLLocationManager region monitoring on iOS).
@pragma('vm:entry-point')
Future<void> respawndGeofenceTriggered(GeofenceCallbackParams params) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (user == null) {
      await NativeGeofenceManager.instance.removeAllGeofences();
      return;
    }

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(user.uid);
    final userData = (await userRef.get().timeout(const Duration(seconds: 10))).data();
    final prefs = GeofencePrefs.fromUserData(userData);
    // Pet transporters are only notified about their own assignments,
    // rescue-location updates and clinic changes (functions/index.js).
    final isTransporter = userData?['role'] == 'pet_transporter';

    // Every event tells us roughly where the user is now — keep the
    // server-side geofence matching (functions/index.js) up to date.
    final loc = params.location;
    if (loc != null) {
      await userRef.set({
        'lastLat': loc.latitude,
        'lastLng': loc.longitude,
        'lastLocationAt': FieldValue.serverTimestamp(),
        'lastLocationSource': 'geofence',
      }, SetOptions(merge: true));
    }

    for (final fence in params.geofences) {
      if (fence.id == _selfAreaFenceId && params.event == GeofenceEvent.exit) {
        // The user left their saved area: move the area to where they are.
        if (loc != null) {
          await GeofenceService._registerSelfArea(loc.latitude, loc.longitude);
        }
        continue;
      }

      if (fence.id.startsWith(_caseFencePrefix) && params.event == GeofenceEvent.enter) {
        if (isTransporter) continue;
        final caseId = fence.id.substring(_caseFencePrefix.length);
        await _handleCaseEnter(db, userRef, user.uid, caseId, prefs);
      }
    }
  } catch (e) {
    debugPrint('respawndGeofenceTriggered failed: $e');
  }
}

Future<void> _handleCaseEnter(
    FirebaseFirestore db,
    DocumentReference<Map<String, dynamic>> userRef,
    String uid,
    String caseId,
    GeofencePrefs prefs,
    ) async {
  final caseDoc = await db.collection('cases').doc(caseId).get().timeout(const Duration(seconds: 10));
  final c = caseDoc.data();
  final status = (c?['status'] as String? ?? '').toLowerCase();
  if (c == null || GeofenceConfig.inactiveCaseStatuses.contains(status)) {
    await NativeGeofenceManager.instance.removeGeofenceById('$_caseFencePrefix$caseId');
    return;
  }
  if (c['reporterId'] == uid || !prefs.wants(GeofenceCategory.newCase)) return;

  // Don't repeat the alert if the user walks in and out of the same fence.
  final hitRef = userRef.collection('geofenceHits').doc(caseId);
  final hit = await hitRef.get();
  final last = (hit.data()?['at'] as Timestamp?)?.toDate();
  if (last != null && DateTime.now().difference(last) < const Duration(hours: 6)) return;
  await hitRef.set({'at': FieldValue.serverTimestamp()});

  final address = (c['address'] as String?)?.trim();
  final species = (c['animalType'] ?? c['species'] ?? 'animal').toString().toLowerCase();
  await NotificationService.show(
    title: "You're near an active rescue report",
    body: address == null || address.isEmpty
        ? 'A reported $species needs help close to you. Tap to see the report.'
        : 'A reported $species needs help near $address. Tap to see the report.',
    data: {'type': 'geofence_case_nearby', 'caseId': caseId},
  );
}

/// Registers on-device geofences (Google Geofencing API through
/// native_geofence) around active rescue cases near the user, plus one
/// "self area" geofence whose exit keeps users/{uid}.lastLat/lastLng
/// current while the app is closed.
class GeofenceService {
  GeofenceService._();

  static bool _initialized = false;
  static bool _syncing = false;
  static DateTime? _lastSync;
  static String? _startedForUid;

  /// Call after sign-in. Safe to call repeatedly.
  static Future<void> start(String uid) async {
    if (kIsWeb) return;
    if (_startedForUid == uid) {
      await sync();
      return;
    }
    _startedForUid = uid;
    await sync(force: true);
  }

  /// Call on sign-out.
  static Future<void> stop() async {
    _startedForUid = null;
    _lastSync = null;
    if (kIsWeb) return;
    try {
      await _ensureInitialized();
      await NativeGeofenceManager.instance.removeAllGeofences();
    } catch (e) {
      debugPrint('GeofenceService.stop: $e');
    }
  }

  /// Saves the current location and re-registers the nearby case
  /// geofences. Throttled to once every 5 minutes unless [force] is set.
  static Future<void> sync({bool force = false}) async {
    if (kIsWeb || _syncing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (!force && _lastSync != null && DateTime.now().difference(_lastSync!) < const Duration(minutes: 5)) {
      return;
    }
    _syncing = true;
    try {
      final pos = await _currentPosition();
      if (pos == null) return;
      _lastSync = DateTime.now();

      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      await userRef.set({
        'lastLat': pos.latitude,
        'lastLng': pos.longitude,
        'lastLocationAt': FieldValue.serverTimestamp(),
        'lastLocationSource': 'app',
      }, SetOptions(merge: true));

      final prefs = GeofencePrefs.fromUserData((await userRef.get()).data());
      await _ensureInitialized();

      // Background geofences need "Allow all the time" on Android 10+.
      final permission = await Geolocator.checkPermission();
      if (!prefs.enabled || permission != LocationPermission.always) {
        await NativeGeofenceManager.instance.removeAllGeofences();
        return;
      }

      await _registerSelfArea(pos.latitude, pos.longitude);
      await _registerNearbyCases(uid, pos.latitude, pos.longitude);
    } on NativeGeofenceException catch (e) {
      debugPrint('GeofenceService.sync: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('GeofenceService.sync: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Asks for "Allow all the time". On Android 11+ the system only offers
  /// this from the app's settings page, so that page is opened if needed.
  /// Returns true when background location is granted.
  static Future<bool> requestBackgroundPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
    if (p != LocationPermission.always) {
      await Geolocator.openAppSettings();
      return false;
    }
    await sync(force: true);
    return true;
  }

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await NativeGeofenceManager.instance.initialize();
    _initialized = true;
  }

  static Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          final last = await Geolocator.getLastKnownPosition();
          if (last == null) throw TimeoutException('location timeout');
          return last;
        },
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _registerSelfArea(double lat, double lng) async {
    await _ensureInitialized();
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(_selfAreaFenceId);
    } catch (_) {
      // not registered yet
    }
    await NativeGeofenceManager.instance.createGeofence(
      Geofence(
        id: _selfAreaFenceId,
        location: Location(latitude: lat, longitude: lng),
        radiusMeters: GeofenceConfig.selfAreaRadiusMeters,
        triggers: const {GeofenceEvent.exit},
        iosSettings: const IosGeofenceSettings(initialTrigger: false),
        androidSettings: const AndroidGeofenceSettings(
          initialTriggers: {},
          notificationResponsiveness: Duration(minutes: 2),
        ),
      ),
      respawndGeofenceTriggered,
    );
  }

  static Future<void> _registerNearbyCases(String uid, double lat, double lng) async {
    const searchKm = GeofenceConfig.caseSearchRadiusKm;
    final latDelta = searchKm / 111;
    final lngDelta = searchKm / (111 * math.cos(lat * math.pi / 180));

    final snap = await FirebaseFirestore.instance
        .collection('cases')
        .where('lat', isGreaterThanOrEqualTo: lat - latDelta)
        .where('lat', isLessThanOrEqualTo: lat + latDelta)
        .get();

    final nearby = <({String id, double lat, double lng, double km})>[];
    for (final doc in snap.docs) {
      final c = doc.data();
      final cLat = (c['lat'] as num?)?.toDouble();
      final cLng = (c['lng'] as num?)?.toDouble();
      final status = (c['status'] as String? ?? '').toLowerCase();
      if (cLat == null || cLng == null) continue;
      if ((cLng - lng).abs() > lngDelta) continue;
      if (GeofenceConfig.inactiveCaseStatuses.contains(status)) continue;
      if (c['reporterId'] == uid) continue;
      final km = haversineDistanceKm(lat, lng, cLat, cLng);
      if (km <= searchKm) nearby.add((id: doc.id, lat: cLat, lng: cLng, km: km));
    }
    nearby.sort((a, b) => a.km.compareTo(b.km));
    final wanted = {for (final c in nearby.take(GeofenceConfig.maxCaseGeofences)) '$_caseFencePrefix${c.id}': c};

    final registered = await NativeGeofenceManager.instance.getRegisteredGeofences();
    final registeredIds = <String>{};
    for (final g in registered) {
      if (!g.id.startsWith(_caseFencePrefix)) continue;
      if (wanted.containsKey(g.id)) {
        registeredIds.add(g.id);
      } else {
        await NativeGeofenceManager.instance.removeGeofenceById(g.id);
      }
    }

    for (final entry in wanted.entries) {
      if (registeredIds.contains(entry.key)) continue;
      await NativeGeofenceManager.instance.createGeofence(
        Geofence(
          id: entry.key,
          location: Location(latitude: entry.value.lat, longitude: entry.value.lng),
          radiusMeters: GeofenceConfig.caseGeofenceRadiusMeters,
          triggers: const {GeofenceEvent.enter},
          // Don't fire for fences the user is already inside when they're
          // registered — only for actually walking/driving into one.
          iosSettings: const IosGeofenceSettings(initialTrigger: false),
          androidSettings: const AndroidGeofenceSettings(
            initialTriggers: {},
            expiration: Duration(days: 7),
            notificationResponsiveness: Duration(minutes: 1),
          ),
        ),
        respawndGeofenceTriggered,
      );
    }
  }
}
