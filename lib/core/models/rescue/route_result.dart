import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A route between two points, either road-following (from the Directions
/// API) or a straight-line fallback when that's unavailable. See
/// DirectionsRepository for how/when each is produced.
class RouteResult {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final Duration? duration; // only present for a real Directions result
  final bool isRoadFollowing;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceKm,
    this.duration,
    required this.isRoadFollowing,
  });
}
