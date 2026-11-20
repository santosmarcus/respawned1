import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';
import 'package:respawnd1/core/utils/stream_combine.dart';
import 'package:respawnd1/core/utils/validators.dart';

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

  /// Set instead of [email] for an invitation by mobile number; matched
  /// against the invitee's verified sign-in number (+639XXXXXXXXX).
  final String phone;
  final String normalizedPhone;
  final OrgRole role;

  /// What the invited Staff member will be able to do (every permission
  /// for an Admin). Older invitations without a list fall back by role
  /// (staffPermissionsFrom), like members docs.
  final Set<OrgPermission> permissions;
  final OrgPreset? preset;

  /// The stored role, which may be the legacy 'carer'.
  final String rawRole;
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
    this.phone = '',
    this.normalizedPhone = '',
    required this.role,
    this.permissions = const {},
    this.preset,
    this.rawRole = '',
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

  bool get isPhoneInvite => normalizedEmail.isEmpty && normalizedPhone.isNotEmpty;

  /// Who it was sent to: the email, or the mobile number.
  String get contactLabel => isPhoneInvite ? (phone.isNotEmpty ? phone : normalizedPhone) : email;

  /// One key per invitee, for de-duplicating lists.
  String get contactKey => isPhoneInvite ? 'phone:$normalizedPhone' : 'email:$normalizedEmail';

  /// "Organization Admin", "Staff" or "Staff · Custom access".
  String get accessLabel =>
      role == OrgRole.admin ? OrgRole.admin.memberTitle : staffTitle(preset);

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
      phone: data['phone'] as String? ?? '',
      normalizedPhone: data['normalizedPhone'] as String? ?? '',
      role: OrgRole.fromName(data['role'] as String?),
      permissions: OrgRole.fromName(data['role'] as String?) == OrgRole.admin
          ? OrgPermission.values.toSet()
          : staffPermissionsFrom(data),
      preset: OrgRole.fromName(data['role'] as String?) == OrgRole.admin
          ? null
          : OrgPreset.matching(staffPermissionsFrom(data)),
      rawRole: data['role'] as String? ?? '',
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

  /// Whether an invitation doc is for this account: its email, or its
  /// verified phone number. An empty side never matches.
  static bool _addressedTo(Map<String, dynamic> data, {required String email, required String phone}) {
    final invitedEmail = (data['normalizedEmail'] as String? ?? '').trim();
    final invitedPhone = (data['normalizedPhone'] as String? ?? '').trim();
    return (invitedEmail.isNotEmpty && invitedEmail == email) || (invitedPhone.isNotEmpty && invitedPhone == phone);
  }

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

  /// Pending invitations sent to this verified mobile number (+639…).
  Stream<List<OrganizationInvitation>> streamInvitationsForPhone(String normalizedPhone) {
    return _invitations
        .where('normalizedPhone', isEqualTo: normalizedPhone)
        .where('status', isEqualTo: InvitationStatus.pending.name)
        .snapshots()
        .map(_parseInvitations);
  }

  /// Pending invitations for the signed-in account, by its email and/or its
  /// verified phone number.
  Stream<List<OrganizationInvitation>> streamMyInvitations({String? email, String? phone}) {
    final e = email?.trim().toLowerCase() ?? '';
    final p = phone?.trim() ?? '';
    final streams = [
      if (e.isNotEmpty) streamInvitationsForEmail(e),
      if (p.isNotEmpty) streamInvitationsForPhone(p),
    ];
    if (streams.isEmpty) return Stream.value(const []);
    if (streams.length == 1) return streams.first;
    return combineLatest(streams).map((lists) {
      final seen = <String>{};
      return [for (final l in lists) ...l].where((i) => seen.add(i.id)).toList();
    });
  }

  Future<bool> isAlreadyActiveMemberByPhone({required String organizationId, required String normalizedPhone}) async {
    final snap = await _db
        .collection('organizations')
        .doc(organizationId)
        .collection('members')
        .where('normalizedPhone', isEqualTo: normalizedPhone)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<OrganizationInvitation?> findActiveInvitationByPhone({
    required String organizationId,
    required String normalizedPhone,
  }) async {
    final snap = await _invitations
        .where('organizationId', isEqualTo: organizationId)
        .where('normalizedPhone', isEqualTo: normalizedPhone)
        .where('status', isEqualTo: InvitationStatus.pending.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return OrganizationInvitation.fromFirestore(snap.docs.first);
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
    String email = '',
    /// Instead of [email]: a PH mobile number, matched against the
    /// invitee's verified phone sign-in.
    String phone = '',
    required OrgRole role,
    Set<OrgPermission> permissions = const {},
    required String invitedBy,
    String invitedByName = '',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final byPhone = normalizedEmail.isEmpty;
    final normalizedPhone = byPhone ? normalizePhPhone(phone) : null;
    if (byPhone && normalizedPhone == null) {
      throw ArgumentError('Enter a valid Philippine mobile number.');
    }
    final ref = _invitations.doc(byPhone
        ? '${organizationId}_phone_${normalizedPhone!.substring(1)}'
        : _invitationDocId(organizationId: organizationId, normalizedEmail: normalizedEmail));

    // No transactional read first: for a first invite the doc doesn't exist
    // yet, and reading a missing invitation used to be denied by the rules
    // (permission-denied for every org admin). The friendly duplicate checks
    // run before this call (findActiveInvitation / isAlreadyActiveMember);
    // the deterministic id still keeps one doc per org+email, so a racing
    // duplicate only refreshes the same pending invitation.
    await ref.set({
      'organizationId': organizationId,
      'organizationName': organizationName,
      'email': email.trim(),
      'normalizedEmail': normalizedEmail,
      if (byPhone) ...{
        'phone': phone.trim(),
        'normalizedPhone': normalizedPhone,
      },
      'role': role.name,
      ..._accessFields(role, permissions),
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
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Invitation sent',
      actorId: invitedBy,
      actorName: invitedByName,
      organizationId: organizationId,
      targetType: 'Invitation',
      targetId: ref.id,
      newValues: {if (byPhone) 'phone': normalizedPhone else 'email': email.trim(), 'role': role.name},
    );
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

  /// The permissions an invitation carries: a Staff list and its preset;
  /// none for an Admin. Accepting copies them onto the member exactly
  /// (firestore.rules checks they match).
  static Map<String, dynamic> _accessFields(OrgRole role, Set<OrgPermission> permissions) {
    if (role == OrgRole.admin) return const {};
    final perms = normalizePermissions(permissions);
    return {'permissions': permissionKeys(perms), 'preset': OrgPreset.matching(perms).name};
  }

  Future<void> changeInvitationAccess(String invitationId, OrgRole role, Set<OrgPermission> permissions) async {
    await _invitations.doc(invitationId).update({
      'role': role.name,
      'permissions': role == OrgRole.admin ? FieldValue.delete() : permissionKeys(normalizePermissions(permissions)),
      'preset': role == OrgRole.admin ? FieldValue.delete() : OrgPreset.matching(normalizePermissions(permissions)).name,
    });
  }

  Future<void> revokeInvitation(String invitationId, {String? actorId, String? actorName}) async {
    final ref = _invitations.doc(invitationId);
    final before = (await ref.get()).data();
    await ref.update({'status': InvitationStatus.revoked.name});
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Invitation revoked',
      actorId: actorId ?? FirebaseAuth.instance.currentUser?.uid,
      actorName: actorName,
      organizationId: before?['organizationId'] as String?,
      targetType: 'Invitation',
      targetId: invitationId,
      oldValues: {'email': ?before?['email'], 'role': ?before?['role']},
    );
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
    String? signedInEmail,
    /// The account's verified phone sign-in number (User.phoneNumber).
    String? signedInPhone,
    bool preserveAccountRole = false,
  }) async {
    final myEmail = signedInEmail?.trim().toLowerCase() ?? '';
    final myPhone = signedInPhone?.trim() ?? '';
    final ref = _invitations.doc(invitationId);
    late String grantedRole;
    Object? grantedPermissions;
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
      if (!_addressedTo(data, email: myEmail, phone: myPhone)) {
        throw StateError('This invitation was sent to a different email address or mobile number.');
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

      // Copied exactly as the invitation names them (firestore.rules
      // compares role, permissions and preset with the invitation).
      grantedRole = (data['role'] as String?) ?? OrgRole.staff.name;
      grantedPermissions = data['permissions'];
      final displayName = userSnap.data()?['name'] as String?;

      tx.update(ref, {'status': InvitationStatus.accepted.name, 'acceptedAt': FieldValue.serverTimestamp(), 'acceptedBy': uid});
      if (!existingMemberSnap.exists) {
        tx.set(memberRef, {
          'uid': uid,
          'organizationId': organizationId,
          'role': grantedRole,
          if (data.containsKey('permissions')) 'permissions': data['permissions'],
          if (data.containsKey('preset')) 'preset': data['preset'],
          'email': signedInEmail?.trim() ?? '',
          'normalizedEmail': myEmail,
          if (myPhone.isNotEmpty) ...{
            'phone': myPhone,
            'normalizedPhone': myPhone,
          },
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
      actorEmail: (signedInEmail?.isNotEmpty ?? false) ? signedInEmail : (myPhone.isEmpty ? null : myPhone),
      organizationId: organizationId,
      targetType: 'OrgMember',
      targetId: uid,
      newValues: {'role': grantedRole, 'permissions': ?grantedPermissions},
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
    String? signedInEmail,
    String? signedInPhone,
  }) async {
    final myEmail = signedInEmail?.trim().toLowerCase() ?? '';
    final myPhone = signedInPhone?.trim() ?? '';
    final ref = _invitations.doc(invitationId);
    String? organizationId;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('This invitation no longer exists.');
      final data = snap.data()!;
      final status = InvitationStatus.fromName(data['status'] as String?);
      if (status != InvitationStatus.pending) {
        throw StateError('This invitation is no longer pending.');
      }
      if (!_addressedTo(data, email: myEmail, phone: myPhone)) {
        throw StateError('This invitation was sent to a different email address or mobile number.');
      }
      organizationId = data['organizationId'] as String?;
      tx.update(ref, {
        'status': InvitationStatus.rejected.name,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': uid,
      });
    });
    await _auditLog.log(
      category: AuditCategory.organizationStaff,
      action: 'Invitation declined',
      actorId: uid,
      actorEmail: (signedInEmail?.isNotEmpty ?? false) ? signedInEmail : (myPhone.isEmpty ? null : myPhone),
      organizationId: organizationId,
      targetType: 'Invitation',
      targetId: invitationId,
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
    // Unlink the account FIRST: an org-linked account with no members doc is
    // treated as legacy full staff (app and firestore.rules), so deleting
    // the members doc first gave a removed member full access in between.
    // Never deletes the Firebase Auth account itself.
    await _users.doc(uid).update({'organizationId': FieldValue.delete()});
    await _db.collection('organizations').doc(organizationId).collection('members').doc(uid).delete();
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
}
