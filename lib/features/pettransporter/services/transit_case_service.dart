// Firestore / Storage / Places writes for one transit, split out of
// transit_progress_page.dart (behavior-preserving refactor). The page keeps
// the UI concerns (validation snackbars, busy flags, navigation); this class
// only reads and writes data, using the exact same fields as before.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import 'package:respawnd1/core/constants/maps_config.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';

/// Result of [TransitCaseService.findAndRouteToNextClinic].
enum ClinicSearchOutcome {
  /// A new clinic was found and the case moved back to `dropoff`.
  routedToClinic,

  /// No suitable clinic left; the case moved to `in_transit_shelter`.
  proceedingToShelter,
}

class TransitCaseService {
  TransitCaseService(
    this.caseId, {
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore,
       _storage = storage,
       _auth = auth;

  final String caseId;
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  // Resolved lazily (same as the original direct `.instance` calls) so
  // constructing the service never touches Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _st => _storage ?? FirebaseStorage.instance;
  FirebaseAuth get _au => _auth ?? FirebaseAuth.instance;

  String get _placesApiKey => MapsConfig.placesApiKey;

  DocumentReference<Map<String, dynamic>> get caseRef =>
      _db.collection('cases').doc(caseId);

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCase() =>
      caseRef.snapshots();

  Future<Map<String, dynamic>> fetchCase() async =>
      (await caseRef.get()).data() ?? {};

  // Location streaming — fire-and-forget, exactly like the original
  // listener (neither write was awaited).
  void recordPosition(double lat, double lng) {
    unawaited(
      caseRef.collection('tracking').add({
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
      }),
    );
    unawaited(caseRef.update({'riderLastLat': lat, 'riderLastLng': lng}));
  }

  Map<String, dynamic> _historyEntry(String label) => {
    'statusHistory': FieldValue.arrayUnion([
      {'status': label, 'timestamp': Timestamp.now()},
    ]),
  };

  Future<void> setStatus(String status, String statusLabel) {
    return caseRef.update({'status': status, ..._historyEntry(statusLabel)});
  }

  Future<List<String>> uploadVerificationImages(
    List<File?> images,
    String type,
  ) async {
    final urls = <String>[];
    for (int i = 0; i < images.length; i++) {
      final f = images[i];
      if (f == null) continue;
      final ref = _st.ref('cases/$caseId/${type}_verify_$i.jpg');
      await ref.putFile(f);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> submitPickupVerification(List<String> urls) {
    return caseRef.update({
      'status': 'treatment',
      'pickupVerificationUrls': urls,
      ..._historyEntry('Animal rescued. On the way to treatment.'),
    });
  }

  Future<void> acceptTreatment(List<String> clinicUrls) async {
    final data = await fetchCase();

    // The case never had its own shelter destination — resolve the
    // assigned organization's registered shelter location (same source
    // the Intake flow uses) and snapshot it onto the case now, so the
    // in-transit-to-shelter panel/map/arrival-check all have a real
    // destination instead of falling back to placeholder text with no
    // coordinates at all.
    final shelter = await OrganizationDirectoryRepository()
        .resolveShelterLocation(data['organizationId'] as String?);

    final next = statusAfterTreatmentAccepted(data);

    await caseRef.update({
      'status': next.status,
      'clinicVerificationUrls': clinicUrls,
      'shelterName': shelter?.name ?? kFallbackShelterName,
      'shelterAddress': shelter?.address ?? kFallbackShelterAddress,
      'shelterLat': shelter?.lat ?? kFallbackShelterLat,
      'shelterLng': shelter?.lng ?? kFallbackShelterLng,
      ..._historyEntry(next.label),
    });

    unawaited(
      logClinicDecision(
        placeId: data['dropoffPlaceId'] as String?,
        name:
            (data['dropoffName'] ??
                    data['dropoffAddress'] ??
                    data['vetClinicAddress'] ??
                    'Clinic')
                .toString(),
        address: clinicAddressFrom(data),
        lat: (data['dropoffLat'] as num?)?.toDouble(),
        lng: (data['dropoffLng'] as num?)?.toDouble(),
        accepted: true,
      ),
    );
  }

  Future<void> rejectTreatment(String reason) async {
    final data = await fetchCase();
    final currentAddress = clinicAddressFrom(data);
    final currentPlaceId = data['dropoffPlaceId'] as String?;

    await caseRef.update({
      'status': 'searching_clinic',
      'lastRejectionReason': reason,
      'rejectedClinics': FieldValue.arrayUnion([
        {
          'address': currentAddress,
          'reason': reason,
          'timestamp': Timestamp.now(),
        },
      ]),
      ..._historyEntry('Treatment has been rejected - $reason'),
    });

    // Log the decline against the clinic itself so future rescues routed
    // near this clinic can see, ahead of time, what kinds of treatment it
    // has and hasn't been able to accommodate.
    unawaited(
      logClinicDecision(
        placeId: currentPlaceId,
        name: (data['dropoffName'] ?? currentAddress).toString(),
        address: currentAddress.toString(),
        lat: (data['dropoffLat'] as num?)?.toDouble(),
        lng: (data['dropoffLng'] as num?)?.toDouble(),
        accepted: false,
        reason: reason,
      ),
    );
  }

  /// Searches Places for the nearest veterinary clinic that hasn't already
  /// rejected this case (and isn't flagged by its profile), widening the
  /// radius each round. Throws when the case has no origin or the search
  /// service can't be reached at all.
  Future<ClinicSearchOutcome> findAndRouteToNextClinic() async {
    final data = await fetchCase();

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
    for (final radius in kClinicSearchRadiiMeters) {
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

        final profile = await fetchClinicProfile(placeId, addr);
        final tally = Map<String, dynamic>.from(
          profile?['declineReasonTally'] ?? {},
        );
        if (capabilityDeclineCount(tally) >= kClinicCapabilityDeclineLimit) {
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

      await caseRef.update({
        'status': 'in_transit_shelter',
        ..._historyEntry(
          'No more nearby clinics available. Proceeding directly to shelter.',
        ),
      });
      return ClinicSearchOutcome.proceedingToShelter;
    }

    final loc = candidate['geometry']?['location'] as Map<String, dynamic>?;
    final newAddress =
        (candidate['vicinity'] ?? candidate['name'] ?? 'Nearby Clinic')
            .toString();
    final newPlaceId = candidate['place_id'] as String?;
    final newName = (candidate['name'] ?? newAddress).toString();

    await caseRef.update({
      'status': 'dropoff',
      'dropoffAddress': newAddress,
      'dropoffPlaceId': newPlaceId,
      'dropoffName': newName,
      if (loc != null) 'dropoffLat': loc['lat'],
      if (loc != null) 'dropoffLng': loc['lng'],
      ..._historyEntry('Finding nearby clinics… routed to $newAddress'),
    });
    return ClinicSearchOutcome.routedToClinic;
  }

  Future<void> completeShelterDropoff(List<String> shelterUrls) {
    return caseRef.update({
      'status': 'completed',
      'shelterVerificationUrls': shelterUrls,
      ..._historyEntry('Animal delivered to shelter. Rescue completed.'),
    });
  }

  Future<void> confirmAdopterPickup() {
    return caseRef.update({
      'status': 'completed',
      'adopterPickupConfirmedAt': Timestamp.now(),
      ..._historyEntry(
        'Animal handed off directly to the interested adopter at the treatment location. Rescue completed.',
      ),
    });
  }

  Future<void> applyEndReason(EndReasonOutcome outcome) {
    final serviceType = outcome.serviceType;
    final extra = <String, dynamic>{
      'endReason': outcome.reasonText,
      if (outcome.notes.isNotEmpty) 'endReasonNotes': outcome.notes,
      // The specific service type the animal needs — this is what
      // assign_rider_page.dart reads to show the org what to arrange
      // and to weight vehicle-compatibility ranking for the next
      // transporter offered the case.
      'endReasonServiceType': ?serviceType,
      // Consumed by expireStaleReporterResponses; cleared automatically
      // once the reporter replies (see TrackCasePage's reporter-response
      // handling) or the case is manually resolved by staff.
      if (outcome.awaitingReporter)
        'awaitingReporterSince': FieldValue.serverTimestamp(),
      // So a future reliability-score feature can exclude this pickup
      // from counting against the transporter — verified here as an
      // animal-safety/capability escalation, not a no-show or missed job.
      if (outcome.excludeFromTransporterFault)
        'transporterFaultVerified': false,
    };

    return caseRef.update({
      'status': outcome.status,
      ..._historyEntry(outcome.statusLabel),
      ...extra,
    });
  }

  Future<void> sendMessage(String text) async {
    final uid = _au.currentUser!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    final name =
        '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
            .trim();
    await caseRef.collection('messages').add({
      'senderId': uid,
      'senderName': name.isEmpty ? 'Rider' : name,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Clinic profile logging — never throws.
  Future<void> logClinicDecision({
    required String? placeId,
    required String name,
    required String address,
    double? lat,
    double? lng,
    required bool accepted,
    String reason = '',
  }) async {
    try {
      final id = clinicProfileId(placeId: placeId, address: address);
      final ref = _db.collection('clinic_profiles').doc(id);

      final clinicReasons = clinicDeclineReasons(
        accepted: accepted,
        reason: reason,
      );

      await _db.runTransaction((tx) async {
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
                'caseId': caseId,
                'timestamp': Timestamp.now(),
              },
          ]),
          'lastUpdated': Timestamp.now(),
        }, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> fetchClinicProfile(
    String? placeId,
    String address,
  ) async {
    try {
      final id = clinicProfileId(placeId: placeId, address: address);
      final snap = await _db.collection('clinic_profiles').doc(id).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }
}
