import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:respawnd1/core/constants/maps_config.dart';
import '../../../app_theme.dart';

/// Result handed back to whoever pushed [LastSeenLocationPicker].
class PickedLostLocation {
  final double lat;
  final double lng;
  final String address;

  const PickedLostLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

/// Tap-to-pin picker — originally built for the collar tag's "Mark as Lost"
/// action so the owner can drop a pin on exactly where the pet was last
/// seen, and now the shared source of truth for any "confirm a real map
/// location" flow (Community Reports' "Animal moved" update reuses this
/// exact widget rather than a second copy — see community_report_section.
/// dart). Mirrors the same map + address-search pattern already used for
/// pinning a rescue location in rescue_page.dart, so the interaction feels
/// familiar across the app.
///
/// [title]/[instructionText]/[pinLabel]/[confirmLabel] default to the
/// original collar-tag copy so that call site needs no changes; other
/// callers override them for their own context.
///
/// Returns a [PickedLostLocation] via Navigator.pop if the person confirms a
/// location, or `null` if they back out.
class LastSeenLocationPicker extends StatefulWidget {
  final String petName;
  final String? title;
  final String? instructionText;
  final String pinLabel;
  final String? confirmLabel;

  const LastSeenLocationPicker({
    super.key,
    this.petName = 'your pet',
    this.title,
    this.instructionText,
    this.pinLabel = 'Pinned location',
    this.confirmLabel,
  });

  @override
  State<LastSeenLocationPicker> createState() => _LastSeenLocationPickerState();
}

class _LastSeenLocationPickerState extends State<LastSeenLocationPicker> {
  final _addressController = TextEditingController();
  GoogleMapController? _mapController;

  LatLng _pinnedLocation = const LatLng(14.5995, 120.9842);
  bool _hasResolvedLocation = false;
  String _pinnedAddress = 'Fetching location…';
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _fallbackToLastKnownOrDefault(String reasonMessage) async {
    if (_hasResolvedLocation) {
      if (mounted) setState(() => _loadingLocation = false);
      return;
    }
    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {
      lastKnown = null;
    }
    if (lastKnown != null) {
      await _updatePin(LatLng(lastKnown.latitude, lastKnown.longitude));
      return;
    }
    if (mounted) {
      setState(() {
        _loadingLocation = false;
        _pinnedAddress = reasonMessage;
      });
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _loadingLocation = true);

    if (!_hasResolvedLocation) {
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null && mounted) {
          await _updatePin(LatLng(cached.latitude, cached.longitude));
        }
      } catch (_) {}
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please enable location services for accurate pinning.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        await _fallbackToLastKnownOrDefault(
            'Location services disabled — tap the map to pin manually.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted && permission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission permanently denied.'),
              action: SnackBarAction(
                label: 'App Settings',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        await _fallbackToLastKnownOrDefault(
            'Location permission denied — tap the map to pin manually.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).then<Position?>((p) => p).timeout(
        const Duration(seconds: 15),
        onTimeout: () => Geolocator.getLastKnownPosition(),
      );

      if (pos != null) {
        await _updatePin(LatLng(pos.latitude, pos.longitude));
      } else {
        await _fallbackToLastKnownOrDefault(
            'Could not get your location — tap the map to pin manually.');
      }
    } catch (_) {
      await _fallbackToLastKnownOrDefault(
          'Could not get location — tap the map to pin manually.');
    }
  }

  Future<void> _updatePin(LatLng pos) async {
    setState(() {
      _pinnedLocation = pos;
      _hasResolvedLocation = true;
      _pinnedAddress = 'Resolving address…';
      _loadingLocation = true;
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17)),
    );

    String resolvedAddress;
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${pos.latitude},${pos.longitude}'
            '&key=${MapsConfig.placesApiKey}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        resolvedAddress = data['results'][0]['formatted_address'];
      } else {
        resolvedAddress =
        '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } catch (_) {
      resolvedAddress =
      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    }

    if (!mounted) return;
    setState(() {
      _pinnedAddress = resolvedAddress;
      _loadingLocation = false;
    });
  }

  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loadingLocation = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(address)}'
            '&key=${MapsConfig.placesApiKey}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        final loc = data['results'][0]['geometry']['location'];
        final latLng = LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
        _addressController.text = data['results'][0]['formatted_address'];
        await _updatePin(latLng);
      } else {
        if (mounted) {
          setState(() => _loadingLocation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find that address.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Address search failed: $e')),
        );
      }
    }
  }

  void _confirm() {
    if (!_hasResolvedLocation) return;
    Navigator.pop(
      context,
      PickedLostLocation(
        lat: _pinnedLocation.latitude,
        lng: _pinnedLocation.longitude,
        address: _addressController.text.trim().isEmpty
            ? _pinnedAddress
            : _addressController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title ?? 'Where was ${widget.petName} last seen?',
          style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.instructionText ??
                  'Tap anywhere on the map to drop a pin, or search an address '
                      'below. This pin is what other users will see on the Explore '
                      'Reports map.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 14),

          // Map
          Stack(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 300,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.hardEdge,
                child: GoogleMap(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                    ),
                  },
                  onMapCreated: (ctrl) => _mapController = ctrl,
                  initialCameraPosition: CameraPosition(
                    target: _pinnedLocation,
                    zoom: 15,
                  ),
                  onTap: _updatePin,
                  markers: _hasResolvedLocation
                      ? {
                    Marker(
                      markerId: const MarkerId('last_seen_pin'),
                      position: _pinnedLocation,
                      infoWindow:
                      InfoWindow(title: '${widget.petName} — last seen here'),
                    ),
                  }
                      : {},
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              Positioned(
                bottom: 10,
                right: 26,
                child: GestureDetector(
                  onTap: _fetchCurrentLocation,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _loadingLocation
                        ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    )
                        : const Icon(Icons.my_location,
                        size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Address search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        hintText: 'Search address…',
                        hintStyle: GoogleFonts.zain(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 16),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _geocodeAddress,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _geocodeAddress(_addressController.text),
                    child: const Icon(Icons.arrow_forward_ios,
                        size: 16, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Pinned location display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.pinLabel,
                    style: GoogleFonts.tiltWarp(fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.textPrimary, width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _pinnedAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_hasResolvedLocation && !_loadingLocation) ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  widget.confirmLabel ?? 'Confirm Last Seen Location',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}