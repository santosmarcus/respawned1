import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:respawnd1/core/constants/maps_config.dart';
import 'package:respawnd1/core/models/rescue/route_result.dart';
import 'package:respawnd1/core/utils/geo.dart';

/// Route returned by [fetchDirectionsRoute] (moved here from
/// transit_progress_page.dart, which re-exports it). The transporter's
/// transit screen uses this plain, uncached call; Track Case uses the
/// cached [DirectionsRepository] below. Both share [decodePolyline].
class DirectionsRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final String distanceText;
  final String durationText;

  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.distanceText,
    required this.durationText,
  });
}

Future<DirectionsRoute?> fetchDirectionsRoute(
  LatLng origin,
  LatLng destination,
) async {
  try {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': MapsConfig.directionsApiKey,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      debugPrint('fetchDirectionsRoute: HTTP ${res.statusCode} — ${res.body}');
      return null;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') {
      debugPrint(
        'fetchDirectionsRoute: status=${body['status']} '
        'error_message=${body['error_message']}',
      );
      return null;
    }
    final routes = body['routes'] as List<dynamic>;
    if (routes.isEmpty) {
      debugPrint('fetchDirectionsRoute: status OK but routes list empty.');
      return null;
    }
    final route = routes.first as Map<String, dynamic>;
    final legs = route['legs'] as List<dynamic>;
    if (legs.isEmpty) {
      debugPrint('fetchDirectionsRoute: route has no legs.');
      return null;
    }
    final leg = legs.first as Map<String, dynamic>;
    final overview = route['overview_polyline']?['points'] as String?;
    if (overview == null) {
      debugPrint('fetchDirectionsRoute: no overview_polyline in response.');
      return null;
    }

    return DirectionsRoute(
      points: decodePolyline(overview),
      distanceMeters: (leg['distance']?['value'] as num?)?.toDouble() ?? 0,
      distanceText: (leg['distance']?['text'] as String?) ?? '',
      durationText: (leg['duration']?['text'] as String?) ?? '',
    );
  } catch (e) {
    debugPrint('fetchDirectionsRoute: threw $e');
    return null;
  }
}

// Standard Google encoded-polyline decoder.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  final len = encoded.length;

  while (index < len) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dLat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dLng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Legacy Google Directions API wrapper for road-following routes (Track
/// Case's rider->case polyline). This project already calls this exact
/// endpoint successfully from transit_progress_page.dart's
/// `fetchDirectionsRoute`/`_verifyArrivalViaDirections` — reusing the same
/// endpoint and decode logic here rather than migrating to the newer Routes
/// API, since there's no evidence Routes API has been enabled for this
/// project (only Places API/Places API (New) were confirmed enabled) and
/// the legacy endpoint already works elsewhere in this app.
///
/// Caches the last successful route in memory, keyed by a "meaningfully
/// different" check on origin/destination (not exact equality — small GPS
/// jitter shouldn't trigger a fresh request). On failure, falls back to
/// that same stale cache if one exists, then to a straight-line route —
/// this repository never returns null, so callers always have something
/// to draw.
class DirectionsRepository {
  static const _baseUrl = 'maps.googleapis.com';

  /// Two points closer together than this are treated as "the same" route
  /// request — avoids re-calling the API for trivial coordinate jitter.
  static const _meaningfulChangeKm = 0.05; // 50 meters

  RouteResult? _cachedResult;
  LatLng? _cachedOrigin;
  LatLng? _cachedDestination;

  bool _isSameAsCached(LatLng origin, LatLng destination) {
    if (_cachedOrigin == null ||
        _cachedDestination == null ||
        _cachedResult == null) {
      return false;
    }
    final originDelta = haversineDistanceKm(
      _cachedOrigin!.latitude,
      _cachedOrigin!.longitude,
      origin.latitude,
      origin.longitude,
    );
    final destDelta = haversineDistanceKm(
      _cachedDestination!.latitude,
      _cachedDestination!.longitude,
      destination.latitude,
      destination.longitude,
    );
    return originDelta < _meaningfulChangeKm && destDelta < _meaningfulChangeKm;
  }

  /// Never returns null — always resolves to one of: a fresh road route, a
  /// stale-but-still-useful cached route, or a straight-line fallback.
  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_isSameAsCached(origin, destination)) {
      _log(
        'using cached route (origin/destination within ${_meaningfulChangeKm}km of last request)',
      );
      return _cachedResult!;
    }

    try {
      final fresh = await _fetchFromDirectionsApi(origin, destination);
      if (fresh != null) {
        _cachedOrigin = origin;
        _cachedDestination = destination;
        _cachedResult = fresh;
        _log(
          'road route accepted: polylineAdded=true, points=${fresh.polylinePoints.length}, '
          'distanceKm=${fresh.distanceKm.toStringAsFixed(2)}, durationSec=${fresh.duration?.inSeconds}',
        );
        return fresh;
      }
    } catch (e) {
      // fall through to cache/straight-line below
      _log('Directions API call threw: $e');
    }

    // API failed, timed out, or returned no usable route — an existing
    // cached route (even for a slightly different pair) is still more
    // useful than nothing.
    if (_cachedResult != null) {
      _log('falling back to stale cached route after a failed fresh request');
      return _cachedResult!;
    }

    _log(
      'falling back to straight-line polyline: polylineAdded=true, isRoadFollowing=false '
      '(road route unavailable — see prior log line for HTTP/API result)',
    );
    return RouteResult(
      polylinePoints: [origin, destination],
      distanceKm: haversineDistanceKm(
        origin.latitude,
        origin.longitude,
        destination.latitude,
        destination.longitude,
      ),
      duration: null,
      isRoadFollowing: false,
    );
  }

  Future<RouteResult?> _fetchFromDirectionsApi(
    LatLng origin,
    LatLng destination,
  ) async {
    MapsConfig.logDirectionsKeySourceOnce();

    final uri = Uri.https(_baseUrl, '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': MapsConfig.directionsApiKey,
    });

    _log(
      'requesting route: origin=${_maskCoord(origin)}, destination=${_maskCoord(destination)}',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      _log('HTTP ${res.statusCode} — treating as no route (falling back)');
      return null;
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final apiStatus = body['status'] as String?;
    if (apiStatus != 'OK') {
      // This is the exact branch that fires when the API key isn't
      // authorized for the Directions API (REQUEST_DENIED) — logging the
      // status/error_message (never the key) here is what makes that
      // diagnosable from a device log instead of silently drawing a
      // straight line with no explanation.
      _log(
        'Directions API status=$apiStatus, error_message=${body['error_message']} — falling back',
      );
      return null;
    }

    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      _log('status=OK but routes[] is empty — falling back');
      return null;
    }
    final route = routes.first as Map<String, dynamic>;

    final legs = route['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) {
      _log('route present but legs[] is empty — falling back');
      return null;
    }
    final leg = legs.first as Map<String, dynamic>;

    final overview = route['overview_polyline']?['points'] as String?;
    if (overview == null || overview.isEmpty) {
      _log(
        'route present but overview_polyline.points is missing/empty — falling back',
      );
      return null;
    }

    final points = decodePolyline(overview);
    _log(
      'decoded polyline: encodedLength=${overview.length}, decodedPoints=${points.length}',
    );
    if (points.isEmpty) {
      _log(
        'decodePolyline returned 0 points from a non-empty encoded string — falling back',
      );
      return null;
    }

    final distanceMeters = (leg['distance']?['value'] as num?)?.toDouble();
    final durationSeconds = (leg['duration']?['value'] as num?)?.toInt();

    return RouteResult(
      polylinePoints: points,
      distanceKm: distanceMeters != null
          ? distanceMeters / 1000
          : haversineDistanceKm(
              origin.latitude,
              origin.longitude,
              destination.latitude,
              destination.longitude,
            ),
      duration: durationSeconds != null
          ? Duration(seconds: durationSeconds)
          : null,
      isRoadFollowing: true,
    );
  }

  // Rounded to ~1km precision — enough to spot "same city" vs "wrong
  // hemisphere" bugs in a log without publishing anyone's exact location.
  String _maskCoord(LatLng p) =>
      '${p.latitude.toStringAsFixed(2)},${p.longitude.toStringAsFixed(2)}';

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('DirectionsRepository: $message');
  }
}
