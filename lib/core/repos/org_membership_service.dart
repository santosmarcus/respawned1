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

  /// Just "which organization is this account linked to" — reads
  /// `users/{uid}.organizationId` directly, with NO dependency on the
  /// `organizations/{orgId}/members/{uid}` subdoc [getMembership] requires.
  /// Per this class's own TODO above, no member subdoc exists for real
  /// users yet, so [getMembership] returns null for every legitimate,
  /// already-configured organization today — which was silently routing
  /// "open my Organization Profile" into the blank bootstrap/invitation
  /// flow instead of the account's real org. Use this for "which org
  /// profile should open" (viewing); keep using [getMembership] for
  /// role-gated actions (editing/staff management), which SHOULD fail open
  /// on missing membership per the TODO above, not silently succeed.
  Future<String?> resolveOrganizationId(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final orgId = userDoc.data()?['organizationId'] as String?;
    return (orgId == null || orgId.isEmpty) ? null : orgId;
  }

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

  /// [email]/[displayName]/[status]/[invitationId] are optional purely for
  /// backward compatibility with existing callers that only ever changed
  /// `role` — when supplied they're merged in alongside it so a role change
  /// can also backfill a legacy membership doc's missing display fields
  /// without a second write.
  Future<void> setMember({
    required String organizationId,
    required String uid,
    required OrgRole role,
    String? email,
    String? displayName,
    String? status,
    String? invitationId,
  }) async {
    await _db
        .collection('organizations')
        .doc(organizationId)
        .collection('members')
        .doc(uid)
        .set({
      'role': role.name,
      'updatedAt': FieldValue.serverTimestamp(),
      if (email != null && email.isNotEmpty) ...{
        'email': email,
        'normalizedEmail': email.trim().toLowerCase(),
      },
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      if (status != null && status.isNotEmpty) 'status': status,
      if (invitationId != null && invitationId.isNotEmpty) 'invitationId': invitationId,
    }, SetOptions(merge: true));
    await _db.collection('users').doc(uid).update({'organizationId': organizationId});
  }
}
