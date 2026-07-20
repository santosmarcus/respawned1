import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<List<OrgReferralCandidate>> search({
    String? nameQuery,
    String? species,
    int limit = 30,
  }) async {
    final snap = await _organizations.limit(200).get();
    var results = snap.docs.map(OrgReferralCandidate.fromFirestore).toList();

    if (nameQuery != null && nameQuery.trim().isNotEmpty) {
      final q = nameQuery.trim().toLowerCase();
      results = results.where((o) => o.name.toLowerCase().contains(q)).toList();
    }
    if (species != null && species.trim().isNotEmpty) {
      results = results
          .where((o) =>
              o.acceptedSpecies.isEmpty ||
              o.acceptedSpecies.any((s) => s.toLowerCase() == species.toLowerCase()))
          .toList();
    }

    return results.take(limit).toList();
  }

  /// Resolves the Intake flow's destination, in priority order: an
  /// org-specific saved shelter/intake location
  /// (`organizations/{orgId}.shelterLocation` + optional
  /// `shelterLat`/`shelterLng` — not set by any UI yet, but read
  /// defensively in case it's ever populated directly) -> the org's
  /// existing `location` field (name only, no coordinates) -> null
  /// (caller falls back to a temporary hardcoded default). Returns null
  /// outright if [organizationId] is null/empty, which is the common case
  /// today since org-membership backfill hasn't happened yet (see
  /// org_membership_service.dart's TODO) — so in practice this almost
  /// always resolves to the caller's own fallback right now, which is
  /// expected and handled, not an error state.
  Future<({String name, double? lat, double? lng})?> resolveShelterLocation(String? organizationId) async {
    if (organizationId == null || organizationId.isEmpty) return null;
    final doc = await _organizations.doc(organizationId).get();
    final data = doc.data();
    if (data == null) return null;
    final shelterLocation = data['shelterLocation'] as String?;
    if (shelterLocation != null && shelterLocation.trim().isNotEmpty) {
      return (
        name: shelterLocation.trim(),
        lat: (data['shelterLat'] as num?)?.toDouble(),
        lng: (data['shelterLng'] as num?)?.toDouble(),
      );
    }
    final location = data['location'] as String?;
    if (location != null && location.trim().isNotEmpty) {
      return (name: location.trim(), lat: null, lng: null);
    }
    return null;
  }
}
