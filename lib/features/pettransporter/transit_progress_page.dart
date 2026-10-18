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
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';
import 'package:respawnd1/core/constants/maps_config.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
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

const double _arrivalThresholdMeters = 150;

// Temporary default shelter — used whenever
// OrganizationDirectoryRepository.resolveShelterLocation comes back null,
// which per that method's own doc comment is still the common case today
// (org-membership backfill hasn't happened for most test accounts). Without
// this, a case with no org-registered shelter would show "Shelter address
// not available" and have no coordinates to route/verify arrival against.
// Remove once every organization has a real shelter location configured.
const String _fallbackShelterName = 'LGARI Shelter - Tanza';
const String _fallbackShelterAddress =
    'LGARI Shelter, Tanza, Cavite, Philippines';
const double _fallbackShelterLat = 14.3860;
const double _fallbackShelterLng = 120.8283;

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
  Timestamp? _lastReadAt;

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

  // Location streaming
  void _beginLocationStreaming() {
    if (_positionSub != null) return;
    _positionSub =
        Geolocator.getPositionStream(
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
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          );
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
              {'status': statusLabel, 'timestamp': Timestamp.now()},
            ]),
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
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
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  // Places a phone call to the given number, if available.
  Future<void> _launchCall(String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number available.')),
        );
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
    }
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

  LatLng? _clinicLatLngFrom(Map<String, dynamic> data) {
    return _latLngFrom(data, 'dropoffLat', 'dropoffLng') ??
        _latLngFrom(data, 'vetClinicLat', 'vetClinicLng');
  }

  String _clinicAddressFrom(Map<String, dynamic> data) {
    final dropoff = (data['dropoffAddress'] as String?)?.trim();
    if (dropoff != null && dropoff.isNotEmpty) return dropoff;
    final vet = (data['vetClinicAddress'] as String?)?.trim();
    if (vet != null && vet.isNotEmpty) return vet;
    return '';
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
      final ref = FirebaseFirestore.instance
          .collection('clinic_profiles')
          .doc(id);

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
        final tally = Map<String, dynamic>.from(
          data['declineReasonTally'] ?? {},
        );
        for (final r in clinicReasons) {
          tally[r] = ((tally[r] as num?)?.toInt() ?? 0) + 1;
        }

        tx.set(ref, {
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
              },
          ]),
          'lastUpdated': Timestamp.now(),
        }, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _fetchClinicProfile(
    String? placeId,
    String address,
  ) async {
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
    LatLng? destination,
    String destinationLabel,
  ) async {
    if (destination == null) return true;

    setState(() => _isVerifyingArrival = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
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

        if (straightLineMeters <= _arrivalThresholdMeters) {
          return true;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Couldn't verify your route to $destinationLabel via Google Maps, and you're still "
                '~${straightLineMeters.round()}m away by straight-line distance — keep heading there before confirming arrival.',
              ),
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
                "You're still ${route.distanceText} from $destinationLabel according to Google Maps — keep heading there before confirming arrival.",
              ),
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
            backgroundColor: Colors.redAccent,
          ),
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
    final data = doc.data() ?? {};
    final destination = _latLngFrom(data, 'lat', 'lng');

    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the pick up location',
    );
    if (!arrived) return;

    await _setStatus('arrived', 'Arrived at pick up location.');
  }

  Future<void> _arriveAtClinic() async {
    final doc = await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .get();
    final data = doc.data() ?? {};
    final destination = _clinicLatLngFrom(data);

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
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(_pickupImages, 'pickup');
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
            'status': 'treatment',
            'pickupVerificationUrls': urls,
            'statusHistory': FieldValue.arrayUnion([
              {
                'status': 'Animal rescued. On the way to treatment.',
                'timestamp': Timestamp.now(),
              },
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
      final data =
          (await FirebaseFirestore.instance
                  .collection('cases')
                  .doc(widget.caseId)
                  .get())
              .data() ??
          {};

      // The case never had its own shelter destination — resolve the
      // assigned organization's registered shelter location (same source
      // the Intake flow uses) and snapshot it onto the case now, so the
      // in-transit-to-shelter panel/map/arrival-check all have a real
      // destination instead of falling back to placeholder text with no
      // coordinates at all.
      final shelter = await OrganizationDirectoryRepository()
          .resolveShelterLocation(data['organizationId'] as String?);

      // The reporter answered "yes" to "interested to adopt" on the
      // original report form (see rescue_page.dart's `interestedToAdopt`)
      // — that reporter is the intended adopter, so instead of continuing
      // on to the shelter, the transporter's job pauses here at the
      // clinic/treatment location until that adopter shows up in person
      // (see AwaitingAdopterPanel / TrackCasePage's own "Arrived at
      // Treatment" button, which is what unlocks the "Adopter Arrived"
      // action below).
      final hasInterestedAdopter = data['interestedToAdopt'] == 'yes';
      final nextStatus = hasInterestedAdopter
          ? 'awaiting_adopter_pickup'
          : 'in_transit_shelter';
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
            'shelterLat': shelter?.lat ?? _fallbackShelterLat,
            'shelterLng': shelter?.lng ?? _fallbackShelterLng,
            'statusHistory': FieldValue.arrayUnion([
              {'status': nextStatusLabel, 'timestamp': Timestamp.now()},
            ]),
          });

      unawaited(
        _logClinicDecision(
          placeId: data['dropoffPlaceId'] as String?,
          name:
              (data['dropoffName'] ??
                      data['dropoffAddress'] ??
                      data['vetClinicAddress'] ??
                      'Clinic')
                  .toString(),
          address: _clinicAddressFrom(data),
          lat: (data['dropoffLat'] as num?)?.toDouble(),
          lng: (data['dropoffLng'] as num?)?.toDouble(),
          accepted: true,
        ),
      );
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
    final reason = await showTreatmentRejectDialog(context);
    if (reason == null) return; // dismissed via X / back

    setState(() => _isActing = true);
    try {
      final data =
          (await FirebaseFirestore.instance
                  .collection('cases')
                  .doc(widget.caseId)
                  .get())
              .data() ??
          {};
      final currentAddress = _clinicAddressFrom(data);
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
              },
            ]),
            'statusHistory': FieldValue.arrayUnion([
              {
                'status': 'Treatment has been rejected - $reason',
                'timestamp': Timestamp.now(),
              },
            ]),
          });

      // Log the decline against the clinic itself
      // so future rescues routed near this clinic can see, ahead of time,
      // what kinds of treatment it has and hasn't been able to accommodate.
      unawaited(
        _logClinicDecision(
          placeId: currentPlaceId,
          name: (data['dropoffName'] ?? currentAddress).toString(),
          address: currentAddress.toString(),
          lat: (data['dropoffLat'] as num?)?.toDouble(),
          lng: (data['dropoffLng'] as num?)?.toDouble(),
          accepted: false,
          reason: reason,
        ),
      );

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
      final docRef = FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId);
      final doc = await docRef.get();
      final data = doc.data() ?? {};

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
            profile?['declineReasonTally'] ?? {},
          );
          final capabilityDeclines = tally.entries
              .where((e) => e.key != 'Clinic at full capacity')
              .fold<int>(
                0,
                (sum, e) => sum + ((e.value as num?)?.toInt() ?? 0),
              );
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
          throw Exception('Could not reach clinic search. Please try again.');
        }

        await docRef.update({
          'status': 'in_transit_shelter',
          'statusHistory': FieldValue.arrayUnion([
            {
              'status':
                  'No more nearby clinics available. Proceeding directly to shelter.',
              'timestamp': Timestamp.now(),
            },
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
            'timestamp': Timestamp.now(),
          },
        ]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clinic search failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingClinic = false);
    }
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
    final data = doc.data() ?? {};
    final destination = _latLngFrom(data, 'shelterLat', 'shelterLng');
    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the shelter',
    );
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
                'timestamp': Timestamp.now(),
              },
            ]),
          });
      _positionSub?.cancel();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const TransitResultPage(completed: true),
          ),
        );
      }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Adopter Pickup',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Is the interested adopter actually here, in person, ready to take the animal?',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Not yet',
              style: GoogleFonts.zain(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.greenrspwn,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Yes, confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return; // "Not yet" — stay exactly as is.

    setState(() => _isActing = true);
    try {
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
            'status': 'completed',
            'adopterPickupConfirmedAt': Timestamp.now(),
            'statusHistory': FieldValue.arrayUnion([
              {
                'status':
                    'Animal handed off directly to the interested adopter at the treatment location. Rescue completed.',
                'timestamp': Timestamp.now(),
              },
            ]),
          });
      _positionSub?.cancel();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const TransitResultPage(completed: true),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<List<String>> _uploadVerificationImages(
    List<File?> images,
    String type,
  ) async {
    final urls = <String>[];
    for (int i = 0; i < images.length; i++) {
      final f = images[i];
      if (f == null) continue;
      final ref = FirebaseStorage.instance.ref(
        'cases/${widget.caseId}/${type}_verify_$i.jpg',
      );
      await ref.putFile(f);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
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

  static const _reasonNotFound = 'Animal/Reporter not Found';
  static const _reasonReporterUnreachable = 'Reporter Unreachable';
  static const _reasonAggressive = 'Animal is too aggressive to handle safely';
  static const _reasonDeceased = 'Animal Deceased';
  static const _reasonSpecializedTransport =
      'Animal requires specialized transport that I cannot provide';
  static const _reasonBreakdown = 'Vehicle breakdown';
  static const _reasonOther = 'Other';

  // Options offered when _reasonSpecializedTransport is picked — shown to
  // the admin (and factored into vehicle-compatibility ranking) so
  // whoever's re-assigned next knows exactly what to bring, instead of
  // finding out on-site the same way this transporter just did.
  static const _serviceTypeOptions = [
    'Larger enclosed vehicle (van/truck)',
    'Secure crate/cage required',
    'Two-person handling required',
    'Climate-controlled transport',
    'Other',
  ];

  Future<void> _showCloseTransitDialog() async {
    final reasons = [
      _reasonNotFound,
      _reasonReporterUnreachable,
      _reasonAggressive,
      _reasonDeceased,
      _reasonSpecializedTransport,
      _reasonBreakdown,
      _reasonOther,
    ];
    String? selectedReason;
    String? other;
    String? serviceType;
    bool searchedTenMinutes = false;
    final notesCtrl = TextEditingController();
    final serviceTypeOtherCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final needsSearchConfirm = selectedReason == _reasonNotFound;
          final needsOtherText = selectedReason == _reasonOther;
          final needsServiceType =
              selectedReason == _reasonSpecializedTransport;
          final needsNotes =
              selectedReason == _reasonNotFound ||
              selectedReason == _reasonReporterUnreachable ||
              selectedReason == _reasonAggressive;
          final canConfirm =
              !submitting &&
              selectedReason != null &&
              (!needsSearchConfirm || searchedTenMinutes) &&
              (!needsServiceType ||
                  (serviceType != null &&
                      (serviceType != 'Other' ||
                          serviceTypeOtherCtrl.text.trim().isNotEmpty)));

          return Dialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          'End Reason',
                          style: GoogleFonts.tiltWarp(
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(
                            Icons.close,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...reasons.map(
                    (r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      groupValue: selectedReason,
                      activeColor: AppColors.textPrimary,
                      title: Text(
                        r,
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onChanged: (v) => setDlg(() => selectedReason = v),
                    ),
                  ),
                  if (needsOtherText) ...[
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => other = v,
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Describe reason…',
                        hintStyle: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.slaterspwn,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (needsSearchConfirm) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.yellowrspwn.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: searchedTenMinutes,
                        activeColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.textPrimary),
                        title: Text(
                          'I waited and searched the immediate area for at '
                          'least 10 minutes and could not locate the animal.',
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onChanged: (v) =>
                            setDlg(() => searchedTenMinutes = v ?? false),
                      ),
                    ),
                  ],
                  if (needsNotes) ...[
                    const SizedBox(height: 14),
                    Text(
                      selectedReason == _reasonAggressive
                          ? 'Describe the animal\'s behavior'
                          : 'Notes (what did you observe?)',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: selectedReason == _reasonAggressive
                            ? 'e.g. "Lunging and growling, could not be safely restrained."'
                            : 'e.g. "Neighbors said the dog left 30 minutes ago."',
                        hintStyle: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.slaterspwn,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (needsServiceType) ...[
                    const SizedBox(height: 14),
                    Text(
                      'What kind of service does this animal need?',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is shown to the org so they can arrange the right transporter or vehicle.',
                      style: GoogleFonts.zain(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._serviceTypeOptions.map(
                      (option) => RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: option,
                        groupValue: serviceType,
                        activeColor: AppColors.textPrimary,
                        title: Text(
                          option,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onChanged: (v) => setDlg(() => serviceType = v),
                      ),
                    ),
                    if (serviceType == 'Other') ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: serviceTypeOtherCtrl,
                        onChanged: (_) => setDlg(() {}),
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Describe the service needed…',
                          hintStyle: GoogleFonts.zain(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.slaterspwn,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: !canConfirm
                          ? null
                          : () async {
                              setDlg(() => submitting = true);
                              final reasonSnapshot = selectedReason!;
                              final otherSnapshot = other;
                              final notesSnapshot = notesCtrl.text.trim();
                              final serviceTypeSnapshot = needsServiceType
                                  ? (serviceType == 'Other'
                                        ? serviceTypeOtherCtrl.text.trim()
                                        : serviceType)
                                  : null;
                              Navigator.pop(ctx);
                              await _resolveEndReason(
                                selectedReason: reasonSnapshot,
                                otherText: otherSnapshot,
                                notes: notesSnapshot,
                                serviceType: serviceTypeSnapshot,
                              );
                            },
                      child: submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Confirm',
                              style: GoogleFonts.zain(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: canConfirm
                                    ? Colors.redAccent
                                    : AppColors.textSecondary,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Decides the resulting case status from the selected End Reason and
  // writes it, along with any supporting notes, to the case doc.
  //
  // - Not Found / Reporter Unreachable: the case is NOT closed as failed —
  //   it moves to a reporter-facing "awaiting response" status so the
  //   reporter can supply a new location or confirm they're reachable.
  //   expireStaleReporterResponses (functions/index.js) auto-closes it if
  //   they never respond.
  // - Aggressive / Specialized Transport: both escalate to
  //   needsSpecializedAssistance instead of ending the case as a failure —
  //   "the original rescue report remains active" and the transporter is
  //   explicitly not penalized for either outcome. Specialized Transport
  //   additionally carries the reported service type forward so it's
  //   visible wherever the case shows up as a service request afterward
  //   (assign_rider_page.dart, rescue_detail_page.dart) instead of a new
  //   transporter having to rediscover the same requirement on-site.
  // - Deceased / Vehicle breakdown / Other: remain a straightforward
  //   transit-ended outcome, same as before.
  Future<void> _resolveEndReason({
    required String selectedReason,
    required String? otherText,
    required String notes,
    String? serviceType,
  }) async {
    setState(() => _isActing = true);
    try {
      final reasonStr = selectedReason == _reasonOther
          ? (otherText != null && otherText.isNotEmpty
                ? otherText
                : _reasonOther)
          : selectedReason;

      String status;
      String statusLabel;
      switch (selectedReason) {
        case _reasonAggressive:
          // Escalate — not a failure, not counted against the transporter.
          status = RescueStatus.needsSpecializedAssistance.firestoreValue;
          statusLabel =
              'Pickup postponed — animal could not be safely handled. '
              'Escalated for specialized assistance.';
          break;
        case _reasonSpecializedTransport:
          // Escalate — same as Aggressive, this is a capability mismatch
          // with THIS transporter/vehicle, not a failed rescue.
          status = RescueStatus.needsSpecializedAssistance.firestoreValue;
          statusLabel = serviceType != null && serviceType.isNotEmpty
              ? 'Pickup postponed — requires specialized transport ($serviceType). '
                    'Escalated for reassignment.'
              : 'Pickup postponed — requires specialized transport. '
                    'Escalated for reassignment.';
          break;
        case _reasonNotFound:
          status = RescueStatus.unableToLocate.firestoreValue;
          statusLabel =
              'Animal not found at reported location. Awaiting reporter response.';
          break;
        case _reasonReporterUnreachable:
          status = RescueStatus.pickupUnsuccessful.firestoreValue;
          statusLabel = 'Pickup attempt unsuccessful — reporter unreachable.';
          break;
        default:
          status = 'ended';
          statusLabel = 'Transit closed: $reasonStr';
      }

      final notFound = selectedReason == _reasonNotFound;
      final unreachable = selectedReason == _reasonReporterUnreachable;
      final aggressive = selectedReason == _reasonAggressive;
      final specializedTransport =
          selectedReason == _reasonSpecializedTransport;

      final extra = <String, dynamic>{
        'endReason': reasonStr,
        if (notes.isNotEmpty) 'endReasonNotes': notes,
        // The specific service type the animal needs — this is what
        // assign_rider_page.dart reads to show the org what to arrange
        // and to weight vehicle-compatibility ranking for the next
        // transporter offered the case.
        if (specializedTransport &&
            serviceType != null &&
            serviceType.isNotEmpty)
          'endReasonServiceType': serviceType,
        // Consumed by expireStaleReporterResponses; cleared automatically
        // once the reporter replies (see TrackCasePage's reporter-response
        // handling) or the case is manually resolved by staff.
        if (notFound || unreachable)
          'awaitingReporterSince': FieldValue.serverTimestamp(),
        // So a future reliability-score feature can exclude this pickup
        // from counting against the transporter — verified here as an
        // animal-safety/capability escalation, not a no-show or missed job.
        if (aggressive || specializedTransport)
          'transporterFaultVerified': false,
      };

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
            'status': status,
            'statusHistory': FieldValue.arrayUnion([
              {'status': statusLabel, 'timestamp': Timestamp.now()},
            ]),
            ...extra,
          });

      _positionSub?.cancel();
      if (mounted) {
        if (status == 'ended') {
          // A genuine terminal cancellation (Deceased, Vehicle breakdown,
          // Specialized transport needed, Other) — show the same result
          // screen used for a successful completion, just with the
          // cancelled variant + reason.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TransitResultPage(completed: false, reason: reasonStr),
            ),
          );
        } else {
          // Not Found / Reporter Unreachable / Aggressive don't end the
          // case — it's still active (awaiting the reporter, or
          // escalated) — so just return the transporter to where they
          // came from instead of showing a "Cancelled" screen.
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
          currentDestination = _latLngFrom(data, 'lat', 'lng');
          currentDestinationLabel = 'Pick up location';
        } else if (status == 'treatment' || status == 'dropoff') {
          currentDestination = _clinicLatLngFrom(data);
          currentDestinationLabel = 'Clinic';
        } else if (status == 'awaiting_adopter_pickup') {
          // Waiting at the clinic for the interested adopter — same
          // location as 'dropoff', just a later phase of the same stop.
          currentDestination = _clinicLatLngFrom(data);
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
    switch (status) {
      // Arrived at pickup — verification
      case 'arrived':
        final clinicAddress = _clinicAddressFrom(data);
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
        final address = _clinicAddressFrom(data);
        return ClinicDecisionPanel(
          address: address,
          images: _clinicImages,
          isActing: _isActing,
          clinicProfileFuture: _fetchClinicProfile(
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
          lastAddress: _clinicAddressFrom(data),
          rejectionReason: data['lastRejectionReason'] ?? '',
          isSearching: _isSearchingClinic,
          onRetry: _findAndRouteToNextClinic,
        );

      // Treatment accepted, and the reporter marked interest to adopt on the
      // original report — waiting at the clinic for that adopter instead of
      // heading to the shelter.
      case 'awaiting_adopter_pickup':
        return AwaitingAdopterPanel(
          address: _clinicAddressFrom(data),
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
          clinicAddress: _clinicAddressFrom(data),
          contactRows: buildTransitContactRows(data, onCall: _launchCall),
          isBusy: _isActing || _isVerifyingArrival,
          onStartTrip: _startTrip,
          onMarkArrived: _markArrived,
          onArriveAtClinic: _arriveAtClinic,
        );
    }
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
