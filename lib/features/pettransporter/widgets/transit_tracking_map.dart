// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:respawnd1/core/repos/directions_repository.dart';

//Tracking map
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
  GoogleMapController? _controller;
  bool _centered = false;

  DirectionsRoute? _route;
  LatLng? _routeFetchedFor;
  LatLng? _routeFetchedFrom;
  Timer? _routeRefreshTimer;

  @override
  void dispose() {
    _routeRefreshTimer?.cancel();
    super.dispose();
  }

  void _maybeRefreshRoute(LatLng riderPosition) {
    if (widget.destination == null) {
      debugPrint('_maybeRefreshRoute: no destination set yet, skipping.');
      return;
    }

    final destChanged =
        _routeFetchedFor == null ||
        _routeFetchedFor!.latitude != widget.destination!.latitude ||
        _routeFetchedFor!.longitude != widget.destination!.longitude;

    final movedFar =
        _routeFetchedFrom == null ||
        Geolocator.distanceBetween(
              _routeFetchedFrom!.latitude,
              _routeFetchedFrom!.longitude,
              riderPosition.latitude,
              riderPosition.longitude,
            ) >
            200;

    if (!destChanged && !movedFar) return;

    _routeFetchedFor = widget.destination;
    _routeFetchedFrom = riderPosition;

    debugPrint(
      '_maybeRefreshRoute: fetching route from $riderPosition to '
      '${widget.destination} (${widget.destinationLabel})',
    );

    fetchDirectionsRoute(riderPosition, widget.destination!).then((route) {
      if (route == null) {
        debugPrint(
          '_maybeRefreshRoute: fetchDirectionsRoute returned null — see '
          'fetchDirectionsRoute logs above for the actual reason.',
        );
        return;
      }
      if (mounted) {
        setState(() => _route = route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('tracking')
          .orderBy('timestamp')
          .limitToLast(100)
          .snapshots(),
      builder: (context, snapshot) {
        final points = <LatLng>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final lat = d['lat'];
            final lng = d['lng'];
            if (lat is num && lng is num) {
              points.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }
        }

        final initialCenter = points.isNotEmpty
            ? points.last
            : const LatLng(14.5995, 120.9842);

        if (_controller != null && points.isNotEmpty && !_centered) {
          _centered = true;
          _controller!.animateCamera(
            CameraUpdate.newLatLngZoom(points.last, 15),
          );
        }

        if (points.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _maybeRefreshRoute(points.last),
          );
        }

        final markers = <Marker>{};
        if (points.isNotEmpty) {
          markers.add(
            Marker(
              markerId: const MarkerId('rider_current'),
              position: points.last,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              zIndexInt: 2,
              infoWindow: const InfoWindow(title: 'You'),
            ),
          );
        }
        if (widget.destination != null) {
          markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: widget.destination!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(
                title: widget.destinationLabel,
                snippet: _route == null
                    ? null
                    : '${_route!.distanceText} • ${_route!.durationText}',
              ),
            ),
          );
        }

        final polylines = <Polyline>{};
        if (points.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route_trail'),
              points: points,
              color: AppColors.textPrimary.withValues(alpha: 0.35),
              width: 3,
              zIndex: 0,
            ),
          );
        }

        if (_route != null && _route!.points.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('directions_route'),
              points: _route!.points,
              color: const Color(0xFF4285F4),
              width: 6,
              zIndex: 1,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
        }

        return Stack(
          children: [
            GoogleMap(
              onMapCreated: (ctrl) {
                _controller = ctrl;
                widget.onMapCreated(ctrl);
              },
              initialCameraPosition: CameraPosition(
                target: initialCenter,
                zoom: 14,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: markers,
              polylines: polylines,
            ),

            if (_route != null && widget.destination != null)
              Positioned(
                bottom: 90,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 15,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_route!.durationText} to ${widget.destinationLabel} • ${_route!.distanceText}',
                          style: GoogleFonts.zain(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
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
