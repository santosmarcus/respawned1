import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';

enum InvitationStatus {
  pending,
  accepted,
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
  final OrgRole role;
  final InvitationStatus status;
  final String invitedBy;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String token;

  const OrganizationInvitation({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.email,
    required this.role,
    required this.status,
    required this.invitedBy,
    this.createdAt,
    this.expiresAt,
    required this.token,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory OrganizationInvitation.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return OrganizationInvitation(
      id: doc.id,
      organizationId: data['organizationId'] as String? ?? '',
      organizationName: data['organizationName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: OrgRole.fromName(data['role'] as String?),
      status: InvitationStatus.fromName(data['status'] as String?),
      invitedBy: data['invitedBy'] as String? ?? '',
      createdAt: ts(data['createdAt']),
      expiresAt: ts(data['expiresAt']),
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

  Stream<List<OrganizationInvitation>> streamInvitations(String organizationId) {
    return _invitations
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(OrganizationInvitation.fromFirestore).toList());
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
        .map((snap) => snap.docs.map(OrganizationInvitation.fromFirestore).toList());
  }

  /// True if the given role is already held by an active member, or already
  /// has a live (pending, unexpired) invitation outstanding — the current
  /// one-email-per-role limitation (spec §14). Membership records are kept
  /// per-uid regardless, so this is a UI-level rule, not a schema
  /// limitation — multiple members per role becomes possible later just by
  /// removing this check.
  Future<bool> isRoleOccupied({required String organizationId, required OrgRole role}) async {
    final members = await _db.collection('organizations').doc(organizationId).collection('members').where('role', isEqualTo: role.name).limit(1).get();
    if (members.docs.isNotEmpty) return true;

    final pending = await _invitations
        .where('organizationId', isEqualTo: organizationId)
        .where('role', isEqualTo: role.name)
        .where('status', isEqualTo: InvitationStatus.pending.name)
        .limit(1)
        .get();
    if (pending.docs.isEmpty) return false;
    // A pending doc that's actually expired doesn't count as "occupied".
    final expiresAt = pending.docs.first.data()['expiresAt'];
    if (expiresAt is Timestamp && DateTime.now().isAfter(expiresAt.toDate())) return false;
    return true;
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
  /// possible with this SDK). `isAlreadyActiveMember`/`findActiveInvitation`/
  /// `isRoleOccupied` remain separate best-effort pre-checks for a fast,
  /// friendly error before ever reaching this call.
  String _invitationDocId({required String organizationId, required String normalizedEmail}) =>
      '${organizationId}_$normalizedEmail';

  Future<String> createInvitation({
    required String organizationId,
    required String organizationName,
    required String email,
    required OrgRole role,
    required String invitedBy,
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
          throw StateError('An invitation is already pending.');
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
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        'acceptedAt': null,
        'acceptedBy': null,
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

      grantedRole = OrgRole.fromName(data['role'] as String?);

      tx.update(ref, {'status': InvitationStatus.accepted.name, 'acceptedAt': FieldValue.serverTimestamp(), 'acceptedBy': uid});
      final memberRef = _organizations.doc(organizationId).collection('members').doc(uid);
      tx.set(memberRef, {
        'role': grantedRole.name,
        'email': signedInEmail.trim().toLowerCase(),
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
        'invitedBy': data['invitedBy'],
      });
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
