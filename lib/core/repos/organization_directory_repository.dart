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
}
