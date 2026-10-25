import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';


class ServiceFilterSheet extends StatefulWidget {
  final double initialRange;
  final ValueChanged<double> onApply;
  // The rider's last-known location (e.g. ServiceScreen's _currentLocation).
  // If null — the rider opened the filter before ever going online — the
  // sheet resolves its own location so the map still has something real to
  // center on.
  final LatLng? currentLocation;

  const ServiceFilterSheet({
    required this.initialRange,
    required this.onApply,
    this.currentLocation,
  });

  @override
  State<ServiceFilterSheet> createState() =>
      _ServiceFilterSheetState();
}

class _ServiceFilterSheetState
    extends State<ServiceFilterSheet> {
  late double _range;
  GoogleMapController? _mapController;
  LatLng? _center;
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _center = widget.currentLocation;
    if (_center == null) {
      _resolveLocation();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _resolveLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() => _center = LatLng(pos.latitude, pos.longitude));
        // Wait a frame so the map's finished attaching before we move it.
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitToRange());
      }
    } catch (_) {
      // Fall back to the map's "location unavailable" state below.
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // A rough (but plenty accurate for a filter preview) lat/lng bounding box
  // for a circle of the given radius around center.
  LatLngBounds _boundsForRadius(LatLng center, double km) {
    final latDelta = km / 111.0;
    final lngDelta =
        km / (111.0 * math.cos(center.latitude * math.pi / 180)).abs();
    return LatLngBounds(
      southwest: LatLng(center.latitude - latDelta, center.longitude - lngDelta),
      northeast: LatLng(center.latitude + latDelta, center.longitude + lngDelta),
    );
  }

  void _fitToRange() {
    final center = _center;
    final controller = _mapController;
    if (controller == null || center == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsForRadius(center, _range), 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F0DC),
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 16),

          // Back arrow + Title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left, size: 28),
              ),
              const SizedBox(width: 4),
              Text(
                'Filter Service Availability',
                style: GoogleFonts.tiltWarp(
                    fontSize: 18,
                    color: AppColors.textPrimary),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Service Range label + value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Service Range',
                  style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text('${_range.toInt()} KM radius',
                  style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ],
          ),

          const SizedBox(height: 12),

          // Live map — centered on the rider, with a circle showing the
          // selected service range.
          Container(
            height: 200,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: AppColors.slaterspwn,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _center == null
                ? Center(
              child: _loadingLocation
                  ? const CircularProgressIndicator(
                  color: AppColors.textPrimary)
                  : Text('Location unavailable',
                  style: GoogleFonts.nunito(
                      fontSize: 13, color: AppColors.textPrimary)),
            )
                : GoogleMap(
              initialCameraPosition:
              CameraPosition(target: _center!, zoom: 11),
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _fitToRange());
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('service_center'),
                  position: _center!,
                ),
              },
              circles: {
                Circle(
                  circleId: const CircleId('service_range'),
                  center: _center!,
                  radius: _range * 1000,
                  fillColor: AppColors.greenrspwn.withValues(alpha: 0.15),
                  strokeColor: AppColors.greenrspwn,
                  strokeWidth: 2,
                ),
              },
            ),
          ),

          const SizedBox(height: 16),

          // Range slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.textPrimary,
              inactiveTrackColor: AppColors.slaterspwn,
              thumbColor: AppColors.textPrimary,
              overlayColor:
              AppColors.textPrimary.withValues(alpha: 0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: _range,
              min: 1,
              max: 200,
              divisions: 199,
              onChanged: (v) => setState(() => _range = v),
              onChangeEnd: (_) => _fitToRange(),
            ),
          ),

          const SizedBox(height: 12),

          // Apply button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_range);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5C842),
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Apply',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}