import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:geolocator/geolocator.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/repos/organization_repository.dart' show ServiceArea;
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';

/// Search support for the "Refer to Another Organization" modal. Reads the
/// same top-level `organizations` collection used by
/// lib/features/organization/organization_list_page.dart.
///
/// Firestore doesn't support case-insensitive substring search natively;
/// name search here pulls a bounded window and filters client-side, which
/// is fine at the scale of an org directory (dozens to low hundreds of
/// docs), not thousands.
class OrganizationDirectoryRepository {
  OrganizationDirectoryRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _organizations => _db.collection('organizations');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  /// [species] — every species the source case actually covers (a case can
  /// have more than one animal via its `animals[]` array). An organization
  /// matches if it accepts any one of them, or accepts everything — never
  /// filtered down to just the first animal's species.
  ///
  /// Shelters and rescue groups only: independent rescuers are offered
  /// through [independentsNear] (Refer → Rescue Volunteer).
  Future<List<OrgReferralCandidate>> search({
    String? nameQuery,
    List<String>? species,
    int limit = 30,
  }) async {
    final snap = await _organizations.limit(200).get();
    var results = snap.docs
        .where((d) => d.data()['kind'] != 'independent')
        .map(OrgReferralCandidate.fromFirestore)
        .toList();

    if (nameQuery != null && nameQuery.trim().isNotEmpty) {
      final q = nameQuery.trim().toLowerCase();
      results = results.where((o) => o.name.toLowerCase().contains(q)).toList();
    }
    final speciesFilter = (species ?? const []).where((s) => s.trim().isNotEmpty).toList();
    if (speciesFilter.isNotEmpty) {
      results = results
          .where((o) =>
              o.acceptedSpecies.isEmpty ||
              o.acceptedSpecies.any((accepted) =>
                  speciesFilter.any((s) => accepted.toLowerCase() == s.toLowerCase())))
          .toList();
    }

    return results.take(limit).toList();
  }

  /// Approved independent rescuers whose coverage circle contains
  /// ([lat], [lng]), nearest first, with how much room each has. Those at
  /// capacity or paused are listed last and can't be picked
  /// ([IndependentCandidate.refusal]).
  Future<List<IndependentCandidate>> independentsNear({required double lat, required double lng}) async {
    final snap = await _organizations
        .where('kind', isEqualTo: 'independent')
        .where('verificationStatus', isEqualTo: 'approved')
        .get();
    final out = <IndependentCandidate>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      double? best;
      for (final raw in (d['serviceAreas'] as List? ?? const []).whereType<Map>()) {
        final a = ServiceArea.fromMap(Map<String, dynamic>.from(raw));
        if (!a.hasGeofence) continue;
        final r = a.radiusKm!.clamp(IndependentRescuer.minRadiusKm, IndependentRescuer.maxRadiusKm);
        final km = Geolocator.distanceBetween(lat, lng, a.lat!, a.lng!) / 1000;
        if (km <= r && (best == null || km < best)) best = km;
      }
      if (best == null) continue;
      out.add(IndependentCandidate.fromOrg(doc.id, d, distanceKm: best));
    }
    out.sort((a, b) {
      if ((a.refusal == null) != (b.refusal == null)) return a.refusal == null ? -1 : 1;
      return a.distanceKm.compareTo(b.distanceKm);
    });
    return out;
  }

  /// Resolves the Intake flow's destination, in priority order: an
  /// org-specific saved shelter location (`organizations/{orgId}.shelterName`
  /// + `shelterAddress`/`shelterPlaceId`/`shelterLat`/`shelterLng`, written
  /// by [saveShelterLocation] via the shelter-location picker) -> the org's
  /// existing `location` field (name only, never has coordinates) -> null
  /// (caller falls back to a temporary, clearly-marked dev default).
  /// Returns null outright if [organizationId] is null/empty, which is the
  /// common case today since org-membership backfill hasn't happened yet
  /// (see org_membership_service.dart's TODO).
  Future<({String name, String? address, String? placeId, double? lat, double? lng})?> resolveShelterLocation(
      String? organizationId) async {
    if (organizationId == null || organizationId.isEmpty) return null;
    final doc = await _organizations.doc(organizationId).get();
    final data = doc.data();
    if (data == null) return null;

    final shelterName = data['shelterName'] as String?;
    if (shelterName != null && shelterName.trim().isNotEmpty) {
      return (
        name: shelterName.trim(),
        address: data['shelterAddress'] as String?,
        placeId: data['shelterPlaceId'] as String?,
        lat: (data['shelterLat'] as num?)?.toDouble(),
        lng: (data['shelterLng'] as num?)?.toDouble(),
      );
    }
    // Legacy fallback: a name-only org address with no coordinates. Still
    // surfaced (so the destination card shows *something* instead of
    // nothing), but never treated as "usable" for Confirm Intake, which
    // requires real lat/lng for tracking.
    final location = data['location'] as String?;
    if (location != null && location.trim().isNotEmpty) {
      return (name: location.trim(), address: null, placeId: null, lat: null, lng: null);
    }
    return null;
  }

  /// Saves the organization's shelter/intake location — the reusable
  /// source of truth Intake Details reads from. Each confirmed intake case
  /// separately snapshots this onto the case itself
  /// (RescueCaseRepository.confirmIntake), so changing the shelter here
  /// later never retroactively alters an already-active intake's route.
  Future<void> saveShelterLocation({
    required String organizationId,
    required String name,
    String? address,
    String? placeId,
    required double lat,
    required double lng,
  }) async {
    await _organizations.doc(organizationId).set({
      'shelterName': name,
      'shelterAddress': address,
      'shelterPlaceId': placeId,
      'shelterLat': lat,
      'shelterLng': lng,
      'shelterUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // TODO: Remove the user-scoped shelter fallback once organization
  // membership is required for every admin/NGO account. Until then, this
  // lets an account with no organizationId (or no membership doc at all)
  // still exercise the Intake flow end-to-end for testing, by saving a
  // temporary shelter location directly on their own user doc instead of an
  // organization's.

  /// Reads the temporary `temporaryShelter*` fields saved by
  /// [saveUserShelterLocation] onto `users/{uid}` — the fallback destination
  /// source used only when [resolveShelterLocation] found nothing (no
  /// organization linked, or the linked organization has no shelter saved
  /// yet). Returns null if the user hasn't saved one either.
  Future<({String name, String? address, String? placeId, double? lat, double? lng})?>
      resolveUserShelterLocation(String? uid) async {
    if (uid == null || uid.isEmpty) return null;
    final doc = await _users.doc(uid).get();
    final data = doc.data();
    if (data == null) return null;

    final name = data['temporaryShelterName'] as String?;
    if (name == null || name.trim().isEmpty) return null;
    return (
      name: name.trim(),
      address: data['temporaryShelterAddress'] as String?,
      placeId: data['temporaryShelterPlaceId'] as String?,
      lat: (data['temporaryShelterLat'] as num?)?.toDouble(),
      lng: (data['temporaryShelterLng'] as num?)?.toDouble(),
    );
  }

  /// Saves a per-user temporary shelter/intake location — same shape and
  /// merge-write pattern as [saveShelterLocation], just scoped to
  /// `users/{uid}` instead of `organizations/{orgId}` for accounts with no
  /// organization membership yet.
  Future<void> saveUserShelterLocation({
    required String uid,
    required String name,
    String? address,
    String? placeId,
    required double lat,
    required double lng,
  }) async {
    await _users.doc(uid).set({
      'temporaryShelterName': name,
      'temporaryShelterAddress': address,
      'temporaryShelterPlaceId': placeId,
      'temporaryShelterLat': lat,
      'temporaryShelterLng': lng,
      'temporaryShelterUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// An independent rescuer offered for a referral.
class IndependentCandidate {
  const IndependentCandidate({
    required this.id,
    required this.name,
    required this.area,
    required this.distanceKm,
    required this.activeCases,
    required this.maxActiveCases,
    required this.animalsInCare,
    required this.maxAnimalsInCare,
    required this.accepting,
    this.avatarUrl,
  });

  factory IndependentCandidate.fromOrg(String id, Map<String, dynamic> d, {required double distanceKm}) {
    int n(String k, int fallback) => (d[k] as num?)?.toInt() ?? fallback;
    return IndependentCandidate(
      id: id,
      name: (d['name'] as String?)?.trim() ?? '',
      area: (d['location'] as String?)?.trim() ?? '',
      avatarUrl: d['avatarUrl'] as String?,
      distanceKm: distanceKm,
      activeCases: n('activeCaseCount', 0),
      maxActiveCases: n('maxActiveCases', IndependentRescuer.maxActiveCases),
      animalsInCare: n('animalsInCareCount', 0),
      maxAnimalsInCare: n('maxAnimalsInCare', IndependentRescuer.maxAnimalsInCare),
      accepting: d['acceptingCases'] != false,
    );
  }

  final String id;
  final String name;
  final String area;
  final String? avatarUrl;
  final double distanceKm;
  final int activeCases;
  final int maxActiveCases;
  final int animalsInCare;
  final int maxAnimalsInCare;
  final bool accepting;

  /// Why they can't take a referral now, or null.
  String? get refusal {
    if (!accepting) return 'Paused';
    if (activeCases >= maxActiveCases) return 'At case limit ($activeCases/$maxActiveCases)';
    if (animalsInCare >= maxAnimalsInCare) return 'Full ($animalsInCare/$maxAnimalsInCare animals)';
    return null;
  }

  String get room => '${maxActiveCases - activeCases} case slot(s) · '
      '${maxAnimalsInCare - animalsInCare} animal space(s)';
}
