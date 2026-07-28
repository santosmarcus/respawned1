import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';

enum InvitationStatus {
  pending,
  accepted,
  rejected,
  expired,
  revoked;

  static InvitationStatus fromName(String? value) =>
      InvitationStatus.values.firstWhere((v) => v.name == value, orElse: () => InvitationStatus.pending);
}

class OrganizationInvitation {
  final String id;
  final String organizationId;
  final String organizationName;
  final String email;
  final String normalizedEmail;
  final OrgRole role;
  final InvitationStatus status;
  final String invitedBy;
  final String invitedByName;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String token;

  const OrganizationInvitation({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.email,
    required this.normalizedEmail,
    required this.role,
    required this.status,
    required this.invitedBy,
    required this.invitedByName,
    this.createdAt,
    this.expiresAt,
    this.acceptedBy,
    this.acceptedAt,
    this.rejectedBy,
    this.rejectedAt,
    required this.token,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory OrganizationInvitation.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final email = data['email'] as String? ?? '';
    return OrganizationInvitation(
      id: doc.id,
      organizationId: data['organizationId'] as String? ?? '',
      organizationName: data['organizationName'] as String? ?? '',
      email: email,
      // Backward-compatible: older invitation docs (written before this
      // field existed) never stored normalizedEmail — fall back to
      // normalizing `email` on read rather than losing the ability to
      // match/display those legacy documents.
      normalizedEmail: (data['normalizedEmail'] as String?) ?? email.trim().toLowerCase(),
      role: OrgRole.fromName(data['role'] as String?),
      status: InvitationStatus.fromName(data['status'] as String?),
      invitedBy: data['invitedBy'] as String? ?? '',
      invitedByName: data['invitedByName'] as String? ?? '',
      createdAt: ts(data['createdAt']),
      expiresAt: ts(data['expiresAt']),
      acceptedBy: data['acceptedBy'] as String?,
      acceptedAt: ts(data['acceptedAt']),
      rejectedBy: data['rejectedBy'] as String?,
      rejectedAt: ts(data['rejectedAt']),
      token: data['token'] as String? ?? '',
    );
  }
}

/// Organization staff invitations — a new, additive
/// `organizationInvitations/{invitationId}` collection (nothing existing to
/// reuse here). Membership itself is granted through the existing
/// `organizations/{orgId}/members/{uid}` model (OrgMembershipService),
/// never a second membership store.
///
/// IMPORTANT — no email delivery or secure token validation backend exists
/// in this codebase (no Cloud Functions, no email provider integration).
/// [token] is a client-generated random string, not a cryptographic hash
/// backed by a trusted server — treat acceptance here as a controlled,
/// development-only mechanism, not a production-secure invite link. See
/// this session's final report for exactly what a real deployment needs.
class OrganizationInvitationRepository {
  OrganizationInvitationRepository({FirebaseFirestore? firestore, AuditLogRepository? auditLogRepository})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auditLog = auditLogRepository ?? AuditLogRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final AuditLogRepository _auditLog;
  static final _rng = Random.secure();

  CollectionReference<Map<String, dynamic>> get _invitations => _db.collection('organizationInvitations');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _organizations => _db.collection('organizations');

  String _generateToken() => List.generate(32, (_) => _rng.nextInt(36).toRadixString(36)).join();

  /// Parses each doc individually rather than via a bare `.map(...)` —
  /// spec §11's "Could not load invitations." must come from a genuine
  /// query/rules/index failure, never from one malformed invitation
  /// document throwing inside the mapper and taking the whole list down
  /// with it (the same root cause this app's Rescue Reports list hit
  /// before its own per-doc try/catch fix).
  List<OrganizationInvitation> _parseInvitations(QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <OrganizationInvitation>[];
    for (final doc in snap.docs) {
      try {
        out.add(OrganizationInvitation.fromFirestore(doc));
      } catch (e) {
        debugPrint('[OrganizationInvitationRepository] Skipping unparseable invitation ${doc.id}: $e');
      }
    }
    return out;
  }

  Stream<List<OrganizationInvitation>> streamInvitations(String organizationId) {
    return _invitations
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_parseInvitations);
  }

  /// Every pending invitation addressed to [normalizedEmail], across every
  /// organization — used by Organization Profile for an unlinked account
  /// (spec's invitation-lookup addition), which by definition doesn't know
  /// an organizationId yet to scope by. Callers should still filter out
  /// `isExpired` entries themselves (kept out of this query since Firestore
  /// can't combine an equality filter on `status` with a range filter on
  /// `expiresAt` without a composite index this collection doesn't have).
  Stream<List<OrganizationInvitation>> streamInvitationsForEmail(String normalizedEmail) {
    return _invitations
        .where('normalizedEmail', isEqualTo: normalizedEmail)
        .where('status', isEqualTo: InvitationStatus.pending.name)
        .snapshots()
        .map(_parseInvitations);
  }

  Future<bool> isAlreadyActiveMember({required String organizationId, required String email}) async {
    final normalized = email.trim().toLowerCase();
    final snap = await _db.collection('organizations').doc(organizationId).collection('members').where('email', isEqualTo: normalized).limit(1).get();
    return snap.docs.isNotEmpty;
  }

  Future<OrganizationInvitation?> findActiveInvitation({required String organizationId, required String email}) async {
    final normalized = email.trim().toLowerCase();
    final snap = await _invitations
        .where('organizationId', isEqualTo: organizationId)
        .where('normalizedEmail', isEqualTo: normalized)
        .where('status', isEqualTo: InvitationStatus.pending.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return OrganizationInvitation.fromFirestore(snap.docs.first);
  }

  /// Deterministic per-(org, email) doc id — makes the actual create step
  /// below atomic against a concurrent duplicate invite for the exact same
  /// organization+email (the highest-value race to close, since Firestore
  /// transactions here can only `get()` a single DocumentReference, not an
  /// arbitrary query — see the class doc comment on why full multi-check
  /// transactional dedup across `members`/`organizationInvitations` isn't
  /// possible with this SDK). `isAlreadyActiveMember`/`findActiveInvitation`
  /// remain separate best-effort pre-checks for a fast, friendly error
  /// before ever reaching this call.
  String _invitationDocId({required String organizationId, required String normalizedEmail}) =>
      '${organizationId}_$normalizedEmail';

  Future<String> createInvitation({
    required String organizationId,
    required String organizationName,
    required String email,
    required OrgRole role,
    required String invitedBy,
    String invitedByName = '',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final ref = _invitations.doc(_invitationDocId(organizationId: organizationId, normalizedEmail: normalizedEmail));

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final status = InvitationStatus.fromName(snap.data()?['status'] as String?);
        final expiresAt = snap.data()?['expiresAt'];
        final expired = expiresAt is Timestamp && DateTime.now().isAfter(expiresAt.toDate());
        if (status == InvitationStatus.pending && !expired) {
          throw StateError('An invitation is already pending for this email.');
        }
      }
      tx.set(ref, {
        'organizationId': organizationId,
        'organizationName': organizationName,
        'email': email.trim(),
        'normalizedEmail': normalizedEmail,
        'role': role.name,
        'status': InvitationStatus.pending.name,
        'invitedBy': invitedBy,
        'invitedByName': invitedByName,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        'acceptedAt': null,
        'acceptedBy': null,
        'rejectedAt': null,
        'rejectedBy': null,
        'token': _generateToken(),
      });
    });
    return ref.id;
  }

  /// Bumps the SAME invitation doc's expiry/createdAt rather than creating
  /// a second document — this is what "Resend should not create unlimited
  /// duplicate invitation documents" means in practice.
  Future<void> resendInvitation(String invitationId) async {
    await _invitations.doc(invitationId).update({
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'createdAt': FieldValue.serverTimestamp(),
      'token': _generateToken(), // invalidates any previously-copied link
    });
  }

  Future<void> changeInvitationRole(String invitationId, OrgRole role) async {
    await _invitations.doc(invitationId).update({'role': role.name});
  }

  Future<void> revokeInvitation(String invitationId) async {
    await _invitations.doc(invitationId).update({'status': InvitationStatus.revoked.name});
  }

  /// Development-only acceptance path (spec §12's explicit allowance when no
  /// email/deep-link backend exists): the signed-in account's email must
  /// match the invitation's email, the invitation must still be pending and
  /// unexpired, the target organization must still exist, the account must
  /// not already be linked to a *different* organization, and the whole
  /// grant is wrapped in a transaction so a double-tap/duplicate call can't
  /// accept the same invitation twice or leave a half-applied membership.
  ///
  /// [preserveAccountRole] — when true, never overwrites `users/{uid}.role`.
  /// Set this for an account that already has a real app role (e.g. an
  /// admin joining an organization through Organization Profile's
  /// invitation flow) so acceptance never re-routes them out of their
  /// existing role's UI. Left false for the original organization-signup
  /// acceptance path, which intentionally sets `role: 'organization'`.
  Future<void> acceptInvitation({
    required String invitationId,
    required String uid,
    required String signedInEmail,
    bool preserveAccountRole = false,
  }) async {
    final ref = _invitations.doc(invitationId);
    late OrgRole grantedRole;
    late String organizationId;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final userSnap = await tx.get(_users.doc(uid));
      if (!snap.exists) throw StateError('This invitation no longer exists.');
      final data = snap.data()!;
      final status = InvitationStatus.fromName(data['status'] as String?);
      if (status != InvitationStatus.pending) {
        throw StateError('This invitation is no longer pending.');
      }
      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp && DateTime.now().isAfter(expiresAt.toDate())) {
        throw StateError('This invitation has expired.');
      }
      final invitedEmail = (data['normalizedEmail'] as String? ?? '').trim();
      if (invitedEmail != signedInEmail.trim().toLowerCase()) {
        throw StateError('This invitation was sent to a different email address.');
      }

      organizationId = data['organizationId'] as String? ?? '';
      final orgSnap = await tx.get(_organizations.doc(organizationId));
      if (!orgSnap.exists) throw StateError('This organization no longer exists.');

      final existingOrgId = userSnap.data()?['organizationId'] as String?;
      if (existingOrgId != null && existingOrgId.isNotEmpty && existingOrgId != organizationId) {
        throw StateError('This account is already linked to a different organization.');
      }

      // Already an active member of THIS SAME organization (e.g. a double
      // tap raced two acceptances of the same invitation) — the invitation
      // status update below still needs to happen, but never overwrite an
      // existing membership doc's role/joinedAt.
      final memberRef = _organizations.doc(organizationId).collection('members').doc(uid);
      final existingMemberSnap = await tx.get(memberRef);

      grantedRole = OrgRole.fromName(data['role'] as String?);
      final normalizedSignedInEmail = signedInEmail.trim().toLowerCase();
      final displayName = userSnap.data()?['name'] as String?;

      tx.update(ref, {'status': InvitationStatus.accepted.name, 'acceptedAt': FieldValue.serverTimestamp(), 'acceptedBy': uid});
      if (!existingMemberSnap.exists) {
        tx.set(memberRef, {
          'uid': uid,
          'organizationId': organizationId,
          'role': grantedRole.name,
          'email': signedInEmail.trim(),
          'normalizedEmail': normalizedSignedInEmail,
          if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
          'invitedBy': data['invitedBy'],
          'invitationId': ref.id,
        });
      }
      tx.set(_users.doc(uid), {
        'organizationId': organizationId,
        if (!preserveAccountRole) 'role': 'organization',
      }, SetOptions(merge: true));
    });
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Staff added',
      actorId: uid,
      actorEmail: signedInEmail,
      organizationId: organizationId,
      targetType: 'OrgMember',
      targetId: uid,
      newValues: {'role': grantedRole.name},
    );
  }

  /// The invited person's own decline action (distinct from
  /// [revokeInvitation], which is the organization side cancelling it).
  /// Never creates a membership — only the invitation doc is updated, kept
  /// (not deleted) so its history remains visible on both the org's and the
  /// invited user's invitation lists.
  Future<void> rejectInvitation({
    required String invitationId,
    required String uid,
    required String signedInEmail,
  }) async {
    final ref = _invitations.doc(invitationId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('This invitation no longer exists.');
      final data = snap.data()!;
      final status = InvitationStatus.fromName(data['status'] as String?);
      if (status != InvitationStatus.pending) {
        throw StateError('This invitation is no longer pending.');
      }
      final invitedEmail = (data['normalizedEmail'] as String? ?? '').trim();
      if (invitedEmail != signedInEmail.trim().toLowerCase()) {
        throw StateError('This invitation was sent to a different email address.');
      }
      tx.update(ref, {
        'status': InvitationStatus.rejected.name,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': uid,
      });
    });
  }

  /// Blocks removing the final active Admin — every organization must keep
  /// at least one.
  Future<bool> isFinalAdmin({required String organizationId, required String uid}) async {
    final admins = await _db.collection('organizations').doc(organizationId).collection('members').where('role', isEqualTo: OrgRole.admin.name).get();
    return admins.docs.length <= 1 && admins.docs.any((d) => d.id == uid);
  }

  Future<void> removeMember({
    required String organizationId,
    required String uid,
    String? actorId,
    String? actorName,
  }) async {
    await _db.collection('organizations').doc(organizationId).collection('members').doc(uid).delete();
    // Clears the account's org association so access is revoked on the
    // next auth/provider refresh — never deletes the Firebase Auth account
    // itself.
    await _users.doc(uid).update({'organizationId': FieldValue.delete()});
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Staff removed',
      actorId: actorId,
      actorName: actorName,
      organizationId: organizationId,
      targetType: 'OrgMember',
      targetId: uid,
    );
  }

  Future<void> changeMemberRole({
    required String organizationId,
    required String uid,
    required OrgRole role,
    String? actorId,
    String? actorName,
  }) async {
    await OrgMembershipService(firestore: _db).setMember(organizationId: organizationId, uid: uid, role: role);
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Staff role changed',
      actorId: actorId,
      actorName: actorName,
      organizationId: organizationId,
      targetType: 'OrgMember',
      targetId: uid,
      newValues: {'role': role.name},
    );
  }
}
