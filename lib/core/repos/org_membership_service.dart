import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';

/// A user's membership in a single organization.
///
/// [status] mirrors the Firestore doc's own `status` field. Older
/// membership docs predate this field entirely — [isActive] treats a
/// missing/unrecognized status as
/// active rather than blocking legacy accounts that were never written
/// with one, and only treats a recognized inactive value ('inactive',
/// 'removed', 'disabled') as actually revoking organization access
/// (Temporary Organization Admin/Member Access Model spec — a removed
/// membership must remove ORG access only, never the underlying account).
class OrgMembership {
  final String organizationId;
  final OrgRole role;
  final String? status;
  const OrgMembership({required this.organizationId, required this.role, this.status});

  static const _inactiveStatuses = {'inactive', 'removed', 'disabled'};
  bool get isActive => status == null || !_inactiveStatuses.contains(status);
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
/// Enforcement lives in firestore.rules, and this class mirrors it:
///   - Members docs: only the owner or an active admin manages them; an
///     invited person creates only their own (rules `members/{uid}`).
///   - `users/{uid}.organizationId` can only point at an organization the
///     account owns or holds an active membership in, or be set by that
///     organization's admin — so it can't be forged.
///   - Organization-owned cases, animals and adoptions are writable by that
///     organization's staff (owner, active member, or a legacy account
///     linked through `organizationId` with no members doc yet).
/// An org-linked account with no members doc therefore still works as
/// staff (fail open, matching the rules), but gets none of the owner/admin-
/// only capabilities ([_resolveCapabilities] passes
/// `confirmedMembership: false`), which the rules and facebook.js also deny.
/// Remaining gap: Admin-only case actions (merge, refer) are enforced in the
/// app only; the rules treat every staff member of the organization alike.
class OrgMembershipService {
  OrgMembershipService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Just "which organization is this account linked to" — reads
  /// `users/{uid}.organizationId` directly, with NO dependency on the
  /// `organizations/{orgId}/members/{uid}` subdoc [getMembership] requires.
  /// Legacy org-linked accounts may have no member subdoc, so
  /// [getMembership] returns null for them — which was silently routing
  /// "open my Organization Profile" into the blank bootstrap/invitation
  /// flow instead of the account's real org. Use this for "which org
  /// profile should open" (viewing); keep using [getMembership] for
  /// role-gated actions (editing/staff management).
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
      status: memberDoc.data()?['status'] as String?,
    );
  }

  /// One-shot equivalent of [streamCapabilities], for the several existing
  /// call sites that resolve access once in `initState`/a load method
  /// rather than watching a Riverpod provider (staff_members_page.dart,
  /// organization_profile_edit_page.dart, audit_page.dart) — same
  /// owner-fallback / active-membership / fail-open-on-missing-subdoc
  /// resolution as the stream version, just without staying subscribed.
  Future<OrganizationCapabilities> resolveCapabilities(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final orgId = userDoc.data()?['organizationId'] as String?;
    if (orgId == null || orgId.isEmpty) return OrganizationCapabilities.none;

    final orgDoc = await _db.collection('organizations').doc(orgId).get();
    final memberDoc =
        await _db.collection('organizations').doc(orgId).collection('members').doc(uid).get();
    return _resolveCapabilities(uid: uid, orgDoc: orgDoc, memberDoc: memberDoc);
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
                  status: memberDoc.data()?['status'] as String?,
                )
              : null);
    });
  }

  /// Temporary Organization Admin/Member Access Model spec — the single
  /// centralized resolver every screen should use instead of comparing
  /// `membership.role` directly. Order: active membership first, then the
  /// organization's own `ownerId` as a fallback so a legacy owner (no
  /// membership subdoc, or a membership doc that predates this model) is
  /// never blocked. An org-linked account with NO membership subdoc at all
  /// (a legacy link — see the class doc comment) still resolves to staff
  /// access, minus the owner/admin-only capabilities, matching
  /// firestore.rules.
  Stream<OrganizationCapabilities> streamCapabilities(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncExpand((userDoc) {
      final orgId = userDoc.data()?['organizationId'] as String?;
      if (orgId == null || orgId.isEmpty) return Stream.value(OrganizationCapabilities.none);
      return _combineOrgAndMember(orgId: orgId, uid: uid);
    });
  }

  OrganizationCapabilities _resolveCapabilities({
    required String uid,
    required DocumentSnapshot<Map<String, dynamic>> orgDoc,
    required DocumentSnapshot<Map<String, dynamic>> memberDoc,
  }) {
    final isOwner = orgDoc.exists && orgDoc.data()?['ownerId'] == uid;
    if (isOwner) return OrganizationCapabilities.forRole(ResolvedOrgRole.owner);

    if (!memberDoc.exists) {
      // No membership subdoc yet for a (legacy) org-linked account — staff
      // access, as firestore.rules' isStaffOf allows. Owner/admin-only
      // actions stay off: facebook.js and the rules' isOrgAdmin both fail
      // closed on a missing membership doc.
      return OrganizationCapabilities.forRole(ResolvedOrgRole.admin, confirmedMembership: false);
    }

    final membership = OrgMembership(
      organizationId: orgDoc.id,
      role: OrgRole.fromName(memberDoc.data()?['role'] as String?),
      status: memberDoc.data()?['status'] as String?,
    );
    if (!membership.isActive) return OrganizationCapabilities.none;
    return OrganizationCapabilities.forRole(
      resolvedRoleFromOrgRole(membership.role),
      facebookPublisher: memberDoc.data()?['facebookPublisher'] == true,
    );
  }

  /// Firestore has no built-in "combine latest" across two document
  /// streams, and this project doesn't depend on rxdart — this hand-rolls
  /// the minimal broadcast-merge needed so capability resolution reacts to
  /// EITHER the organization doc (ownerId) or the membership doc
  /// (role/status) changing live, not just whichever one happened to
  /// change first.
  Stream<OrganizationCapabilities> _combineOrgAndMember({required String orgId, required String uid}) {
    late final StreamController<OrganizationCapabilities> controller;
    DocumentSnapshot<Map<String, dynamic>>? latestOrg;
    DocumentSnapshot<Map<String, dynamic>>? latestMember;
    StreamSubscription? orgSub;
    StreamSubscription? memberSub;

    void emit() {
      final org = latestOrg;
      final member = latestMember;
      if (org == null || member == null) return;
      controller.add(_resolveCapabilities(uid: uid, orgDoc: org, memberDoc: member));
    }

    controller = StreamController<OrganizationCapabilities>.broadcast(
      onListen: () {
        orgSub = _db.collection('organizations').doc(orgId).snapshots().listen((d) {
          latestOrg = d;
          emit();
        }, onError: controller.addError);
        memberSub = _db
            .collection('organizations')
            .doc(orgId)
            .collection('members')
            .doc(uid)
            .snapshots()
            .listen((d) {
          latestMember = d;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () {
        orgSub?.cancel();
        memberSub?.cancel();
      },
    );
    return controller.stream;
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
