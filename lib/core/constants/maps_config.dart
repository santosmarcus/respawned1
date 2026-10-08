import 'package:flutter/foundation.dart';

/// Centralized Google Maps/Places configuration — the single source of
/// truth for which API key clinic search uses. Do not add another
/// hardcoded key literal anywhere else; read from here.
///
/// ROOT CAUSE of "This API project was not found": this file previously
/// defaulted to a *different* key literal (copied from
/// lib/features/pettransporter/transit_progress_page.dart's own
/// `_placesApiKey`, 'AIzaSyAzqeI6...') than the key actually proven to work
/// elsewhere in this app — the one embedded in
/// android/app/src/main/AndroidManifest.xml (`com.google.android.geo.API_KEY`)
/// and in lib/features/rescue/rescue_page.dart / track_case_page.dart's
/// `_geocodingApiKey` ('AIzaSyChQ9...'), which successfully renders the
/// native map and resolves addresses today. Two different key values were
/// in play; the one this file used was, per Google's error, not a key
/// belonging to any live project — almost certainly stale, revoked, or
/// simply never valid. This now defaults to the SAME key already proven to
/// work for Maps SDK rendering and Geocoding, on the assumption that's the
/// one actually tied to the `respawnd1-45021` Firebase/GCP project where
/// the Places APIs were enabled. If clinic search still fails after this
/// change, the AndroidManifest/geocoding key itself needs the checklist in
/// the PR notes run against it (project match, billing, API restrictions).
///
/// transit_progress_page.dart's own separate `_placesApiKey`/
/// `_directionsApiKey` literals are NOT changed by this file — they're a
/// distinct hardcoded constant in that file, out of scope here, but should
/// be checked against the same checklist since they may share the same
/// root cause.
///
/// Override at build/run time with:
///   flutter run --dart-define=PLACES_API_KEY=your_real_key
///   flutter build ... --dart-define=PLACES_API_KEY=your_real_key
/// so the key doesn't have to live in source at all going forward.
class MapsConfig {
  static const String placesApiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0',
  );

  /// Legacy Directions API key. Defaults to the same value as
  /// [placesApiKey] — Google API keys aren't per-product unless explicitly
  /// restricted, and this is the key already proven to work for Maps
  /// SDK/Geocoding in this project. Kept as its own constant (not just an
  /// alias) so it can be overridden independently via
  /// `--dart-define=DIRECTIONS_API_KEY=...` if it ever needs a different
  /// key than Places.
  static const String directionsApiKey = String.fromEnvironment(
    'DIRECTIONS_API_KEY',
    defaultValue: placesApiKey,
  );

  /// First/last 4 characters only — enough to confirm which key actually
  /// compiled in (e.g. to compare against Google Cloud Console's key list)
  /// without ever printing the full secret. Debug builds only.
  static String get maskedKeyForLogging => _mask(placesApiKey);

  static String get maskedDirectionsKeyForLogging => _mask(directionsApiKey);

  static String _mask(String key) {
    if (key.length <= 10) return '(key too short to mask safely)';
    return '${key.substring(0, 4)}…${key.substring(key.length - 4)}';
  }

  static void logKeySourceOnce() {
    if (!kDebugMode || _loggedKeySource) return;
    _loggedKeySource = true;
    const fromDefine = String.fromEnvironment('PLACES_API_KEY');
    debugPrint(
      'MapsConfig: Places key in use = $maskedKeyForLogging '
      '(source: ${fromDefine.isEmpty ? 'hardcoded fallback' : '--dart-define'})',
    );
  }

  static void logDirectionsKeySourceOnce() {
    if (!kDebugMode || _loggedDirectionsKeySource) return;
    _loggedDirectionsKeySource = true;
    const fromDefine = String.fromEnvironment('DIRECTIONS_API_KEY');
    debugPrint(
      'MapsConfig: Directions key in use = $maskedDirectionsKeyForLogging '
      '(source: ${fromDefine.isEmpty ? 'hardcoded fallback (= Places key)' : '--dart-define'})',
    );
  }

  static bool _loggedKeySource = false;
  static bool _loggedDirectionsKeySource = false;
}
