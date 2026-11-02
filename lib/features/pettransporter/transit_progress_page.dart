import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/features/pettransporter/services/transit_case_service.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';
import 'package:respawnd1/features/pettransporter/widgets/close_transit_dialog.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/awaiting_adopter_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/clinic_decision_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/searching_clinic_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/standard_progress_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/verification_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_info_widgets.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_messages.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_result_page.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_tracking_map.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_unread_badge.dart';
import 'package:respawnd1/features/pettransporter/widgets/treatment_reject_dialog.dart';

// Moved out of this file; re-exported so existing imports of
// transit_progress_page.dart that use these keep compiling unchanged.
export 'package:respawnd1/core/repos/directions_repository.dart'
    show DirectionsRoute, fetchDirectionsRoute, decodePolyline;
export 'package:respawnd1/features/pettransporter/widgets/transit_result_page.dart'
    show TransitResultPage;

String get _placesApiKey => MapsConfig.placesApiKey;

String get _directionsApiKey => MapsConfig.directionsApiKey;

const double _arrivalThresholdMeters = 150;

// Temporary default shelter — used whenever
// OrganizationDirectoryRepository.resolveShelterLocation comes back null,
// which per that method's own doc comment is still the common case today
// (org-membership backfill hasn't happened for most test accounts). Without
// this, a case with no org-registered shelter would show "Shelter address
// not available" and have no coordinates to route/verify arrival against.
// Remove once every organization has a real shelter location configured.
// Default shelter, used when the case's organization has no registered
// shelter location (OrganizationDirectoryRepository.resolveShelterLocation
// returns null).
const String _fallbackShelterName = 'Loved by the Gapz Shelter - Rodriguez';
const String _fallbackShelterAddress =
    'Sitio Maislap, Brgy. San Isidro, Rodriguez, Rizal, Philippines';
// APPROXIMATE coordinates for Brgy. San Isidro, Rodriguez, Rizal. The
// shelter arrival geofence is only 150 m, so replace these with the exact
// pin (Google Maps → long-press the shelter → copy the numbers).
// _resolveFallbackShelterLatLng() geocodes the address first and only
// uses these if geocoding fails.
const double _fallbackShelterLat = 14.7350;
const double _fallbackShelterLng = 121.1590;

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
    LatLng origin, LatLng destination) async {
  try {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'key': _directionsApiKey,
      },
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      debugPrint(
          'fetchDirectionsRoute: HTTP ${res.statusCode} — ${res.body}');
      return null;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') {
      debugPrint(
          'fetchDirectionsRoute: status=${body['status']} '
              'error_message=${body['error_message']}');
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

// Status
// accepted         - rider accepted, not yet started
// ongoing          - otw to pickup
// arrived          - arrived at pickup, verify
// treatment        - picked up, otw to clinic
// dropoff          - arrived at a clinic, awaiting Treatment Accepted/Rejected
// searching_clinic - clinic rejected treatment, auto-searching next nearby clinic
// in_transit_shelter - treatment accepted, on the way to drop the pet at the shelter
// completed        - rescue done (delivered to shelter)
// ended            - aborted

class TransitProgressPage extends StatefulWidget {
  final String caseId;
  const TransitProgressPage({super.key, required this.caseId});

  @override
  State<TransitProgressPage> createState() => _TransitProgressPageState();
}

class _TransitProgressPageState extends State<TransitProgressPage> {
  final _messageController = TextEditingController();
  final _picker = ImagePicker();
  late final TransitCaseService _service = TransitCaseService(widget.caseId);
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  bool _isActing = false;
  bool _isSearchingClinic = false;
  bool _autoSearchAttempted = false;
  bool _isVerifyingArrival = false;
  Timestamp? _lastReadAt;

  // Arrival geofences — latest case snapshot (set in build) so the GPS
  // stream can tell which stop the rider is heading to.
  Map<String, dynamic>? _latestCase;
  bool _autoArriving = false;
  String? _autoArrivedFor;

  // Verification geofence — photo verification (pickup, clinic, shelter)
  // is only allowed while the rider's live GPS is within
  // _arrivalThresholdMeters of the stop being verified.
  Position? _lastRiderPosition;
  double? _distanceToStopMeters;
  String? _proximityStatus; // status the distance above was computed for

  @override
  void initState() {
    super.initState();
    _lastReadAt = Timestamp.now();
  }

  // Verification images
  final List<File?> _pickupImages = [null, null];
  final List<File?> _clinicImages = [
    null,
    null,
  ]; // arrived-at-clinic verification
  final List<File?> _shelterImages = [
    null,
    null,
  ]; // final shelter drop-off verification

  @override
  void dispose() {
    _messageController.dispose();
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// False (with a snackbar) when none of [images] has been taken yet.
  bool _hasVerificationImage(List<File?> images) {
    if (images.every((f) => f == null)) {
      _showError('Please add at least one verification image.');
      return false;
    }
    return true;
  }

  void _openResultPage({required bool completed, String? reason}) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TransitResultPage(completed: completed, reason: reason),
      ),
    );
  }

  // Location streaming
  void _beginLocationStreaming() {
    if (_positionSub != null) return;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) {
      FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('tracking')
          .add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'riderLastLat': pos.latitude,
        'riderLastLng': pos.longitude,
      });
      _mapController
          ?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
      _checkArrivalGeofence(pos);
      _updateStopProximity(pos);
    });
  }

  /// The stop whose photo verification is due in [status], or null when the
  /// current status has no photo verification step.
  ({LatLng? target, String place})? _verificationStopFor(
      String status, Map<String, dynamic> data) {
    switch (status) {
      case 'arrived':
        return (target: _latLngFrom(data, 'lat', 'lng'), place: 'the pick up location');
      case 'dropoff':
        return (target: _clinicLatLngFrom(data), place: 'the clinic');
      case 'in_transit_shelter':
        return (target: _latLngFrom(data, 'shelterLat', 'shelterLng'), place: 'the shelter');
      default:
        return null;
    }
  }

  void _updateStopProximity(Position pos) {
    _lastRiderPosition = pos;
    final data = _latestCase;
    if (data == null || !mounted) return;
    final stop = _verificationStopFor(data['status'] as String? ?? '', data);
    final target = stop?.target;
    final meters = target == null
        ? null
        : Geolocator.distanceBetween(
        pos.latitude, pos.longitude, target.latitude, target.longitude);
    if (meters != _distanceToStopMeters) {
      setState(() => _distanceToStopMeters = meters);
    }
  }

  Future<void> _refreshStopProximity() async {
    final known = _lastRiderPosition;
    if (known != null) {
      _updateStopProximity(known);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _updateStopProximity(pos);
    } catch (_) {
      // The live stream will fill it in on the next GPS update.
    }
  }

  /// True when the rider is inside the current stop's geofence. A stop with
  /// no saved coordinates can't be geofenced, so it isn't blocked.
  bool _isAtVerificationStop(Map<String, dynamic> data) {
    final stop = _verificationStopFor(data['status'] as String? ?? '', data);
    if (stop == null || stop.target == null) return true;
    final d = _distanceToStopMeters;
    return d != null && d <= _arrivalThresholdMeters;
  }

  /// Fresh GPS check right before uploading verification photos, so a stale
  /// stream reading can't let a submission through from somewhere else.
  Future<bool> _ensureAtVerificationStop(Map<String, dynamic> data) async {
    final stop = _verificationStopFor(data['status'] as String? ?? '', data);
    final target = stop?.target;
    if (stop == null || target == null) return true;
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _updateStopProximity(pos);
      final meters = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, target.latitude, target.longitude);
      if (meters <= _arrivalThresholdMeters) return true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("You're ~${meters.round()} m from ${stop.place}. "
              'Photo verification only works at the location.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not check your location: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return false;
    }
  }

  /// Opens the camera for a verification photo only inside the geofence.
  Future<void> _pickVerificationImage(
      List<File?> slot, int index, Map<String, dynamic> data) async {
    if (!_isAtVerificationStop(data)) {
      final stop = _verificationStopFor(data['status'] as String? ?? '', data);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Photo verification unlocks when you are at '
            '${stop?.place ?? 'the location'} (within ${_arrivalThresholdMeters.round()} m).'),
      ));
      return;
    }
    await _pickImage(slot, index);
  }

  /// Banner on every photo-verification panel showing whether the rider is
  /// inside the stop's geofence.
  Widget _buildGeofenceBanner(Map<String, dynamic> data) {
    final stop = _verificationStopFor(data['status'] as String? ?? '', data);
    if (stop == null) return const SizedBox.shrink();

    final String text;
    final Color color;
    final IconData icon;
    if (stop.target == null) {
      text = 'No saved coordinates for ${stop.place}, so your location can\'t be checked.';
      color = AppColors.textSecondary;
      icon = Icons.info_outline;
    } else if (_distanceToStopMeters == null) {
      text = 'Checking your location…';
      color = AppColors.textSecondary;
      icon = Icons.my_location;
    } else if (_isAtVerificationStop(data)) {
      text = "You're at ${stop.place} (detected by geofence). You can submit photo verification.";
      color = Colors.green.shade700;
      icon = Icons.verified;
    } else {
      text = "You're ~${_distanceToStopMeters!.round()} m from ${stop.place}. "
          'Photo verification unlocks within ${_arrivalThresholdMeters.round()} m.';
      color = Colors.orange.shade800;
      icon = Icons.location_searching;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  /// Geocodes the default shelter address once per page; falls back to the
  /// approximate constants if geocoding isn't available.
  Future<LatLng> _resolveFallbackShelterLatLng() async {
    try {
      final results = await locationFromAddress(_fallbackShelterAddress)
          .timeout(const Duration(seconds: 8));
      if (results.isNotEmpty) {
        return LatLng(results.first.latitude, results.first.longitude);
      }
    } catch (_) {
      // fall through to the constants
    }
    return const LatLng(_fallbackShelterLat, _fallbackShelterLng);
  }

  // Arrival geofences: a circle of _arrivalThresholdMeters around the
  // current stop. Entering it moves the case on automatically —
  //   pickup  : ongoing   -> arrived  (reporter is notified by
  //             notifyCaseGeofenceEvents in functions/index.js)
  //   clinic  : treatment -> dropoff
  //   shelter : in_transit_shelter -> prompt only, because completing a
  //             shelter drop-off still needs the verification photos.
  // The manual "Arrived" buttons keep working as before.
  Future<void> _checkArrivalGeofence(Position pos) async {
    final data = _latestCase;
    if (data == null || _autoArriving || _isActing || !mounted) return;
    final status = data['status'] as String? ?? '';

    LatLng? target;
    String? nextStatus;
    String? statusLabel;
    String place;
    if (status == 'ongoing') {
      target = _latLngFrom(data, 'lat', 'lng');
      nextStatus = 'arrived';
      statusLabel = 'Arrived at pick up location.';
      place = 'the pick up location';
    } else if (status == 'treatment') {
      target = _clinicLatLngFrom(data);
      nextStatus = 'dropoff';
      statusLabel = 'Arrived at clinic for treatment.';
      place = 'the clinic';
    } else if (status == 'in_transit_shelter') {
      target = _latLngFrom(data, 'shelterLat', 'shelterLng');
      place = 'the shelter';
    } else {
      return;
    }
    if (target == null) return;

    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      target.latitude,
      target.longitude,
    );
    if (meters > _arrivalThresholdMeters) return;

    final key = '$status@${target.latitude},${target.longitude}';
    if (_autoArrivedFor == key) return;
    _autoArrivedFor = key;

    if (nextStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You're at $place. Add the drop-off photos, then tap Complete.")),
      );
      return;
    }

    _autoArriving = true;
    try {
      await _setStatus(nextStatus, '$statusLabel (detected by geofence)');
      await FirebaseFirestore.instance.collection('cases').doc(widget.caseId).set({
        'arrivalGeofence': {
          nextStatus: {
            'at': FieldValue.serverTimestamp(),
            'lat': pos.latitude,
            'lng': pos.longitude,
            'distanceMeters': meters.round(),
          },
        },
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Arrival detected — you're at $place.")),
        );
      }
    } catch (e) {
      debugPrint('Arrival geofence update failed: $e');
      _autoArrivedFor = null; // try again on the next GPS update
    } finally {
      _autoArriving = false;
    }
  }

  // Status transitions
  Future<void> _setStatus(String status, String statusLabel) async {
    setState(() => _isActing = true);
    try {
      await _service.setStatus(status, statusLabel);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _startTrip() async {
    await _setStatus('ongoing', 'On the way to pick up location.');
    _beginLocationStreaming();
  }

  Future<void> _launchNavigation(LatLng destination, String label) async {
    final uri = Uri(
      scheme: 'https',
      host: 'www.google.com',
      path: '/maps/dir/',
      queryParameters: {
        'api': '1',
        'destination': '${destination.latitude},${destination.longitude}',
        'travelmode': 'driving',
      },
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showMessage('Could not open Google Maps.');
    } catch (_) {
      _showMessage('Could not open Google Maps.');
    }
  }

  // Places a phone call to the given number, if available.
  Future<void> _launchCall(String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) {
      _showMessage('No phone number available.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showMessage('Could not start the call.');
    } catch (_) {
      _showMessage('Could not start the call.');
    }
  }

  Future<bool> _verifyArrivalViaDirections(
    LatLng? destination,
    String destinationLabel,
  ) async {
    if (destination == null) return true;

    setState(() => _isVerifyingArrival = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final origin = LatLng(pos.latitude, pos.longitude);
      final route = await fetchDirectionsRoute(origin, destination);

      if (route == null) {
        final straightLineMeters = Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          destination.latitude,
          destination.longitude,
        );

        if (straightLineMeters <= kArrivalThresholdMeters) {
          return true;
        }

        _showError(
          "Couldn't verify your route to $destinationLabel via Google Maps, and you're still "
          '~${straightLineMeters.round()}m away by straight-line distance — keep heading there before confirming arrival.',
        );
        return false;
      }

      if (route.distanceMeters > kArrivalThresholdMeters) {
        _showError(
          "You're still ${route.distanceText} from $destinationLabel according to Google Maps — keep heading there before confirming arrival.",
        );
        return false;
      }

      return true;
    } catch (e) {
      _showError('Could not check your location: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isVerifyingArrival = false);
    }
  }

  Future<void> _markArrived() async {
    final data = await _service.fetchCase();
    final destination = latLngFrom(data, 'lat', 'lng');

    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the pick up location',
    );
    if (!arrived) return;

    await _setStatus('arrived', 'Arrived at pick up location.');
  }

  Future<void> _arriveAtClinic() async {
    final data = await _service.fetchCase();
    final destination = clinicLatLngFrom(data);

    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the clinic',
    );
    if (!arrived) return;

    await _setStatus('dropoff', 'Arrived at clinic for treatment.');
  }

  Future<void> _submitPickupVerification() async {
    if (_pickupImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!await _ensureAtVerificationStop(_latestCase ?? const {})) return;
    setState(() => _isActing = true);
    try {
      final urls = await _service.uploadVerificationImages(
        _pickupImages,
        'pickup',
      );
      await _service.submitPickupVerification(urls);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // Shelter destination, interested-adopter routing and clinic logging are
  // handled by TransitCaseService.acceptTreatment.
  Future<void> _acceptTreatment() async {
    if (_clinicImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!await _ensureAtVerificationStop(_latestCase ?? const {})) return;
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(_clinicImages, 'clinic');
      final data = (await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .get())
          .data() as Map<String, dynamic>? ??
          {};

      // The case never had its own shelter destination — resolve the
      // assigned organization's registered shelter location (same source
      // the Intake flow uses) and snapshot it onto the case now, so the
      // in-transit-to-shelter panel/map/arrival-check all have a real
      // destination instead of falling back to placeholder text with no
      // coordinates at all.
      final shelter = await OrganizationDirectoryRepository()
          .resolveShelterLocation(data['organizationId'] as String?);
      final fallback = shelter == null ? await _resolveFallbackShelterLatLng() : null;

      // The reporter answered "yes" to "interested to adopt" on the
      // original report form (see rescue_page.dart's `interestedToAdopt`)
      // — that reporter is the intended adopter, so instead of continuing
      // on to the shelter, the transporter's job pauses here at the
      // clinic/treatment location until that adopter shows up in person
      // (see _buildAwaitingAdopterPanel / TrackCasePage's own "Arrived at
      // Treatment" button, which is what unlocks the "Adopter Arrived"
      // action below).
      final hasInterestedAdopter = data['interestedToAdopt'] == 'yes';
      final nextStatus =
      hasInterestedAdopter ? 'awaiting_adopter_pickup' : 'in_transit_shelter';
      final nextStatusLabel = hasInterestedAdopter
          ? 'Treatment accepted. Awaiting the interested adopter to arrive at the treatment location.'
          : 'Treatment accepted. On the way to shelter.';

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': nextStatus,
        'clinicVerificationUrls': urls,
        'shelterName': shelter?.name ?? _fallbackShelterName,
        'shelterAddress': shelter?.address ?? _fallbackShelterAddress,
        'shelterLat': shelter?.lat ?? fallback!.latitude,
        'shelterLng': shelter?.lng ?? fallback!.longitude,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': nextStatusLabel,
            'timestamp': Timestamp.now()
          }
        ]),
      });

      unawaited(_logClinicDecision(
        placeId: data['dropoffPlaceId'] as String?,
        name: (data['dropoffName'] ?? data['dropoffAddress'] ?? data['vetClinicAddress'] ?? 'Clinic')
            .toString(),
        address: _clinicAddressFrom(data),
        lat: (data['dropoffLat'] as num?)?.toDouble(),
        lng: (data['dropoffLng'] as num?)?.toDouble(),
        accepted: true,
      ));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _rejectTreatment() async {
    if (_clinicImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!await _ensureAtVerificationStop(_latestCase ?? const {})) return;
    final reason = await _showTreatmentRejectDialog();
    if (reason == null) return; // dismissed via X / back

    setState(() => _isActing = true);
    try {
      await _service.rejectTreatment(reason);

      // reset verification images for the next clinic attempt
      setState(() {
        for (int i = 0; i < _clinicImages.length; i++) {
          _clinicImages[i] = null;
        }
      });
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _findAndRouteToNextClinic() async {
    if (_isSearchingClinic) return;
    setState(() => _isSearchingClinic = true);
    try {
      await _service.findAndRouteToNextClinic();
    } catch (e) {
      _showError('Clinic search failed: $e');
    } finally {
      if (mounted) setState(() => _isSearchingClinic = false);
    }
  }

  Future<void> _completeShelterDropoff() async {
    if (!_hasVerificationImage(_shelterImages)) return;

    final doc = await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    // Same geofence check as every other photo verification step.
    if (!await _ensureAtVerificationStop(data)) return;

    setState(() => _isActing = true);
    try {
      final urls = await _service.uploadVerificationImages(
        _shelterImages,
        'shelter',
      );
      await _service.completeShelterDropoff(urls);
      _positionSub?.cancel();
      _openResultPage(completed: true);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // Triggered by the "Adopter Arrived" action in AwaitingAdopterPanel
  // — only reachable once the reporter has already tapped their own
  // "Arrived at Treatment" button in TrackCasePage (adopterArrivedAtTreatment
  // == true). This is the transporter's own in-person check: the reporter
  // tapping a button on their phone doesn't prove they're actually there,
  // so this asks the transporter — who can see with their own eyes — to
  // confirm before the case concludes. Answering "not yet" is a pure no-op:
  // the case stays at 'awaiting_adopter_pickup' exactly as it was, i.e.
  // "the pet transporter remains in progress with the transit".
  Future<void> _confirmAdopterPresent() async {
    final confirmed = await showConfirmAdopterPickupDialog(context);
    if (!confirmed) return; // "Not yet" — stay exactly as is.

    setState(() => _isActing = true);
    try {
      await _service.confirmAdopterPickup();
      _positionSub?.cancel();
      _openResultPage(completed: true);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _pickImage(List<File?> slot, int index) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      setState(() => slot[index] = File(picked.path));
    }
  }

  Future<void> _showCloseTransitDialog() async {
    final selection = await showCloseTransitDialog(context);
    if (selection == null) return; // closed with the X
    await _resolveEndReason(selection);
  }

  // The status decision for each End Reason is documented on
  // resolveEndReason (transit_rules.dart).
  Future<void> _resolveEndReason(EndReasonSelection selection) async {
    setState(() => _isActing = true);
    try {
      final outcome = resolveEndReason(selection);
      await _service.applyEndReason(outcome);

      _positionSub?.cancel();
      if (mounted) {
        if (outcome.isTerminal) {
          // A genuine terminal cancellation (Deceased, Vehicle breakdown,
          // Other) — show the same result screen used for a successful
          // completion, just with the cancelled variant + reason.
          _openResultPage(completed: false, reason: outcome.reasonText);
        } else {
          // Not Found / Reporter Unreachable / Aggressive / Specialized
          // transport don't end the case — it's still active (awaiting the
          // reporter, or escalated) — so just return the transporter to
          // where they came from instead of showing a "Cancelled" screen.
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  void _openMessageSheet() {
    setState(() => _lastReadAt = Timestamp.now());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),

              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Messages',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              Expanded(child: TransitMessagesList(caseId: widget.caseId)),

              SafeArea(
                child: TransitMessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _lastReadAt = Timestamp.now());
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await _service.sendMessage(text);
    _messageController.clear();
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('Case no longer exists.')),
          );
        }

        final status = data['status'] ?? 'accepted';
        _latestCase = data;
        // New stop (e.g. ongoing -> arrived): recompute the distance now —
        // the GPS stream only emits after 15 m of movement, so a rider
        // standing still at the stop would otherwise stay locked out.
        if (_proximityStatus != status) {
          _proximityStatus = status as String?;
          _distanceToStopMeters = null;
          WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStopProximity());
        }

        if ((status == 'ongoing' ||
                status == 'arrived' ||
                status == 'treatment' ||
                status == 'dropoff' ||
                status == 'searching_clinic' ||
                status == 'in_transit_shelter' ||
                status == 'awaiting_adopter_pickup') &&
            _positionSub == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _beginLocationStreaming(),
          );
        }

        if (status == 'searching_clinic') {
          if (!_isSearchingClinic && !_autoSearchAttempted) {
            _autoSearchAttempted = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _findAndRouteToNextClinic(),
            );
          }
        } else {
          _autoSearchAttempted = false;
        }

        LatLng? currentDestination;
        String currentDestinationLabel = '';
        if (status == 'ongoing' || status == 'arrived') {
          currentDestination = latLngFrom(data, 'lat', 'lng');
          currentDestinationLabel = 'Pick up location';
        } else if (status == 'treatment' || status == 'dropoff') {
          currentDestination = clinicLatLngFrom(data);
          currentDestinationLabel = 'Clinic';
        } else if (status == 'awaiting_adopter_pickup') {
          // Waiting at the clinic for the interested adopter — same
          // location as 'dropoff', just a later phase of the same stop.
          currentDestination = clinicLatLngFrom(data);
          currentDestinationLabel = 'Clinic';
        } else if (status == 'in_transit_shelter') {
          currentDestination = latLngFrom(data, 'shelterLat', 'shelterLng');
          currentDestinationLabel = 'Shelter';
        }

        return Theme(
          data: AppTheme.rescuerTheme,
          child: Scaffold(
            backgroundColor: AppColors.background,
            bottomNavigationBar: _buildBottomNav(),
            body: Column(
              children: [
                // Map
                Expanded(
                  flex: 2,
                  child: Stack(
                    children: [
                      TransitTrackingMap(
                        caseId: widget.caseId,
                        onMapCreated: (ctrl) => _mapController = ctrl,
                        destination: currentDestination,
                        destinationLabel: currentDestinationLabel,
                      ),

                      // Online badge
                      Positioned(
                        top: 48,
                        left: 16,
                        child: TransitOnlineBadge(),
                      ),

                      // Navigate button — opens turn-by-turn driving
                      // directions in the native Google Maps app, the same
                      // pattern Grab/Foodpanda driver apps use. Only shown
                      // once there's an actual destination to navigate to.
                      if (currentDestination != null)
                        Positioned(
                          bottom: 20,
                          left: 16,
                          child: FloatingActionButton.extended(
                            heroTag: 'navigate_btn',
                            backgroundColor: AppColors.textPrimary,
                            onPressed: () => _launchNavigation(
                              currentDestination!,
                              currentDestinationLabel,
                            ),
                            icon: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Navigate',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        bottom: 20,
                        right: 16,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            FloatingActionButton(
                              heroTag: 'chat_btn',
                              backgroundColor: AppColors.yellowrspwn,
                              onPressed: _openMessageSheet,
                              child: const Icon(
                                Icons.chat_bubble,
                                color: AppColors.textPrimary,
                              ),
                            ),

                            TransitUnreadBadge(
                              caseId: widget.caseId,
                              lastReadAt: _lastReadAt,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom panel
                Expanded(flex: 1, child: _buildBottomPanel(status, data)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Picks the bottom panel for the current transit [status].
  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    // Arrived at pickup — verification
    if (status == 'arrived') {
      final clinicAddress = _clinicAddressFrom(data);
      return _buildVerificationPanel(
        title: 'Arrived at pick up location',
        address: data['address'] ?? '',
        destinationAddress:
        clinicAddress.isEmpty ? 'Clinic not yet assigned' : clinicAddress,
        images: _pickupImages,
        onImageTap: (i) => _pickVerificationImage(_pickupImages, i, data),
        onConfirm: _submitPickupVerification,
        onEnd: _showCloseTransitDialog,
        confirmLabel: 'Animal Rescued',
        isActing: _isActing,
        data: data,
        showContacts: true,
      );
    }

    // Arrived at a clinic — Treatment Accepted / Treatment Rejected decision
    if (status == 'dropoff') {
      return _buildClinicDecisionPanel(data);
    }

    // A clinic just rejected treatment — auto-searching for the next one
    if (status == 'searching_clinic') {
      return _buildSearchingClinicPanel(data);
    }

    // Treatment accepted, and the reporter marked interest to adopt on the
    // original report — waiting at the clinic for that adopter instead of
    // heading to the shelter.
    if (status == 'awaiting_adopter_pickup') {
      return _buildAwaitingAdopterPanel(data);
    }

    // Treatment accepted — final leg to the shelter
    if (status == 'in_transit_shelter') {
      final shelterAddress = (data['shelterAddress'] as String?)?.isNotEmpty == true
          ? data['shelterAddress'] as String
          : (data['shelterName'] as String?) ?? 'Shelter address not available';
      return _buildVerificationPanel(
        title: 'In transit to shelter',
        address: shelterAddress,
        images: _shelterImages,
        onImageTap: (i) => _pickVerificationImage(_shelterImages, i, data),
        onConfirm: _completeShelterDropoff,
        confirmLabel: 'Complete',
        isActing: _isActing,
        data: data,
      );
    }

    // Standard panel for other statuses
    return _buildStandardPanel(status, data);
  }

  // Arrived at clinic — decide whether treatment was accepted or rejected.
  Widget _buildClinicDecisionPanel(Map<String, dynamic> data) {
    final address = _clinicAddressFrom(data);
    final placeId = data['dropoffPlaceId'] as String?;
    final atStop = _isAtVerificationStop(data);
    final canDecide = !_isActing && atStop;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arrived at drop off location',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildGeofenceBanner(data),
            _ClinicHistoryNote(
              future: _fetchClinicProfile(placeId, address.toString()),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Provide images to verify',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                const Text('*',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),

            // image grid
            Row(
              children: List.generate(
                2,
                    (i) => Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                  child: GestureDetector(
                    onTap: () => _pickVerificationImage(_clinicImages, i, data)
                        .then((_) => setState(() {})),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _clinicImages[i] != null
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.tearspwn.withOpacity(0.15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _clinicImages[i] != null
                          ? Image.file(_clinicImages[i]!, fit: BoxFit.cover)
                          : Center(
                          child: Icon(atStop ? Icons.add : Icons.lock_outline,
                              size: 28, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),

            const SizedBox(height: 20),

            _SwipeButton(
              label: 'Treatment Accepted',
              onSwiped: canDecide ? _acceptTreatment : null,
            ),
            const SizedBox(height: 10),
            _SwipeButton(
              label: 'Treatment Rejected',
              onSwiped: canDecide ? _rejectTreatment : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingClinicPanel(Map<String, dynamic> data) {
    final rejectionReason = data['lastRejectionReason'] ?? '';
    final lastAddress = _clinicAddressFrom(data);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arrived at drop off location',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(lastAddress,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Treatment has been rejected - $rejectionReason',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: _isSearchingClinic
                      ? CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textSecondary)
                      : const SizedBox.shrink(),
                ),
                if (_isSearchingClinic) const SizedBox(width: 8),
                Text(
                  _isSearchingClinic
                      ? 'Finding nearby clinics'
                      : 'Search paused — tap Retry to try again',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (!_isSearchingClinic) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _findAndRouteToNextClinic,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('Retry',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 14, color: AppColors.textPrimary)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _SwipeButton(
              label: 'Treatment Rejected',
              onSwiped: null, // locked — reflects the last decision made
            ),
          ],
        ),
      ),
    );
  }

  // Treatment accepted, interested adopter expected — waits at the clinic.
  // The "Adopter Arrived" action only appears once the reporter has
  // already tapped their own "Arrived at Treatment" button in
  // TrackCasePage (adopterArrivedAtTreatment == true); before that, this
  // just shows a waiting state so the transporter knows why they're not
  // moving toward the shelter yet.
  Widget _buildAwaitingAdopterPanel(Map<String, dynamic> data) {
    final address = _clinicAddressFrom(data);
    final adopterArrived = data['adopterArrivedAtTreatment'] == true;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Awaiting adopter pickup',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address.isEmpty ? 'Clinic' : address,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lavenderrspwn.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The reporter expressed interest in adopting this animal. '
                    'Stay at the treatment location — the animal goes home with '
                    'them directly instead of continuing to the shelter.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 20),
            if (!adopterArrived) ...[
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Waiting for the adopter to mark their arrival on their end.',
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ] else ...[
              _SwipeButton(
                label: 'Adopter Arrived',
                onSwiped: _isActing ? null : _confirmAdopterPresent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStandardPanel(String status, Map<String, dynamic> data) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ongoing Request',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 10),

            // Address card
            _AddressCard(
              pickup: data['address'] ?? '',
              dropoff: _clinicAddressFrom(data).isEmpty
                  ? 'Clinic not yet assigned'
                  : _clinicAddressFrom(data),
            ),

            const SizedBox(height: 12),

            // Reporter/witness and organization contact rows
            ..._buildContactRows(data),

            const SizedBox(height: 8),

            // Swipe button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildSwipeButton(status),
            ),

          ],
        ),
      ),

    );

  }

  // Builds the tappable Reporter/Witness and Organization contact rows.
  List<Widget> _buildContactRows(Map<String, dynamic> data) {
    final reporterName = (data['reporterName'] as String?)?.trim() ?? '';
    final witnessName = (data['witnessName'] as String?)?.trim() ?? '';
    final reporterPhone = (data['reporterPhone'] as String?)?.trim() ?? '';
    final witnessPhone = (data['witnessPhone'] as String?)?.trim() ?? '';

    final contactName = reporterName.isNotEmpty
        ? reporterName
        : (witnessName.isNotEmpty ? witnessName : 'Reporter/Witness Name');
    final contactPhone =
    reporterPhone.isNotEmpty ? reporterPhone : witnessPhone;

    final organizationName =
        (data['organizationName'] as String?)?.trim() ?? '';
    final organizationPhone =
        (data['organizationPhone'] as String?)?.trim() ?? '';

    return [
      _ContactRow(
        name: contactName,
        onCall: () => _launchCall(contactPhone),
      ),
      _ContactRow(
        name: organizationName.isNotEmpty
            ? organizationName
            : 'Loved by the Gapz',
        onCall: () => _launchCall(organizationPhone),
      ),
    ];
  }

  Widget _buildSwipeButton(String status) {
    String label;
    VoidCallback? onSwipe;

    switch (status) {
      // Arrived at pickup — verification
      case 'arrived':
        final clinicAddress = clinicAddressFrom(data);
        return VerificationPanel(
          title: 'Arrived at pick up location',
          address: data['address'] ?? '',
          destinationAddress: clinicAddress.isEmpty
              ? 'Clinic not yet assigned'
              : clinicAddress,
          images: _pickupImages,
          onImageTap: (i) => _pickImage(_pickupImages, i),
          onConfirm: _submitPickupVerification,
          onEnd: _showCloseTransitDialog,
          confirmLabel: 'Animal Rescued',
          isActing: _isActing,
          contactRows: buildTransitContactRows(data, onCall: _launchCall),
        );

      // Arrived at a clinic — Treatment Accepted / Treatment Rejected decision
      case 'dropoff':
        final address = clinicAddressFrom(data);
        return ClinicDecisionPanel(
          address: address,
          images: _clinicImages,
          isActing: _isActing,
          clinicProfileFuture: _service.fetchClinicProfile(
            data['dropoffPlaceId'] as String?,
            address.toString(),
          ),
          onImageTap: (i) =>
              _pickImage(_clinicImages, i).then((_) => setState(() {})),
          onAccept: _acceptTreatment,
          onReject: _rejectTreatment,
        );

      // A clinic just rejected treatment — auto-searching for the next one
      case 'searching_clinic':
        return SearchingClinicPanel(
          lastAddress: clinicAddressFrom(data),
          rejectionReason: data['lastRejectionReason'] ?? '',
          isSearching: _isSearchingClinic,
          onRetry: _findAndRouteToNextClinic,
        );

      // Treatment accepted, and the reporter marked interest to adopt on the
      // original report — waiting at the clinic for that adopter instead of
      // heading to the shelter.
      case 'awaiting_adopter_pickup':
        return AwaitingAdopterPanel(
          address: clinicAddressFrom(data),
          adopterArrived: data['adopterArrivedAtTreatment'] == true,
          isActing: _isActing,
          onAdopterArrived: _confirmAdopterPresent,
        );

      // Treatment accepted — final leg to the shelter
      case 'in_transit_shelter':
        final shelterAddress =
            (data['shelterAddress'] as String?)?.isNotEmpty == true
            ? data['shelterAddress'] as String
            : (data['shelterName'] as String?) ??
                  'Shelter address not available';
        return VerificationPanel(
          title: 'In transit to shelter',
          address: shelterAddress,
          images: _shelterImages,
          onImageTap: (i) => _pickImage(_shelterImages, i),
          onConfirm: _completeShelterDropoff,
          confirmLabel: 'Complete',
          isActing: _isActing,
        );

      // Standard panel for other statuses
      default:
        return StandardProgressPanel(
          status: status,
          pickupAddress: data['address'] ?? '',
          clinicAddress: clinicAddressFrom(data),
          contactRows: buildTransitContactRows(data, onCall: _launchCall),
          isBusy: _isActing || _isVerifyingArrival,
          onStartTrip: _startTrip,
          onMarkArrived: _markArrived,
          onArriveAtClinic: _arriveAtClinic,
        );
    }

    return _SwipeButton(
      label: label,
      onSwiped: (_isActing || _isVerifyingArrival) ? null : onSwipe,
    );
  }

  Widget _buildVerificationPanel({
    required String title,
    required String address,
    required List<File?> images,
    required Function(int) onImageTap,
    required VoidCallback onConfirm,
    required String confirmLabel,
    required bool isActing,
    VoidCallback? onEnd,
    Map<String, dynamic>? data,
    bool showContacts = false,
    // Where the animal is headed next (e.g. the assigned clinic) — shown
    // in the address row below the image grid. Defaults to [address]
    // itself for panels that only ever have one relevant location (the
    // final shelter drop-off), but the pickup-verification panel passes
    // the clinic address here so it isn't just a second copy of the
    // pickup address above it.
    String? destinationAddress,
  }) {
    final bottomAddress = destinationAddress ?? address;
    final atStop = data == null || _isAtVerificationStop(data);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (data != null) _buildGeofenceBanner(data),
            Row(
              children: [
                Text('Provide images and video to verify',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                const Text('*',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),

            // image grid
            Row(
              children: List.generate(
                2,
                    (i) => Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                  child: GestureDetector(
                    onTap: () => onImageTap(i),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: images[i] != null
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.tearspwn.withOpacity(0.15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: images[i] != null
                          ? Image.file(images[i]!, fit: BoxFit.cover)
                          : Center(
                          child: Icon(atStop ? Icons.add : Icons.lock_outline,
                              size: 28, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Address below images — the NEXT destination, not a repeat
            // of the pickup address above.
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(bottomAddress,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),

            // Reporter/witness and organization contact rows
            if (showContacts && data != null) ...[
              const SizedBox(height: 12),
              ..._buildContactRows(data),
            ],

            const SizedBox(height: 20),

            // Confirm button — swipeable, matching every other
            // progression action in this flow (On the way / Arrived /
            // Treatment Accepted-Rejected all use _SwipeButton; this one
            // shouldn't be the lone plain tap button).
            _SwipeButton(
              label: confirmLabel,
              onSwiped: (isActing || !atStop) ? null : onConfirm,
            ),
            const SizedBox(height: 14),

            if (onEnd != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onEnd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.slaterspwn,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('Close Case',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 14, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 14),
            ],

          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications_outlined),
          activeIcon: Icon(Icons.notifications),
          label: 'Notifications',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'My Profile',
        ),
      ],
      onTap: (index) {
        if (index == 0) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransporterNotifications()),
          );
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransporterProfile()),
          );
        }
      },
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final String caseId;
  final Timestamp? lastReadAt;
  const _UnreadBadge({required this.caseId, required this.lastReadAt});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('messages')
          .orderBy('timestamp')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final unread = snap.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final senderId = d['senderId'] as String?;
          if (senderId == uid) return false; // don't count your own messages
          final ts = d['timestamp'] as Timestamp?;
          if (ts == null) return true; // not yet committed server-side
          if (lastReadAt == null) return true;
          return ts.compareTo(lastReadAt!) > 0;
        }).length;

        if (unread == 0) return const SizedBox.shrink();

        return Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Swipe button
class _SwipeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onSwiped;

  const _SwipeButton({required this.label, this.onSwiped});

  @override
  State<_SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<_SwipeButton> {
  double _dragX = 0;
  static const double _thumbSize = 52;
  static const double _triggerFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onSwiped == null;

    return LayoutBuilder(builder: (context, constraints) {
      final trackWidth = constraints.maxWidth;
      final maxDrag = trackWidth - _thumbSize - 8;
      final fraction = (_dragX / maxDrag).clamp(0.0, 1.0);
      // Track is solid dark the whole way through (matches the mockup —
      // no light-grey base with a small dark "fill" nub), thumb is a
      // plain white circle that slides across it.
      final trackColor =
      disabled ? Colors.grey.shade400 : AppColors.textPrimary;
      final labelColor =
      disabled ? Colors.grey.shade100 : AppColors.background;
      final thumbIconColor =
      disabled ? Colors.grey.shade400 : AppColors.textPrimary;

      return GestureDetector(
        onHorizontalDragUpdate: disabled
            ? null
            : (d) => setState(
                () => _dragX = (_dragX + d.delta.dx).clamp(0, maxDrag)),
        onHorizontalDragEnd: disabled
            ? null
            : (d) {
          if (fraction >= _triggerFraction) {
            widget.onSwiped!();
          }
          setState(() => _dragX = 0);
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Label
              Center(
                child: Text(
                  widget.label,
                  style: GoogleFonts.tiltWarp(
                      fontSize: 13, color: labelColor),
                  textAlign: TextAlign.center,
                ),
              ),

              // Thumb
              Positioned(
                left: 4 + _dragX,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right,
                      color: thumbIconColor,
                      size: 25),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// Online badge
class _OnlineBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: Colors.green),
          const SizedBox(width: 6),
          Text('Online',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// Address card
class _AddressCard extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const _AddressCard({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 13, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(pickup,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      height: 14,
                      child: VerticalDivider(
                          color: AppColors.slaterspwn, thickness: 1.5),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 13, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(dropoff,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// Contact row — name/label with a tappable call button
class _ContactRow extends StatelessWidget {
  final String name;
  final VoidCallback onCall;
  const _ContactRow({required this.name, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.tiltWarp(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCall,
              child: const Icon(Icons.call,
                  size: 20, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

//Messages list
class _MessagesList extends StatelessWidget {
  final String caseId;
  const _MessagesList({required this.caseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('messages')
          .orderBy('timestamp')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox();
        }
        final docs = snap.data!.docs;
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg =
            docs[docs.length - 1 - i].data() as Map<String, dynamic>;
            final ts = msg['timestamp'] as Timestamp?;
            final timeStr = ts != null
                ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '';
            final senderName = (msg['senderName'] ?? 'U').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.slaterspwn,
                    child: Text(
                      senderName.isEmpty ? 'U' : senderName[0],
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(msg['senderName'] ?? '',
                                style: GoogleFonts.zain(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            Text(timeStr,
                                style: GoogleFonts.zain(
                                    fontSize: 10,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                        Text(msg['text'] ?? '',
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}


class _ClinicHistoryNote extends StatelessWidget {
  final Future<Map<String, dynamic>?> future;
  const _ClinicHistoryNote({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final tally = Map<String, dynamic>.from(
            profile?['declineReasonTally'] ?? {});
        if (tally.isEmpty) return const SizedBox.shrink();

        final topReasons = tally.entries.toList()
          ..sort((a, b) =>
              ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0));
        final summary = topReasons
            .take(2)
            .map((e) => '${e.key} (${e.value}x)')
            .join(', ');

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.history, size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Previously declined treatment here: $summary',
                  style: GoogleFonts.zain(
                      fontSize: 11.5, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Message input
class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _MessageInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Type a message',
                hintStyle: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: AppColors.slaterspwn),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide:
                  const BorderSide(color: AppColors.textPrimary),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.yellowrspwn,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send,
                  size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

//Tracking map
class _TrackingMap extends StatefulWidget {
  final String caseId;
  final void Function(GoogleMapController) onMapCreated;
  final LatLng? destination;
  final String destinationLabel;

  const _TrackingMap({
    required this.caseId,
    required this.onMapCreated,
    this.destination,
    this.destinationLabel = 'Destination',
  });

  @override
  State<_TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<_TrackingMap> {
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

    final destChanged = _routeFetchedFor == null ||
        _routeFetchedFor!.latitude != widget.destination!.latitude ||
        _routeFetchedFor!.longitude != widget.destination!.longitude;

    final movedFar = _routeFetchedFrom == null ||
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
            '${widget.destination} (${widget.destinationLabel})');

    fetchDirectionsRoute(riderPosition, widget.destination!).then((route) {
      if (route == null) {
        debugPrint(
            '_maybeRefreshRoute: fetchDirectionsRoute returned null — see '
                'fetchDirectionsRoute logs above for the actual reason.');
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
              CameraUpdate.newLatLngZoom(points.last, 15));
        }

        if (points.isNotEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _maybeRefreshRoute(points.last));
        }

        final markers = <Marker>{};
        if (points.isNotEmpty) {
          markers.add(Marker(
            markerId: const MarkerId('rider_current'),
            position: points.last,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            zIndex: 2,
            infoWindow: const InfoWindow(title: 'You'),
          ));
        }
        if (widget.destination != null) {
          markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: widget.destination!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: widget.destinationLabel,
              snippet: _route == null
                  ? null
                  : '${_route!.distanceText} • ${_route!.durationText}',
            ),
          ));
        }

        final polylines = <Polyline>{};
        if (points.length >= 2) {
          polylines.add(Polyline(
            polylineId: const PolylineId('route_trail'),
            points: points,
            color: AppColors.textPrimary.withOpacity(0.35),
            width: 3,
            zIndex: 0,
          ));
        }

        if (_route != null && _route!.points.length >= 2) {
          polylines.add(Polyline(
            polylineId: const PolylineId('directions_route'),
            points: _route!.points,
            color: const Color(0xFF4285F4),
            width: 6,
            zIndex: 1,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));
        }

        return Stack(
          children: [
            GoogleMap(
              onMapCreated: (ctrl) {
                _controller = ctrl;
                widget.onMapCreated(ctrl);
              },
              initialCameraPosition:
              CameraPosition(target: initialCenter, zoom: 14),
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6)
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time,
                            size: 15, color: AppColors.textPrimary),
                        const SizedBox(width: 6),
                        Text(
                          '${_route!.durationText} to ${widget.destinationLabel} • ${_route!.distanceText}',
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
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
// Shown after a transit reaches a terminal outcome — either delivered to
// the shelter (completed) or ended via the End Reason flow (cancelled,
// with the chosen reason). Replaces the old MaterialBanner-on-completion /
// silent-pop-on-cancellation behavior with one consistent result screen
// for both outcomes.
class TransitResultPage extends StatelessWidget {
  final bool completed;
  final String? reason;

  const TransitResultPage({super.key, required this.completed, this.reason});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.rescuerTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left,
                color: AppColors.textPrimary, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title:   Text(
        completed ? 'Transit Completed' : 'Transit Canceled',
            style: GoogleFonts.tiltWarp(
                fontSize: 15, color: AppColors.textSecondary),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  completed
                      ? 'Rescue Transit has been completed! Thank you for safely '
                      'transporting the rescued animal to its destination.'
                      : 'Transit Canceled',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tiltWarp(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                if (!completed) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This transit has been cancelled.'
                        '${(reason != null && reason!.isNotEmpty) ? '\nReason: $reason' : ''}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}