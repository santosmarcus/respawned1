import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/org_role.dart';

/// A user's membership in a single organization.
class OrgMembership {
  final String organizationId;
  final OrgRole role;
  const OrgMembership({required this.organizationId, required this.role});
}

/// Reads/writes the new, additive org-membership model:
/// `organizations/{orgId}/members/{uid}.role` plus `users/{uid}.organizationId`.
/// This sits alongside — and does not replace — the existing flat
/// `users/{uid}.role` account type (admin/ngo_staff/general/...); that field
/// still gates which top-level app shell a user lands in (see
/// lib/main.dart AuthWrapper). This service answers the narrower question
/// "within their organization, are they an Admin or Staff member?", which
/// is what backs the Admin-only vs Staff-allowed actions in this module.
///
/// TODO(org-roles) — TESTING PHASE, READ BEFORE PRODUCTION:
/// No `organizations/{orgId}/members/{uid}` documents exist for any real
/// user yet, and no Firestore rule enforces this model — every rescue-module
/// write today is only gated by the existing flat auth/role check (signed in
/// + `users/{uid}.role` in {admin, ngo_staff}), same as before this model was
/// introduced. `getMembership`/`streamMembership` simply return null until
/// membership docs are backfilled; callers (see rescue_detail_page.dart's
/// `canManageOrgActions`) are written to fail OPEN on null rather than block
/// testing. Before shipping Admin-vs-Staff enforcement for real: backfill
/// membership docs, flip frontend checks to fail closed, and add rules like:
///   match /organizations/{orgId}/members/{uid} {
///     allow read: if request.auth != null;
///     allow write: if <caller is an existing admin member of orgId>;
///   }
/// and gate `cases` writes that should be Admin-only (merge, refer) on
/// `orgRole(orgId) == 'admin'` in the deployed rules, not just this class.
class OrgMembershipService {
  OrgMembershipService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<OrgMembership?> getMembership(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final orgId = userDoc.data()?['organizationId'] as String?;
    if (orgId == null || orgId.isEmpty) return null;

    final memberDoc =
        await _db.collection('organizations').doc(orgId).collection('members').doc(uid).get();
    if (!memberDoc.exists) return null;

    return OrgMembership(
      organizationId: orgId,
      role: OrgRole.fromName(memberDoc.data()?['role'] as String?),
    );
  }

  Stream<OrgMembership?> streamMembership(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncExpand((userDoc) {
      final orgId = userDoc.data()?['organizationId'] as String?;
      if (orgId == null || orgId.isEmpty) return Stream.value(null);
      return _db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(uid)
          .snapshots()
          .map((memberDoc) => memberDoc.exists
              ? OrgMembership(
                  organizationId: orgId,
                  role: OrgRole.fromName(memberDoc.data()?['role'] as String?),
                )
              : null);
    });
  }

  Future<void> setMember({
    required String organizationId,
    required String uid,
    required OrgRole role,
  }) async {
    await _db
        .collection('organizations')
        .doc(organizationId)
        .collection('members')
        .doc(uid)
        .set({'role': role.name, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await _db.collection('users').doc(uid).update({'organizationId': organizationId});
  }
}
