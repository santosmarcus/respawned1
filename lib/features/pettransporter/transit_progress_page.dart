import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:respawnd1/app_theme.dart';


const String _placesApiKey = 'AIzaSyAzqeI6uyCZW5VHQTeOyWqLdku6n-rzjTQ';

const String _directionsApiKey = _placesApiKey;

const double _arrivalThresholdMeters = 150;

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
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') return null;
    final routes = body['routes'] as List<dynamic>;
    if (routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final legs = route['legs'] as List<dynamic>;
    if (legs.isEmpty) return null;
    final leg = legs.first as Map<String, dynamic>;
    final overview = route['overview_polyline']?['points'] as String?;
    if (overview == null) return null;

    return DirectionsRoute(
      points: decodePolyline(overview),
      distanceMeters: (leg['distance']?['value'] as num?)?.toDouble() ?? 0,
      distanceText: (leg['distance']?['text'] as String?) ?? '',
      durationText: (leg['duration']?['text'] as String?) ?? '',
    );
  } catch (_) {
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
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  bool _isActing = false;
  bool _isSearchingClinic = false;
  bool _autoSearchAttempted = false;
  bool _isVerifyingArrival = false;

  // Verification images
  final List<File?> _pickupImages = [null, null];
  final List<File?> _clinicImages = [null, null]; // arrived-at-clinic verification
  final List<File?> _shelterImages = [null, null]; // final shelter drop-off verification

  @override
  void dispose() {
    _messageController.dispose();
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
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
    });
  }

  // Status transitions
  Future<void> _setStatus(String status, String statusLabel) async {
    setState(() => _isActing = true);
    try {
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': status,
        'statusHistory': FieldValue.arrayUnion([
          {'status': statusLabel, 'timestamp': Timestamp.now()}
        ]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _startTrip() async {
    await _setStatus('ongoing', 'On the way to pick up location.');
    _beginLocationStreaming();
  }

  // Reads a lat/lng pair off the case document, if present.
  LatLng? _latLngFrom(Map<String, dynamic> data, String latKey, String lngKey) {
    final lat = data[latKey];
    final lng = data[lngKey];
    if (lat is num && lng is num) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }


  // Clinic profile logging
  static const Set<String> _clinicRelevantReasons = {
    'Clinic at full capacity',
    'Insufficient Medication/Treatment Supplies',
    'No Veterinarian/Specialist Available',
  };

  String _clinicProfileId({String? placeId, required String address}) {
    if (placeId != null && placeId.isNotEmpty) return placeId;
    final slug = address
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'unknown_clinic' : slug;
  }

  Future<void> _logClinicDecision({
    required String? placeId,
    required String name,
    required String address,
    double? lat,
    double? lng,
    required bool accepted,
    String reason = '',
  }) async {
    try {
      final id = _clinicProfileId(placeId: placeId, address: address);
      final ref =
      FirebaseFirestore.instance.collection('clinic_profiles').doc(id);

      final clinicReasons = accepted
          ? const <String>[]
          : reason
          .split(',')
          .map((r) => r.trim())
          .where((r) => _clinicRelevantReasons.contains(r))
          .toList();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final tally =
        Map<String, dynamic>.from(data['declineReasonTally'] ?? {});
        for (final r in clinicReasons) {
          tally[r] = ((tally[r] as num?)?.toInt() ?? 0) + 1;
        }

        tx.set(
          ref,
          {
            'name': name,
            'address': address,
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            'declineReasonTally': tally,
            'totalDeclines':
            ((data['totalDeclines'] as num?)?.toInt() ?? 0) +
                (accepted ? 0 : 1),
            'totalAccepted':
            ((data['totalAccepted'] as num?)?.toInt() ?? 0) +
                (accepted ? 1 : 0),
            'declineLog': FieldValue.arrayUnion([
              if (!accepted)
                {
                  'reason': reason,
                  'caseId': widget.caseId,
                  'timestamp': Timestamp.now(),
                }
            ]),
            'lastUpdated': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {
    }
  }

  Future<Map<String, dynamic>?> _fetchClinicProfile(
      String? placeId, String address) async {
    try {
      final id = _clinicProfileId(placeId: placeId, address: address);
      final snap = await FirebaseFirestore.instance
          .collection('clinic_profiles')
          .doc(id)
          .get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifyArrivalViaDirections(
      LatLng? destination, String destinationLabel) async {
    if (destination == null) return true;

    setState(() => _isVerifyingArrival = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final origin = LatLng(pos.latitude, pos.longitude);
      final route = await fetchDirectionsRoute(origin, destination);

      if (route == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Could not verify your route to $destinationLabel. Check your connection and try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      }

      if (route.distanceMeters > _arrivalThresholdMeters) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "You're still ${route.distanceText} from $destinationLabel according to Google Maps — keep heading there before confirming arrival."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not check your location: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isVerifyingArrival = false);
    }
  }

  Future<void> _markArrived() async {
    final doc = await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final destination = _latLngFrom(data, 'lat', 'lng');

    final arrived =
    await _verifyArrivalViaDirections(destination, 'the pick up location');
    if (!arrived) return;

    await _setStatus('arrived', 'Arrived at pick up location.');
  }

  Future<void> _arriveAtClinic() async {
    final doc = await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final destination = _latLngFrom(data, 'dropoffLat', 'dropoffLng');

    final arrived =
    await _verifyArrivalViaDirections(destination, 'the clinic');
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
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(
          _pickupImages, 'pickup');
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'treatment',
        'pickupVerificationUrls': urls,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal rescued. On the way to treatment.',
            'timestamp': Timestamp.now()
          }
        ]),
      });
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

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
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(_clinicImages, 'clinic');
      final data = (await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .get())
          .data() as Map<String, dynamic>? ??
          {};
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'in_transit_shelter',
        'clinicVerificationUrls': urls,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Treatment accepted. On the way to shelter.',
            'timestamp': Timestamp.now()
          }
        ]),
      });

      unawaited(_logClinicDecision(
        placeId: data['dropoffPlaceId'] as String?,
        name: (data['dropoffName'] ?? data['dropoffAddress'] ?? 'Clinic')
            .toString(),
        address:
        (data['dropoffAddress'] ?? data['address'] ?? '').toString(),
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
    final reason = await _showTreatmentRejectDialog();
    if (reason == null) return; // dismissed via X / back

    setState(() => _isActing = true);
    try {
      final data = (await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .get())
          .data() as Map<String, dynamic>? ??
          {};
      final currentAddress = data['dropoffAddress'] ?? data['address'] ?? '';
      final currentPlaceId = data['dropoffPlaceId'] as String?;

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'searching_clinic',
        'lastRejectionReason': reason,
        'rejectedClinics': FieldValue.arrayUnion([
          {
            'address': currentAddress,
            'reason': reason,
            'timestamp': Timestamp.now(),
          }
        ]),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Treatment has been rejected - $reason',
            'timestamp': Timestamp.now()
          }
        ]),
      });

      // Log the decline against the clinic itself
      // so future rescues routed near this clinic can see, ahead of time,
      // what kinds of treatment it has and hasn't been able to accommodate.
      unawaited(_logClinicDecision(
        placeId: currentPlaceId,
        name: (data['dropoffName'] ?? currentAddress).toString(),
        address: currentAddress.toString(),
        lat: (data['dropoffLat'] as num?)?.toDouble(),
        lng: (data['dropoffLng'] as num?)?.toDouble(),
        accepted: false,
        reason: reason,
      ));

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
      final docRef =
      FirebaseFirestore.instance.collection('cases').doc(widget.caseId);
      final doc = await docRef.get();
      final data = doc.data() as Map<String, dynamic>? ?? {};

      final rejected = (data['rejectedClinics'] as List<dynamic>? ?? [])
          .map((e) => (e as Map)['address']?.toString() ?? '')
          .toSet();

      final originLat = data['riderLastLat'] ?? data['dropoffLat'];
      final originLng = data['riderLastLng'] ?? data['dropoffLng'];
      if (originLat == null || originLng == null) {
        throw Exception('Missing current location for clinic search.');
      }

      Map<String, dynamic>? candidate;
      bool sawSuccessfulResponse = false;

      final flaggedByProfile = <String>{};

      // Widen the search radius progressively if nearby clinics have rejected
      for (final radius in [5000, 10000, 20000, 40000]) {
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/nearbysearch/json',
          {
            'location': '$originLat,$originLng',
            'radius': '$radius',
            'type': 'veterinary_care',
            'key': _placesApiKey,
          },
        );
        final res = await http.get(uri);
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final apiStatus = body['status'] as String?;

        if (apiStatus != 'OK' && apiStatus != 'ZERO_RESULTS') continue;
        sawSuccessfulResponse = true;

        final results = (body['results'] as List<dynamic>? ?? []);
        for (final r in results) {
          final map = r as Map<String, dynamic>;
          final addr = (map['vicinity'] ?? map['name'] ?? '').toString();
          final placeId = map['place_id'] as String?;
          if (addr.isEmpty || rejected.contains(addr)) continue;
          if (flaggedByProfile.contains(placeId ?? addr)) continue;

          final profile = await _fetchClinicProfile(placeId, addr);
          final tally = Map<String, dynamic>.from(
              profile?['declineReasonTally'] ?? {});
          final capabilityDeclines = tally.entries
              .where((e) => e.key != 'Clinic at full capacity')
              .fold<int>(0, (sum, e) => sum + ((e.value as num?)?.toInt() ?? 0));
          if (capabilityDeclines >= 2) {
            flaggedByProfile.add(placeId ?? addr);
            continue;
          }

          candidate = map;
          break;
        }
        if (candidate != null) break;
      }

      if (candidate == null) {
        if (!sawSuccessfulResponse) {
          throw Exception(
              'Could not reach clinic search. Please try again.');
        }

        await docRef.update({
          'status': 'in_transit_shelter',
          'statusHistory': FieldValue.arrayUnion([
            {
              'status':
              'No more nearby clinics available. Proceeding directly to shelter.',
              'timestamp': Timestamp.now()
            }
          ]),
        });
        return;
      }

      final loc = candidate['geometry']?['location'] as Map<String, dynamic>?;
      final newAddress =
      (candidate['vicinity'] ?? candidate['name'] ?? 'Nearby Clinic')
          .toString();
      final newPlaceId = candidate['place_id'] as String?;
      final newName = (candidate['name'] ?? newAddress).toString();

      await docRef.update({
        'status': 'dropoff',
        'dropoffAddress': newAddress,
        'dropoffPlaceId': newPlaceId,
        'dropoffName': newName,
        if (loc != null) 'dropoffLat': loc['lat'],
        if (loc != null) 'dropoffLng': loc['lng'],
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Finding nearby clinics… routed to $newAddress',
            'timestamp': Timestamp.now()
          }
        ]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Clinic search failed: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingClinic = false);
    }
  }

  // TESTING ONLY — remove later.
  Future<void> _testSkipToNextStep() async {
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'in_transit_shelter',
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': '[TEST] Skipped clinic search — proceeding to shelter.',
          'timestamp': Timestamp.now()
        }
      ]),
    });
  }

  Future<void> _completeShelterDropoff() async {
    if (_shelterImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final destination = _latLngFrom(data, 'shelterLat', 'shelterLng');
    final arrived =
    await _verifyArrivalViaDirections(destination, 'the shelter');
    if (!arrived) return;

    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(_shelterImages, 'shelter');
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'completed',
        'shelterVerificationUrls': urls,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal delivered to shelter. Rescue completed.',
            'timestamp': Timestamp.now()
          }
        ]),
      });
      _positionSub?.cancel();
      if (mounted) await _showTransitCompletedBanner();
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _showTransitCompletedBanner() async {
    ScaffoldMessenger.of(context).clearMaterialBanners();
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: AppColors.greenrspwn,
        contentTextStyle:
        GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
        leading: const Icon(Icons.check_circle,
            color: AppColors.textPrimary),
        content: Text(
          'Transit has been completed. Routing you to the home screen…',
          style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              if (mounted) Navigator.pop(context);
            },
            child: Text('OK',
                style: GoogleFonts.zain(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      Navigator.pop(context);
    }
  }

  Future<List<String>> _uploadVerificationImages(
      List<File?> images, String type) async {
    final urls = <String>[];
    for (int i = 0; i < images.length; i++) {
      final f = images[i];
      if (f == null) continue;
      final ref = FirebaseStorage.instance
          .ref('cases/${widget.caseId}/${type}_verify_$i.jpg');
      await ref.putFile(f);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _pickImage(List<File?> slot, int index) async {
    final picked =
    await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => slot[index] = File(picked.path));
    }
  }

  Future<void> _showEndReasonDialog() async {
    final reasons = [
      'Animal/Reporter not Found',
      'Invalid / fake report',
      'Animal Deceased',
      'Other',
    ];
    final selected = <String>{};
    String? other;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: AppColors.background,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text('End Reason',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 18, color: AppColors.textPrimary)),
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close,
                            size: 20, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...reasons.map((r) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(r),
                  activeColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  title: Text(r,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary)),
                  onChanged: (v) => setDlg(() {
                    if (v == true) {
                      selected.add(r);
                    } else {
                      selected.remove(r);
                    }
                  }),
                )),
                if (selected.contains('Other')) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => other = v,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Describe reason…',
                      hintStyle: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.slaterspwn),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                      Navigator.pop(ctx);
                      final reasonStr = [
                        ...selected.where((r) => r != 'Other'),
                        if (selected.contains('Other') &&
                            other != null &&
                            other!.isNotEmpty)
                          other!,
                      ].join(', ');
                      await _setStatus(
                          'ended', 'Rescue ended: $reasonStr');
                      _positionSub?.cancel();
                      if (mounted) Navigator.pop(context);
                    },
                    child: Text('Confirm',
                        style: GoogleFonts.zain(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: selected.isEmpty
                                ? AppColors.textSecondary
                                : Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showTreatmentRejectDialog() async {
    final reasons = [
      'Clinic at full capacity',
      'Insufficient Medication/Treatment Supplies',
      'Animal Deceased',
      'No Veterinarian/Specialist Available',
      'Other',
    ];
    final selected = <String>{};
    String? other;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: AppColors.background,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text('Treatment Rejected',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 18, color: AppColors.textPrimary)),
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close,
                            size: 20, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...reasons.map((r) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(r),
                  activeColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  title: Text(r,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary)),
                  onChanged: (v) => setDlg(() {
                    if (v == true) {
                      selected.add(r);
                    } else {
                      selected.remove(r);
                    }
                  }),
                )),
                if (selected.contains('Other')) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => other = v,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Describe reason…',
                      hintStyle: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.slaterspwn),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                      final reasonStr = [
                        ...selected.where((r) => r != 'Other'),
                        if (selected.contains('Other') &&
                            other != null &&
                            other!.isNotEmpty)
                          other!,
                      ].join(', ');
                      Navigator.pop(ctx, reasonStr);
                    },
                    child: Text('Confirm',
                        style: GoogleFonts.zain(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: selected.isEmpty
                                ? AppColors.textSecondary
                                : Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMessageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
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

              Expanded(
                child: _MessagesList(
                  caseId: widget.caseId,
                ),
              ),

              SafeArea(
                child: _MessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final name =
    '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
        .trim();
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('messages')
        .add({
      'senderId': uid,
      'senderName': name.isEmpty ? 'Rider' : name,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
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
              body: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(
              body: Center(child: Text('Case no longer exists.')));
        }

        final status = data['status'] ?? 'accepted';

        if ((status == 'ongoing' ||
            status == 'arrived' ||
            status == 'treatment' ||
            status == 'dropoff' ||
            status == 'searching_clinic' ||
            status == 'in_transit_shelter') &&
            _positionSub == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _beginLocationStreaming());
        }

        if (status == 'searching_clinic') {
          if (!_isSearchingClinic && !_autoSearchAttempted) {
            _autoSearchAttempted = true;
            WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _findAndRouteToNextClinic());
          }
        } else {
          _autoSearchAttempted = false;
        }

        LatLng? currentDestination;
        String currentDestinationLabel = '';
        if (status == 'ongoing' || status == 'arrived') {
          currentDestination = _latLngFrom(data, 'lat', 'lng');
          currentDestinationLabel = 'Pick up location';
        } else if (status == 'treatment' || status == 'dropoff') {
          currentDestination = _latLngFrom(data, 'dropoffLat', 'dropoffLng');
          currentDestinationLabel = 'Clinic';
        } else if (status == 'in_transit_shelter') {
          currentDestination = _latLngFrom(data, 'shelterLat', 'shelterLng');
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
                      _TrackingMap(
                        caseId: widget.caseId,
                        onMapCreated: (ctrl) => _mapController = ctrl,
                        destination: currentDestination,
                        destinationLabel: currentDestinationLabel,
                      ),

                      // Online badge
                      Positioned(
                        top: 48,
                        left: 16,
                        child: _OnlineBadge(),
                      ),
                      // Settings / filter icon top right
                      Positioned(
                        top: 48,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 4)
                            ],
                          ),
                          child: const Icon(Icons.tune,
                              size: 18, color: AppColors.textPrimary),
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

                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text(
                                    '2',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom panel
                Expanded(
                  flex: 1,
                  child: _buildBottomPanel(status, data),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    // Arrived at pickup — verification
    if (status == 'arrived') {
      return _buildVerificationPanel(
        title: 'Arrived at pick up location',
        address: data['address'] ?? '',
        images: _pickupImages,
        onImageTap: (i) => _pickImage(_pickupImages, i),
        onConfirm: _submitPickupVerification,
        onEnd: _showEndReasonDialog,
        confirmLabel: 'Animal Rescued',
        isActing: _isActing,
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

    // Treatment accepted — final leg to the shelter
    if (status == 'in_transit_shelter') {
      return _buildVerificationPanel(
        title: 'In transit to shelter',
        address: data['shelterAddress'] ?? 'Shelter Address',
        images: _shelterImages,
        onImageTap: (i) => _pickImage(_shelterImages, i),
        onConfirm: _completeShelterDropoff,
        confirmLabel: 'Complete',
        isActing: _isActing,
      );
    }

    // Standard panel for other statuses
    return _buildStandardPanel(status, data);
  }

  // Arrived at clinic — decide whether treatment was accepted or rejected.
  Widget _buildClinicDecisionPanel(Map<String, dynamic> data) {
    final address = data['dropoffAddress'] ?? data['address'] ?? '';
    final placeId = data['dropoffPlaceId'] as String?;
    final canDecide = !_isActing;

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
            _ClinicHistoryNote(
              future: _fetchClinicProfile(placeId, address.toString()),
            ),
            const SizedBox(height: 6),
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
                    onTap: () => _pickImage(_clinicImages, i)
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
                          : const Center(
                          child: Icon(Icons.add,
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
    final lastAddress = data['dropoffAddress'] ?? data['address'] ?? '';

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
              Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 10),
                  // Testing-only remove later
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testSkipToNextStep,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text('Skip (Testing)',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 12, color: Colors.orange)),
                    ),
                  ),
                ],
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

  Widget _buildStandardPanel(String status, Map<String, dynamic> data) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
            dropoff: data['dropoffAddress'] ?? data['address'] ?? '',
          ),

          const SizedBox(height: 20),

          // Swipe button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _buildSwipeButton(status),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeButton(String status) {
    String label;
    VoidCallback? onSwipe;

    switch (status) {
      case 'accepted':
        label = 'On the way to pick up location';
        onSwipe = _startTrip;
        break;
      case 'ongoing':
        label = 'Arrived at pick up location';
        onSwipe = _markArrived;
        break;
      case 'treatment':
        label = 'On the way to Treatment';
        onSwipe = _arriveAtClinic;
        break;
      default:
        label = 'Processing…';
        onSwipe = null;
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
  }) {
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
                          : const Center(
                          child: Icon(Icons.add,
                              size: 28, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Address below images
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

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isActing ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: isActing
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background),
                )
                    : Text(confirmLabel,
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, color: AppColors.background)),
              ),
            ),

            // End button (only at pickup)
            if (onEnd != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onEnd,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('End',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 14, color: AppColors.textPrimary)),
                ),
              ),
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
            label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile'),
      ],
      onTap: (_) {},
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
      final trackColor = Color.lerp(
        Colors.grey.shade400,
        AppColors.textPrimary,
        fraction,
      )!;
      final fillColor =
      disabled ? Colors.grey.shade400 : AppColors.textPrimary;
      final thumbColor =
      disabled ? Colors.grey.shade600 : AppColors.textPrimary;
      final labelColor =
      disabled ? Colors.grey.shade100 : AppColors.background;

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
            color: disabled ? Colors.grey.shade300 : AppColors.slaterspwn,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track fill
              AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: _thumbSize + _dragX + 4,
                height: 56,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),

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
                  decoration: BoxDecoration(
                    color: thumbColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right,
                      color: disabled
                          ? Colors.grey.shade300
                          : AppColors.yellowrspwn,
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
    if (widget.destination == null) return;

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

    fetchDirectionsRoute(riderPosition, widget.destination!).then((route) {
      if (mounted && route != null) {
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
            color: AppColors.textPrimary,
            width: 4,
          ));
        }
        if (_route != null && _route!.points.length >= 2) {
          polylines.add(Polyline(
            polylineId: const PolylineId('directions_route'),
            points: _route!.points,
            color: Colors.blueAccent,
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ));
        }

        return GoogleMap(
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
        );
      },
    );
  }
}