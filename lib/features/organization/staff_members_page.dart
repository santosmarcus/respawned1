import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/main.dart' show AuthWrapper, appNavigatorKey;
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/org_member_access_repository.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/repos/organization_invitation_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/organization/widgets/member_access_editor.dart';

/// Staff Members + Invitations. Active members are read straight from
/// `organizations/{orgId}/members` — the existing OrgMembershipService
/// model — rather than a second staff-list store. Invitations use the
/// `organizationInvitations` collection (OrganizationInvitationRepository);
/// see that file's doc comment for the honest state of email delivery.
///
/// [organizationId] is nullable (Organization Invitations spec §8): an
/// account with no accepted membership yet still needs somewhere to see
/// and act on invitations addressed to it ("My Pending Invitations"),
/// without a real organization to scope Staff Members/Organization Pending
/// Invitations to — those two sections simply don't render when null.
class StaffMembersPage extends StatefulWidget {
  final String? organizationId;
  const StaffMembersPage({super.key, this.organizationId});

  @override
  State<StaffMembersPage> createState() => _StaffMembersPageState();
}

class _StaffMembersPageState extends State<StaffMembersPage> {
  final _repo = OrganizationInvitationRepository();

  // Root cause of the "Pending Invitations appears/disappears/reappears"
  // flicker (still relevant to the two new streams below): a Stream
  // created INLINE inside StreamBuilder's `stream:` argument in build() is
  // a fresh Stream (fresh Firestore query + fresh .map()) on every single
  // rebuild of this page. StreamBuilder treats a changed `stream`
  // reference as "the old subscription is gone, go back to
  // ConnectionState.waiting" while still holding the previous data.
  // Hoisting every stream into a `late final` field — created exactly ONCE
  // for the lifetime of this State — gives every StreamBuilder one stable,
  // long-lived subscription, matching "use stable stream instances" / "do
  // not create new stream instances in every widget build".
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _membersStream = widget.organizationId == null
      ? null
      : FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).collection('members').snapshots();
  late final Stream<List<OrganizationInvitation>>? _orgInvitationsStream =
      widget.organizationId == null ? null : _repo.streamInvitations(widget.organizationId!);

  // Normalized once (spec §12 "normalize the user email once"), not
  // recomputed on every build.
  late final String? _signedInEmail = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
  late final String? _signedInPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
  late final Stream<List<OrganizationInvitation>> _myInvitationsStream =
      _repo.streamMyInvitations(email: _signedInEmail, phone: _signedInPhone);

  /// Only the organization's owner or an active Admin invites, edits and
  /// removes members (firestore.rules and the setMemberAccess callable
  /// enforce it). Staff see the list read-only.
  bool _isOrgAdmin = false;

  /// The organization's owner: always an Admin, never edited or removed.
  String? _ownerId;
  Map<String, dynamic>? _orgData;

  // Guards double-tap on the SAME invitation's Accept/Reject — a different
  // invitation's buttons stay usable while one is in flight.
  String? _processingInvitationId;

  // Email-resolution cache (spec §10's fallback chain: membership.email ->
  // users/{uid}.email -> invitation email -> "Email unavailable") — at most
  // one lookup per uid for the lifetime of this page, never repeated on
  // every rebuild.
  final Map<String, String?> _resolvedEmails = {};
  final Set<String> _resolvingUids = {};

  // Organization-name resolution cache for invitations missing their own
  // stored organizationName (legacy docs) — spec §15's fallback chain.
  final Map<String, String?> _resolvedOrgNames = {};
  final Set<String> _resolvingOrgIds = {};
  // Owner/Admin only: access changes and removal.
  bool _canManageMembers = false;

  @override
  void initState() {
    super.initState();
    if (widget.organizationId != null) _loadIsOrgAdmin();
  }

  Future<void> _loadIsOrgAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final capabilities = await OrgMembershipService().resolveCapabilities(uid);
    final org = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
    if (mounted) {
      setState(() {
        _isOrgAdmin = capabilities.canManageTeam;
        _canManageMembers = capabilities.canManageMembers;
        _ownerId = org.data()?['ownerId'] as String?;
        _orgData = org.data();
      });
    }
  }

  Future<void> _resolveEmailIfNeeded(String uid, {String? invitationId}) async {
    if (_resolvedEmails.containsKey(uid) || _resolvingUids.contains(uid)) return;
    _resolvingUids.add(uid);
    String? email;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      email = userDoc.data()?['email'] as String?;
      if ((email == null || email.trim().isEmpty) && invitationId != null && invitationId.isNotEmpty) {
        final inviteDoc = await FirebaseFirestore.instance.collection('organizationInvitations').doc(invitationId).get();
        email = inviteDoc.data()?['email'] as String?;
      }
    } catch (_) {
      email = null;
    }
    _resolvingUids.remove(uid);
    _resolvedEmails[uid] = (email != null && email.trim().isNotEmpty) ? email : null;
    if (mounted) setState(() {});
  }

  Future<void> _resolveOrgNameIfNeeded(String organizationId) async {
    if (_resolvedOrgNames.containsKey(organizationId) || _resolvingOrgIds.contains(organizationId)) return;
    _resolvingOrgIds.add(organizationId);
    String? name;
    try {
      final orgDoc = await FirebaseFirestore.instance.collection('organizations').doc(organizationId).get();
      name = orgDoc.data()?['name'] as String?;
    } catch (_) {
      name = null;
    }
    _resolvingOrgIds.remove(organizationId);
    _resolvedOrgNames[organizationId] = (name != null && name.trim().isNotEmpty) ? name : null;
    if (mounted) setState(() {});
  }

  String _organizationNameFor(OrganizationInvitation invite) {
    if (invite.organizationName.trim().isNotEmpty) return invite.organizationName;
    final cached = _resolvedOrgNames[invite.organizationId];
    if (cached != null) return cached;
    _resolveOrgNameIfNeeded(invite.organizationId);
    return 'Organization';
  }

  /// What the organization has at all: null (everything) for a shelter.
  Set<OrgPermission>? get _available =>
      OrgKind.fromName(_orgData?['kind'] as String?) == OrgKind.independent ? orgEnabledPermissions(_orgData) : null;

  Future<void> _openAddMemberSheet() async {
    if (!_isOrgAdmin) return;
    // An independent rescuer's team is capped (firestore.rules refuses the
    // invitation too).
    if (OrgKind.fromName(_orgData?['kind'] as String?) == OrgKind.independent) {
      final count = (_orgData?['memberCount'] as num?)?.toInt() ?? 1;
      final cap = (_orgData?['memberCap'] as num?)?.toInt() ?? IndependentRescuer.memberCap;
      if (count >= cap) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          'Your team is full ($cap people). Remove someone first, or ask a system admin for a bigger team.',
          kind: AppMessageKind.error,
        ));
        return;
      }
    }
    final available = _available;
    final result = await showMemberAccessSheet(
      context,
      title: 'Invite Staff Member',
      available: available,
      initial: MemberAccess(OrgRole.staff, {
        ...available == null ? OrgPreset.staff.permissions : OrgPreset.staff.permissions.intersection(available),
      }),
      confirmLabel: 'Send Invitation',
      askEmail: true,
      allowPhone: true,
      validateEmail: AppValidators.email,
    );
    if (result == null || !mounted) return;
    if (result.phone.isNotEmpty) {
      await _submitPhoneInvite(result.phone, result.access);
    } else {
      await _submitInvite(result.email, result.access);
    }
  }

  /// Invite by mobile number: matched when that person signs in with the
  /// same number (phone sign-in), so it needs no email at all.
  Future<void> _submitPhoneInvite(String phone, MemberAccess access) async {
    final organizationId = widget.organizationId;
    if (organizationId == null || !_isOrgAdmin) {
      _snack('You do not have permission to add members.', error: true);
      return;
    }
    final normalized = normalizePhPhone(phone);
    if (normalized == null) {
      _snack('Enter a valid Philippine mobile number.', error: true);
      return;
    }
    if (_signedInPhone != null && _signedInPhone == normalized) {
      _snack('You cannot invite your own number.', error: true);
      return;
    }
    try {
      if (await _repo.isAlreadyActiveMemberByPhone(organizationId: organizationId, normalizedPhone: normalized)) {
        _snack('This person is already a member.', error: true);
        return;
      }
      final existing = await _repo.findActiveInvitationByPhone(organizationId: organizationId, normalizedPhone: normalized);
      if (existing != null && !existing.isExpired) {
        _snack('An invitation is already pending for this number.', error: true);
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(organizationId).get();
      await _repo.createInvitation(
        organizationId: organizationId,
        organizationName: doc.data()?['name'] as String? ?? '',
        phone: phone,
        role: access.role,
        permissions: access.permissions,
        invitedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        invitedByName: FirebaseAuth.instance.currentUser?.displayName ?? '',
      );
      _snack('Invitation created for $normalized. They join by signing in with that number.');
    } catch (e) {
      debugPrint('[StaffMembersPage] createInvitation (phone) failed: $e');
      _snack('The invitation could not be created.', error: true);
    }
  }

  Future<void> _submitInvite(String email, MemberAccess access) async {
    final organizationId = widget.organizationId;
    if (organizationId == null || !_isOrgAdmin) {
      _snack('You do not have permission to add members.', error: true);
      return;
    }
    final normalized = email.trim().toLowerCase();
    final selfEmail = _signedInEmail;
    if (selfEmail != null && selfEmail == normalized) {
      _snack('You cannot invite your own email.', error: true);
      return;
    }
    try {
      if (await _repo.isAlreadyActiveMember(organizationId: organizationId, email: email)) {
        _snack('This person is already a member.', error: true);
        return;
      }
      final existing = await _repo.findActiveInvitation(organizationId: organizationId, email: email);
      if (existing != null && !existing.isExpired) {
        _snack('An invitation is already pending for this email.', error: true);
        return;
      }

      // No `users` lookup gate here on purpose — invitations are addressed
      // by normalized email and remain pending until that person signs up
      // or logs in and matches it at acceptance time (see
      // OrganizationInvitationRepository.acceptInvitation), so someone
      // without an existing account is never incorrectly told their email
      // is invalid or unrecognized. And no "role already occupied" check —
      // an organization may have any number of Admins and any number of
      // Members (spec §14); the only real limits are one membership per
      // person and one pending invitation per (org, email) pair, both
      // already checked above.
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(organizationId).get();
      final orgName = doc.data()?['name'] as String? ?? '';
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final inviterName = FirebaseAuth.instance.currentUser?.displayName ?? '';
      await _repo.createInvitation(
        organizationId: organizationId,
        organizationName: orgName,
        email: email,
        role: access.role,
        permissions: access.permissions,
        invitedBy: uid,
        invitedByName: inviterName,
      );
      _snack('Invitation sent to $email.');
    } catch (e) {
      debugPrint('[StaffMembersPage] createInvitation failed: $e');
      _snack('The invitation could not be created.', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
      message,
      kind: error ? AppMessageKind.error : AppMessageKind.info,
    ));
  }

  Future<void> _editMemberAccess(String uid, Map<String, dynamic> data) async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    final current = OrgMembership.fromMemberData(organizationId, data);
    final result = await showMemberAccessSheet(
      context,
      title: 'What can this member do?',
      available: _available,
      initial: MemberAccess(current.role, current.permissions),
      confirmLabel: 'Save',
      roleLocked: uid == _ownerId,
    );
    if (result == null || !mounted) return;
    final next = result.access;
    if (current.role == OrgRole.admin && next.role != OrgRole.admin) {
      final confirmed = await showConfirmActionDialog(
        context,
        title: "Change this Admin to Staff?",
        message: 'They will only be able to do what is ticked, and can no longer manage members or settings.',
        confirmLabel: 'Change',
      );
      if (confirmed != true) return;
    }
    try {
      // The callable checks the owner stays an Admin and that an active
      // Admin remains, and writes the audit entry.
      await OrgMemberAccessRepository().setAccess(
        organizationId: organizationId,
        memberUid: uid,
        role: next.role,
        permissions: next.permissions,
      );
      _snack('Access updated.');
    } catch (e) {
      debugPrint('[StaffMembersPage] setMemberAccess failed: $e');
      _snack(OrgMemberAccessRepository.errorMessage(e), error: true);
    }
  }

  Future<void> _removeMember(String uid) async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    if (uid == _ownerId) {
      _snack("The organization's owner can't be removed.", error: true);
      return;
    }
    if (await _repo.isFinalAdmin(organizationId: organizationId, uid: uid)) {
      _snack('This is the only Admin on this organization and cannot be removed.', error: true);
      return;
    }
    if (!mounted) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Remove this member?',
      message: 'They will lose access to this organization. This does not delete their account.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await _repo.removeMember(
        organizationId: organizationId,
        uid: uid,
        actorId: FirebaseAuth.instance.currentUser?.uid,
        actorName: FirebaseAuth.instance.currentUser?.displayName,
      );
      _snack('Member removed.');
    } catch (e) {
      debugPrint('[StaffMembersPage] removeMember failed: $e');
      _snack('Could not remove member.', error: true);
    }
  }

  Future<void> _acceptMyInvitation(OrganizationInvitation invite) async {
    if (_processingInvitationId != null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email == null && user.phoneNumber == null)) return;
    setState(() => _processingInvitationId = invite.id);
    try {
      await _repo.acceptInvitation(
        invitationId: invite.id,
        uid: user.uid,
        signedInEmail: user.email,
        signedInPhone: user.phoneNumber,
        // Reached from many entry points (already-admin accounts, brand
        // new Organization Member signups) — never clobber whatever
        // account role got them to this page.
        preserveAccountRole: true,
      );
      _snack('You joined ${_organizationNameFor(invite)}.');
      // A member who had no organization yet: restart from AuthWrapper, which
      // now opens their organization, so back doesn't return to invitations.
      if (widget.organizationId == null && mounted) {
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[StaffMembersPage] acceptInvitation failed: $e');
      _snack('Could not accept this invitation. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _processingInvitationId = null);
    }
  }

  Future<void> _rejectMyInvitation(OrganizationInvitation invite) async {
    if (_processingInvitationId != null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email == null && user.phoneNumber == null)) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Reject this invitation?',
      message: 'You will not join ${_organizationNameFor(invite)}. This cannot be undone from here.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _processingInvitationId = invite.id);
    try {
      await _repo.rejectInvitation(
        invitationId: invite.id,
        uid: user.uid,
        signedInEmail: user.email,
        signedInPhone: user.phoneNumber,
      );
      _snack('Invitation rejected.');
    } catch (e) {
      debugPrint('[StaffMembersPage] rejectInvitation failed: $e');
      _snack('Could not reject this invitation. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _processingInvitationId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Staff Members', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
        actions: [
          if (_isOrgAdmin)
            IconButton(icon: const Icon(Icons.person_add_alt_outlined, color: AppColors.background), onPressed: _openAddMemberSheet),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.organizationId == null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No organization joined yet.', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Accept an organization invitation below to get started.',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (widget.organizationId != null) ...[
            Text('Staff Members', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _membersStream!,
              builder: (context, snapshot) {
                // Loading is only the "before the first result ever" state
                // — once any data has arrived, a stale-but-valid list is
                // always preferred over a spinner or an empty state.
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError && !snapshot.hasData) {
                  return Text('Could not load staff members.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Text('No staff members yet', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
                }
                return Column(
                  children: [
                    for (final doc in docs)
                      Builder(builder: (context) {
                        final data = doc.data();
                        final uid = doc.id;
                        final directEmail = data['email'] as String?;
                        String? email;
                        if (directEmail != null && directEmail.trim().isNotEmpty) {
                          email = directEmail;
                        } else if (_resolvedEmails.containsKey(uid)) {
                          email = _resolvedEmails[uid];
                        } else {
                          _resolveEmailIfNeeded(uid, invitationId: data['invitationId'] as String?);
                        }
                        // Your own row never needs a lookup — the signed-in
                        // account's email is always known locally.
                        if ((email == null || email.trim().isEmpty) && uid == currentUid) {
                          email = FirebaseAuth.instance.currentUser?.email;
                        }
                        return _MemberRow(
                          displayName: data['displayName'] as String?,
                          email: email,
                          membership: OrgMembership.fromMemberData(widget.organizationId!, data),
                          isOwner: uid == _ownerId,
                          status: data['status'] as String? ?? 'active',
                          isSelf: uid == currentUid,
                          canManage: _canManageMembers,
                          onEditAccess: () => _editMemberAccess(uid, data),
                          onRemove: () => _removeMember(uid),
                        );
                      }),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          if (widget.organizationId != null && _isOrgAdmin) ...[
            Text('Organization Pending Invitations', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            StreamBuilder<List<OrganizationInvitation>>(
              stream: _orgInvitationsStream!,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError && !snapshot.hasData) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Could not load invitations.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      OutlinedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                    ],
                  );
                }
                // Deduped by normalized email — `createInvitation` keys new
                // invitations by a deterministic organizationId_normalizedEmail
                // doc id so duplicates can't be newly created, but this is a
                // defensive backstop against any pre-existing legacy
                // duplicate docs. streamInvitations orders by createdAt
                // descending, so `seen.add(...)` (true only the first time)
                // keeps the most recent one.
                final seenEmails = <String>{};
                final invites = (snapshot.data ?? const [])
                    .where((i) => i.status == InvitationStatus.pending)
                    .where((i) => seenEmails.add(i.contactKey))
                    .toList();
                if (invites.isEmpty) {
                  return Text('No pending invitations', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
                }
                return Column(
                  children: [
                    for (final invite in invites)
                      _InvitationRow(
                        invitation: invite,
                        onResend: () async {
                          await _repo.resendInvitation(invite.id);
                          _snack('Invitation resent.');
                        },
                        onChangeRole: () async {
                          final result = await showMemberAccessSheet(
                            context,
                            title: 'Change invitation access',
                            initial: MemberAccess(invite.role, invite.permissions),
                            confirmLabel: 'Save',
                          );
                          if (result == null) return;
                          await _repo.changeInvitationAccess(invite.id, result.access.role, result.access.permissions);
                          _snack('Invitation updated.');
                        },
                        onRevoke: () async {
                          await _repo.revokeInvitation(invite.id);
                          _snack('Invitation cancelled.');
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          Text('My Pending Invitations', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          StreamBuilder<List<OrganizationInvitation>>(
            stream: _myInvitationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError && !snapshot.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Could not load your invitations.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    OutlinedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                  ],
                );
              }
              final invites = (snapshot.data ?? const []).where((i) => !i.isExpired).toList();
              if (invites.isEmpty) {
                return Text('No pending invitations for your account.',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
              }
              return Column(
                children: [
                  for (final invite in invites)
                    _MyInvitationCard(
                      invitation: invite,
                      organizationName: _organizationNameFor(invite),
                      busy: _processingInvitationId == invite.id,
                      onAccept: () => _acceptMyInvitation(invite),
                      onReject: () => _rejectMyInvitation(invite),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String? displayName;
  final String? email;
  final OrgMembership membership;
  final bool isOwner;
  final String status;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onEditAccess;
  final VoidCallback onRemove;
  const _MemberRow({
    required this.displayName,
    required this.email,
    required this.membership,
    required this.isOwner,
    required this.status,
    required this.isSelf,
    required this.canManage,
    required this.onEditAccess,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasName = displayName != null && displayName!.trim().isNotEmpty;
    final primaryLabel = hasName ? displayName! : (email ?? 'Email unavailable');
    final isAdmin = isOwner || membership.role == OrgRole.admin;
    final accessLabel = isOwner
        ? 'Owner · Organization Admin'
        : isAdmin
            ? OrgRole.admin.memberTitle
            : staffTitle(membership.preset);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(primaryLabel,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                    // "You" is a secondary label next to the name, never
                    // appended onto a raw UID (spec §10).
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Text('You', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
                if (hasName && email != null)
                  Text(email!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                Text(accessLabel, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                if (!isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: membership.permissions.isEmpty
                        ? Text('No permissions', style: GoogleFonts.zain(fontSize: 12, color: AppColors.error))
                        : Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final p in OrgPermission.values.where(membership.permissions.contains))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.tearspwn,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(p.label,
                                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary)),
                                ),
                            ],
                          ),
                  ),
                if (status != 'active')
                  Text(status[0].toUpperCase() + status.substring(1),
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (canManage && !isOwner)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEditAccess() : onRemove(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit access')),
                PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
        ],
      ),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  final OrganizationInvitation invitation;
  final VoidCallback onResend;
  final VoidCallback onChangeRole;
  final VoidCallback onRevoke;
  const _InvitationRow({
    required this.invitation,
    required this.onResend,
    required this.onChangeRole,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final sent = invitation.createdAt;
    final sentLabel = sent == null ? '' : '${sent.month}/${sent.day}/${sent.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invitation.contactLabel, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(
                        'Invited as ${invitation.accessLabel} · Sent $sentLabel',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    if (invitation.invitedByName.isNotEmpty)
                      Text('Invited by ${invitation.invitedByName}',
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: invitation.isExpired ? AppColors.slaterspwn : AppColors.yellowrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(invitation.isExpired ? 'Expired' : 'Pending', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Invitation Cleanup spec §1 — Copy Dev Link (a development-only
          // affordance that exposed the raw invitation doc id, standing in
          // for real email delivery) removed; Resend/Change Role/Cancel
          // Invitation are the full retained action set.
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: onResend, child: const Text('Resend')),
              OutlinedButton(onPressed: onChangeRole, child: const Text('Change Access')),
              OutlinedButton(
                onPressed: onRevoke,
                style: AppButtons.dangerOutline,
                child: const Text('Cancel Invitation'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MyInvitationCard extends StatelessWidget {
  final OrganizationInvitation invitation;
  final String organizationName;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _MyInvitationCard({
    required this.invitation,
    required this.organizationName,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final sent = invitation.createdAt;
    final sentLabel = sent == null ? '' : '${sent.month}/${sent.day}/${sent.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(organizationName, style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Invited as ${invitation.accessLabel}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          if (invitation.invitedByName.isNotEmpty)
            Text('Invited by ${invitation.invitedByName}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          if (sentLabel.isNotEmpty)
            Text('Sent $sentLabel', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: AppButtons.dangerOutline,
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.greenrspwn, foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
