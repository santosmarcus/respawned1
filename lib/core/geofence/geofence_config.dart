import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared geofence numbers, used by the on-device geofences, the maps that
/// draw them, and (mirrored by hand) functions/index.js.
class GeofenceConfig {
  GeofenceConfig._();

  /// Radius of the on-device geofence registered around each active case.
  /// Entering it shows "You're near an active rescue report".
  static const double caseGeofenceRadiusMeters = 300;

  /// Transporter pickup / clinic / shelter arrival geofence.
  /// Same value as `_arrivalThresholdMeters` in transit_progress_page.dart.
  static const double arrivalRadiusMeters = 150;

  /// "Moved away" geofence around the user's last saved location. Leaving
  /// it refreshes users/{uid}.lastLat/lastLng in the background so the
  /// server-side geofence notifications use a current location.
  static const double selfAreaRadiusMeters = 1000;

  /// How far around the user to look for cases to register geofences for.
  static const double caseSearchRadiusKm = 10;

  /// Android allows 100 geofences per app; stay well under it.
  static const int maxCaseGeofences = 30;

  /// Default alert radius for the general public (functions RADIUS_KM).
  static const double defaultAlertRadiusKm = 5;

  /// Largest alert radius a user can choose (functions MAX_USER_ALERT_RADIUS_KM).
  static const double maxAlertRadiusKm = 10;

  /// Case statuses that are no longer active — no geofence for these.
  static const Set<String> inactiveCaseStatuses = {
    'dismissed',
    'cancelled',
    'withdrawn',
    'rejected',
    'completed',
    'closed',
    'ended',
  };
}

/// Notification categories a user can mute.
/// Keep in sync with NOTIFY_CATEGORY in functions/index.js.
class GeofenceCategory {
  GeofenceCategory._();

  static const String newCase = 'new_case';
  static const String caseUpdate = 'case_update';
  static const String petAlert = 'pet_alert';
  static const String tagScan = 'tag_scan';

  static const Map<String, String> labels = {
    newCase: 'New rescue reports near me',
    caseUpdate: 'Rescue progress & completed rescues',
    petAlert: 'Lost & found pet alerts',
    tagScan: 'Lost pets spotted by tag scan',
  };
}

/// users/{uid}.geofencePrefs — read by the app and by functions/index.js.
class GeofencePrefs {
  final bool enabled;
  final double radiusKm;
  final Set<String> mutedCategories;

  const GeofencePrefs({
    this.enabled = true,
    this.radiusKm = GeofenceConfig.defaultAlertRadiusKm,
    this.mutedCategories = const {},
  });

  factory GeofencePrefs.fromUserData(Map<String, dynamic>? userData) {
    final m = (userData?['geofencePrefs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final r = (m['radiusKm'] as num?)?.toDouble();
    return GeofencePrefs(
      enabled: m['enabled'] as bool? ?? true,
      radiusKm: (r == null || r <= 0)
          ? GeofenceConfig.defaultAlertRadiusKm
          : r.clamp(1, GeofenceConfig.maxAlertRadiusKm).toDouble(),
      mutedCategories: ((m['mutedCategories'] as List?) ?? const []).whereType<String>().toSet(),
    );
  }

  bool wants(String category) => enabled && !mutedCategories.contains(category);

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'radiusKm': radiusKm,
    'mutedCategories': mutedCategories.toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  GeofencePrefs copyWith({bool? enabled, double? radiusKm, Set<String>? mutedCategories}) => GeofencePrefs(
    enabled: enabled ?? this.enabled,
    radiusKm: radiusKm ?? this.radiusKm,
    mutedCategories: mutedCategories ?? this.mutedCategories,
  );
}