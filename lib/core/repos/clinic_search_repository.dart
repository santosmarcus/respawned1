import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:respawnd1/core/constants/maps_config.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';

/// Base type for every failure ClinicSearchRepository can throw. Callers
/// (select_clinic_sheet.dart) catch this and show a message appropriate to
/// the category instead of one generic "something went wrong" string.
sealed class ClinicSearchException implements Exception {
  final String message;
  const ClinicSearchException(this.message);
  @override
  String toString() => message;
}

/// API key / GCP project / billing / API-not-enabled class of failures —
/// this is what "This API project was not found", API key restriction
/// rejections, and billing-disabled responses map to. Distinct from "no
/// results" and from a transient network blip because the fix for this one
/// is in Google Cloud Console, not in retrying.
class ClinicSearchConfigException extends ClinicSearchException {
  const ClinicSearchConfigException(super.message);
}

/// Device offline, DNS failure, timeout — retrying may just work.
class ClinicSearchNetworkException extends ClinicSearchException {
  const ClinicSearchNetworkException(super.message);
}

/// Anything else unexpected (malformed response, unhandled status, rate
/// limiting, etc).
class ClinicSearchUnexpectedException extends ClinicSearchException {
  const ClinicSearchUnexpectedException(super.message);
}

/// Places API (New) wrapper for veterinary clinic search — used by
/// select_clinic_sheet.dart. Mirrors the search intent already used in
/// lib/features/pettransporter/transit_progress_page.dart's
/// `_findAndRouteToNextClinic` (type=veterinary_care), kept in one place so
/// map/Places logic doesn't get duplicated a third time.
///
/// Also reused (via [searchPlaces], which — unlike [textSearch] — doesn't
/// bias toward veterinary clinics) by the shelter-location picker, since
/// it's the same underlying API/key/error-handling for any place search,
/// not just clinics.
///
/// Uses Places API (New) — POST + JSON body + `X-Goog-Api-Key` /
/// `X-Goog-FieldMask` headers — not the legacy `maps/api/place/*` Places
/// Web Service GET endpoints. Both were enabled in Google Cloud per the
/// task notes; New is the actively maintained one and, unlike legacy
/// Nearby/Text Search, returns phone numbers directly in the search
/// response, so no separate Place Details call is needed per selection.
///
/// This is a thin REST wrapper, not a cached/managed clinic directory —
/// there is intentionally no `clinics` Firestore collection. See the
/// automatic-clinic-selection technical assessment for why that's deferred.
class ClinicSearchRepository {
  static const _baseUrl = 'places.googleapis.com';

  // Keep field masks minimal — Places API (New) bills by which fields you
  // request (Essentials/Pro/Enterprise SKU tiers), so asking for more than
  // this screen displays costs more than it needs to.
  static const _fieldMask =
      'places.id,places.displayName,places.formattedAddress,places.location,'
      'places.currentOpeningHours.openNow,places.rating,places.nationalPhoneNumber';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': MapsConfig.placesApiKey,
        'X-Goog-FieldMask': _fieldMask,
      };

  /// Nearby veterinary clinics around [lat]/[lng]. This is the default view
  /// when the clinic search sheet opens with no search text entered yet.
  Future<List<ClinicSearchResult>> nearbySearch({
    required double lat,
    required double lng,
    double radiusMeters = 5000,
  }) async {
    final uri = Uri.https(_baseUrl, '/v1/places:searchNearby');
    final body = jsonEncode({
      'includedTypes': ['veterinary_care'],
      'maxResultCount': 20,
      'locationRestriction': {
        'circle': {
          'center': {'latitude': lat, 'longitude': lng},
          'radius': radiusMeters,
        },
      },
    });
    return _search(uri, body);
  }

  /// Free-text search ("PetCare Manila", "vet clinic near Malate", ...),
  /// optionally biased toward [lat]/[lng] when the case's location is known.
  Future<List<ClinicSearchResult>> textSearch({
    required String query,
    double? lat,
    double? lng,
  }) async {
    if (query.trim().isEmpty) {
      return (lat != null && lng != null)
          ? nearbySearch(lat: lat, lng: lng)
          : const [];
    }
    final uri = Uri.https(_baseUrl, '/v1/places:searchText');
    final body = jsonEncode({
      'textQuery': '$query veterinary clinic',
      if (lat != null && lng != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 20000,
          },
        },
    });
    return _search(uri, body);
  }

  /// General-purpose place/address search — no veterinary bias, for the
  /// shelter-location picker (or anything else that just needs "find this
  /// address/place"). Same endpoint, key, and error handling as
  /// [textSearch]/[nearbySearch]; only the query body differs.
  Future<List<ClinicSearchResult>> searchPlaces({
    required String query,
    double? lat,
    double? lng,
  }) async {
    if (query.trim().isEmpty) return const [];
    final uri = Uri.https(_baseUrl, '/v1/places:searchText');
    final body = jsonEncode({
      'textQuery': query,
      if (lat != null && lng != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 50000,
          },
        },
    });
    return _search(uri, body);
  }

  Future<List<ClinicSearchResult>> _search(Uri uri, String body) async {
    MapsConfig.logKeySourceOnce();

    http.Response res;
    try {
      res = await http
          .post(uri, headers: _headers, body: body)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const ClinicSearchNetworkException(
          'The clinic search timed out. Check your connection and try again.');
    } on SocketException {
      throw const ClinicSearchNetworkException(
          'No internet connection. Check your connection and try again.');
    } on http.ClientException catch (e) {
      throw ClinicSearchNetworkException('Network error: ${e.message}');
    }

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      final places = (decoded is Map<String, dynamic> ? decoded['places'] : null) as List<dynamic>?;
      if (places == null || places.isEmpty) return const []; // valid "zero results", not an error
      return places
          .map((r) => ClinicSearchResult.fromPlacesJson(r as Map<String, dynamic>))
          .where((c) => c.placeId.isNotEmpty)
          .toList();
    }

    // Non-200: classify by status so the UI can tell "fix your Google
    // Cloud config" apart from "try again in a moment".
    Map<String, dynamic>? errorBody;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) errorBody = decoded['error'] as Map<String, dynamic>?;
    } catch (_) {
      // response body wasn't JSON — fall through with errorBody left null
    }
    final apiMessage = errorBody?['message'] as String?;
    final apiStatus = errorBody?['status'] as String?;

    if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
      throw ClinicSearchConfigException(
        'Clinic search is misconfigured (HTTP ${res.statusCode}${apiStatus != null ? ' $apiStatus' : ''}): '
        '${apiMessage ?? 'the API key or its Google Cloud project settings need attention.'} '
        '(key: ${MapsConfig.maskedKeyForLogging})',
      );
    }
    if (res.statusCode == 404) {
      throw ClinicSearchConfigException(
        'This API project was not found for the configured key '
        '(key: ${MapsConfig.maskedKeyForLogging}). The key likely belongs to a '
        'different or deleted Google Cloud project — see the setup notes.',
      );
    }
    if (res.statusCode == 429) {
      throw ClinicSearchUnexpectedException(
          'Clinic search is being rate-limited. Please try again in a moment.');
    }
    throw ClinicSearchUnexpectedException(
      'Clinic search failed (HTTP ${res.statusCode}${apiStatus != null ? ' $apiStatus' : ''}): '
      '${apiMessage ?? 'unexpected error.'}',
    );
  }
}
