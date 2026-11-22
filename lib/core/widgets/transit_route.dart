import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/app_theme.dart';

/// The transit route as drawn on every live tracking map — the pet
/// transporter's own map (transit_tracking_map.dart) and the admin Track
/// Case map — so both show the exact same line in the same color.
class TransitRouteStyle {
  TransitRouteStyle._();

  /// Road route still to drive, styled like Google Maps: a darker casing
  /// under the blue line.
  static const Color routeColor = Color(0xFF4285F4);
  static const Color casingColor = Color(0xFF1A5DC8);
  static const int routeWidth = 6;
  static const int casingWidth = 9;

  /// Where the transporter has already been (cases/{id}/tracking).
  static Color get trailColor => AppColors.textPrimary.withValues(alpha: 0.35);
  static const int trailWidth = 3;

  /// Re-request the road route once the rider is this far from where it
  /// was last requested, or this far off the drawn line.
  static const double refetchAfterMovingMeters = 200;
  static const double offRouteMeters = 60;

  /// The road route: casing + line.
  static Set<Polyline> route(List<LatLng> points) => {
        Polyline(
          polylineId: const PolylineId('directions_casing'),
          points: points,
          color: casingColor,
          width: casingWidth,
          zIndex: 1,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
        Polyline(
          polylineId: const PolylineId('directions_route'),
          points: points,
          color: routeColor,
          width: routeWidth,
          zIndex: 2,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      };

  /// No road route yet: a dashed straight line toward the stop.
  static Set<Polyline> straightLine(List<LatLng> points) => {
        Polyline(
          polylineId: const PolylineId('straight_line'),
          points: points,
          color: routeColor.withValues(alpha: 0.7),
          width: 4,
          zIndex: 1,
          patterns: [PatternItem.dash(20), PatternItem.gap(12)],
        ),
      };

  static Polyline trail(List<LatLng> points) => Polyline(
        polylineId: const PolylineId('route_trail'),
        points: points,
        color: trailColor,
        width: trailWidth,
        zIndex: 0,
      );
}

double _metersBetween(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

/// The closest point to [p] on segment [a]-[b] (flat-earth projection,
/// fine at street scale) and how far along the segment it is (0..1).
({LatLng point, double t}) _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(a.latitude * math.pi / 180);
  final ax = a.longitude * cosLat, ay = a.latitude;
  final bx = b.longitude * cosLat, by = b.latitude;
  final px = p.longitude * cosLat, py = p.latitude;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  return (
    point: LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t),
    t: t,
  );
}

/// The part of [route] still ahead of [rider]: the rider's position snapped
/// onto the line, then the rest of the line. Lets the drawn route shrink
/// behind the rider as they drive, like a transit app. Also returns how far
/// the rider is from the line, to tell when the route needs re-requesting.
({List<LatLng> points, double offRouteMeters}) remainingRoute(List<LatLng> route, LatLng rider) {
  if (route.length < 2) return (points: route, offRouteMeters: 0);
  var bestIndex = 0;
  var bestPoint = route.first;
  var bestDistance = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    final proj = _projectOnSegment(rider, route[i], route[i + 1]);
    final d = _metersBetween(rider, proj.point);
    if (d < bestDistance) {
      bestDistance = d;
      bestIndex = i;
      bestPoint = proj.point;
    }
  }
  return (
    points: [rider, if (_metersBetween(rider, bestPoint) > 1) bestPoint, ...route.sublist(bestIndex + 1)],
    offRouteMeters: bestDistance,
  );
}

/// Linear interpolation between two positions.
LatLng lerpLatLng(LatLng a, LatLng b, double t) =>
    LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);

/// Compass bearing from [a] to [b], degrees clockwise from north.
double bearingBetween(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180, lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Moves a map marker smoothly from one reported position to the next
/// instead of jumping, the way transit apps glide the vehicle along.
/// Positions arrive every ~15 m of travel (the transporter's GPS
/// distanceFilter); each glide lasts about as long as the gap between the
/// last two reports, so the marker keeps moving until the next one lands.
class SmoothPositionAnimator {
  SmoothPositionAnimator({required TickerProvider vsync, required VoidCallback onTick})
      : _controller = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 1200)) {
    _controller.addListener(() {
      final from = _from, to = _to;
      if (from == null || to == null) return;
      _current = lerpLatLng(from, to, Curves.linear.transform(_controller.value));
      onTick();
    });
  }

  final AnimationController _controller;
  LatLng? _from;
  LatLng? _to;
  LatLng? _current;
  DateTime? _lastTargetAt;
  double _bearing = 0;

  /// Where the marker is drawn right now; null before the first report.
  LatLng? get position => _current;
  double get bearing => _bearing;

  /// A new reported position. The first one is shown as-is; later ones are
  /// glided to. A jump of over 2 km (a stale or corrected fix) snaps.
  void moveTo(LatLng target) {
    if (_to != null && _to!.latitude == target.latitude && _to!.longitude == target.longitude) return;
    final now = DateTime.now();
    final start = _current;
    if (start == null || _metersBetween(start, target) > 2000) {
      _controller.stop();
      _from = target;
      _to = target;
      _current = target;
      _lastTargetAt = now;
      return;
    }
    final gap = _lastTargetAt == null ? 1200 : now.difference(_lastTargetAt!).inMilliseconds;
    _lastTargetAt = now;
    if (_metersBetween(start, target) > 2) _bearing = bearingBetween(start, target);
    _from = start;
    _to = target;
    _controller.duration = Duration(milliseconds: gap.clamp(600, 4000));
    _controller.forward(from: 0);
  }

  void dispose() => _controller.dispose();
}
