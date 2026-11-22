// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/widgets/transit_route.dart';

/// The transporter's in-app map: the driving route from where they are to
/// the current stop (pick up, clinic or shelter), drawn from Google
/// Directions like Google Maps' own route line, with the time and distance
/// left. The route follows the transporter and refreshes as they drive;
/// the Navigate button still opens turn-by-turn directions in Google Maps.
class TransitTrackingMap extends StatefulWidget {
  final String caseId;
  final void Function(GoogleMapController) onMapCreated;
  final LatLng? destination;
  final String destinationLabel;

  const TransitTrackingMap({
    super.key,
    required this.caseId,
    required this.onMapCreated,
    this.destination,
    this.destinationLabel = 'Destination',
  });

  @override
  State<TransitTrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<TransitTrackingMap> {
  // Created once: a new stream on every rebuild re-read up to 100 tracking
  // points each time the transit page redrew.
  late Stream<QuerySnapshot> _tracking = _trackingFor(widget.caseId);

  static Stream<QuerySnapshot> _trackingFor(String caseId) => FirebaseFirestore.instance
      .collection('cases')
      .doc(caseId)
      .collection('tracking')
      .orderBy('timestamp')
      .limitToLast(100)
      .snapshots();

  GoogleMapController? _controller;

  // The phone's own position, so the route can be drawn straight away
  // instead of waiting for the first saved tracking point (saved at most
  // every 10 s, and only once the trip has started).
  LatLng? _me;
  StreamSubscription<Position>? _positionSub;

  DirectionsRoute? _route;
  LatLng? _routeFetchedFor;
  LatLng? _routeFetchedFrom;
  DateTime? _lastRouteAttempt;
  bool _routeFailed = false;
  bool _fetching = false;
  LatLng? _fittedFor;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  Future<void> _startLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _onPosition(last);
    } catch (_) {}
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onPosition, onError: (_) {});
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    setState(() => _me = LatLng(pos.latitude, pos.longitude));
    _maybeRefreshRoute();
  }

  @override
  void didUpdateWidget(TransitTrackingMap old) {
    super.didUpdateWidget(old);
    if (old.caseId != widget.caseId) _tracking = _trackingFor(widget.caseId);
    if (old.destination != widget.destination) {
      // New stop: forget the old route at once and fetch the new one.
      _route = null;
      _routeFailed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefreshRoute());
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  LatLng? _origin(List<LatLng> trail) => _me ?? (trail.isEmpty ? null : trail.last);

  void _maybeRefreshRoute([List<LatLng> trail = const []]) {
    final destination = widget.destination;
    final origin = _origin(trail);
    if (destination == null || origin == null || _fetching) return;

    final destChanged = _routeFetchedFor != destination;
    final movedFar = _routeFetchedFrom == null ||
        Geolocator.distanceBetween(
          _routeFetchedFrom!.latitude,
          _routeFetchedFrom!.longitude,
          origin.latitude,
          origin.longitude,
        ) >
            200;
    // A failed request is retried after 30 s rather than never.
    final retryDue = _routeFailed &&
        (_lastRouteAttempt == null ||
            DateTime.now().difference(_lastRouteAttempt!) > const Duration(seconds: 30));
    if (!destChanged && !movedFar && !retryDue) return;

    _routeFetchedFor = destination;
    _routeFetchedFrom = origin;
    _lastRouteAttempt = DateTime.now();
    _fetching = true;
    fetchDirectionsRoute(origin, destination).then((route) {
      if (!mounted) return;
      setState(() {
        _route = route ?? (destChanged ? null : _route);
        _routeFailed = route == null;
      });
      if (route != null) _fitToRoute(route.points, destination);
    }).whenComplete(() => _fetching = false);
  }

  /// Zooms the map out to show the whole route, once per destination.
  void _fitToRoute(List<LatLng> points, LatLng destination) {
    final controller = _controller;
    if (controller == null || points.isEmpty || _fittedFor == destination) return;
    _fittedFor = destination;
    var minLat = points.first.latitude, maxLat = minLat;
    var minLng = points.first.longitude, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _tracking,
      builder: (context, snapshot) {
        final trail = <LatLng>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final lat = d['lat'];
            final lng = d['lng'];
            if (lat is num && lng is num) {
              trail.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }
        }
        final origin = _origin(trail);
        if (_me == null && trail.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefreshRoute(trail));
        }

        final markers = <Marker>{
          if (origin != null)
            Marker(
              markerId: const MarkerId('rider_current'),
              position: origin,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              zIndexInt: 2,
              infoWindow: const InfoWindow(title: 'You'),
            ),
          if (widget.destination != null)
            Marker(
              markerId: const MarkerId('destination'),
              position: widget.destination!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(
                title: widget.destinationLabel,
                snippet: _route == null ? null : '${_route!.distanceText} • ${_route!.durationText}',
              ),
            ),
        };

        final route = _route;
        // Same lines as the admin Track Case map (TransitRouteStyle): the
        // trail already driven, and Google's driving route still ahead,
        // trimmed at the transporter so it shrinks as they drive.
        final polylines = <Polyline>{
          if (trail.length >= 2) TransitRouteStyle.trail(trail),
          if (route != null && route.points.length >= 2)
            ...TransitRouteStyle.route(
              origin == null ? route.points : remainingRoute(route.points, origin).points,
            )
          // No route from Google yet: a dashed straight line so the stop's
          // direction is still clear.
          else if (origin != null && widget.destination != null)
            ...TransitRouteStyle.straightLine([origin, widget.destination!]),
        };

        final banner = widget.destination == null
            ? null
            : route != null
            ? '${route.durationText} to ${widget.destinationLabel} • ${route.distanceText}'
            : _routeFailed
            ? 'Route unavailable right now — retrying. Use Navigate for directions.'
            : origin == null
            ? 'Finding your location…'
            : 'Loading route to ${widget.destinationLabel}…';

        return Stack(
          children: [
            GoogleMap(
              onMapCreated: (ctrl) {
                _controller = ctrl;
                widget.onMapCreated(ctrl);
                final r = _route;
                if (r != null && widget.destination != null) {
                  _fitToRoute(r.points, widget.destination!);
                } else if (origin != null) {
                  ctrl.moveCamera(CameraUpdate.newLatLngZoom(origin, 15));
                }
              },
              initialCameraPosition: CameraPosition(
                target: origin ?? widget.destination ?? const LatLng(14.5995, 120.9842),
                zoom: 14,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              trafficEnabled: true,
              markers: markers,
              polylines: polylines,
            ),
            if (banner != null)
              Positioned(
                bottom: 90,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          route != null ? Icons.access_time : Icons.route,
                          size: 15,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            banner,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
