import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/repos/organization_invitation_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';

/// Staff Members (spec §10-13). Active members are read straight from
/// `organizations/{orgId}/members` — the existing OrgMembershipService
/// model — rather than a second staff-list store. Invitations use the new
/// `organizationInvitations` collection (OrganizationInvitationRepository);
/// see that file's doc comment for the honest state of email delivery.
class StaffMembersPage extends StatefulWidget {
  final String organizationId;
  const StaffMembersPage({super.key, required this.organizationId});

  @override
  State<StaffMembersPage> createState() => _StaffMembersPageState();
}

class _StaffMembersPageState extends State<StaffMembersPage> {
  final _repo = OrganizationInvitationRepository();

  // Root cause of the "Pending Invitations appears/disappears/reappears"
  // flicker: both streams below used to be created INLINE inside
  // StreamBuilder's `stream:` argument in build() — a fresh Stream (fresh
  // Firestore query + fresh .map()) on every single rebuild of this page
  // (e.g. _loadIsOrgAdmin's setState, or any snack/dialog-triggered
  // setState). StreamBuilder treats a changed `stream` reference as "the
  // old subscription is gone, go back to ConnectionState.waiting" while
  // still holding the previous data — but this page's builders checked
  // `connectionState == waiting` before checking `hasData`, so the
  // already-loaded list was hidden and a spinner (or, once the fresh
  // subscription's first cache/server pair arrived, a transient
  // empty-list state) rendered in its place, over and over. Hoisting both
  // streams into `late final` fields — created exactly ONCE for the
  // lifetime of this State, never recreated by a rebuild — gives
  // StreamBuilder one stable, long-lived subscription per stream, exactly
  // matching "use stable stream instances" / "do not create duplicate
  // Firestore subscriptions".
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _membersStream =
      FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).collection('members').snapshots();
  late final Stream<List<OrganizationInvitation>> _invitationsStream = _repo.streamInvitations(widget.organizationId);

  /// Spec's invitation-creation restriction: only an authenticated
  /// organization Admin (checked against *this* organization specifically,
  /// via the existing OrgMembershipService — never a second membership
  /// lookup) may invite another account. A Member who somehow reaches this
  /// page (or an unrelated account) sees Staff Members read-only, with no
  /// Add Member action — enforced here at the UI level; see this session's
  /// final report for why this is not yet a server-side security rule.
  bool _isOrgAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadIsOrgAdmin();
  }

  Future<void> _loadIsOrgAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final membership = await OrgMembershipService().getMembership(uid);
    if (mounted) {
      setState(() => _isOrgAdmin =
          membership != null && membership.organizationId == widget.organizationId && membership.role == OrgRole.admin);
    }
  }

  Future<void> _openAddMemberSheet() async {
    if (!_isOrgAdmin) return;
    final emailController = TextEditingController();
    OrgRole role = OrgRole.staff;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invite Staff Member', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              Text('Email', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'name@example.com')),
              const SizedBox(height: 16),
              Text('Role', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Admin'),
                    selected: role == OrgRole.admin,
                    selectedColor: AppColors.yellowrspwn,
                    onSelected: (_) => setSheetState(() => role = OrgRole.admin),
                  ),
                  ChoiceChip(
                    label: const Text('Member'),
                    selected: role == OrgRole.staff,
                    selectedColor: AppColors.yellowrspwn,
                    onSelected: (_) => setSheetState(() => role = OrgRole.staff),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final emailError = AppValidators.email(emailController.text);
                        if (emailError != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(emailError), backgroundColor: Colors.redAccent));
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                        await _submitInvite(emailController.text.trim(), role);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                      child: const Text('Add Member'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      // handled inline above via _submitInvite
    }
  }

  Future<void> _submitInvite(String email, OrgRole role) async {
    if (!_isOrgAdmin) {
      _snack('You do not have permission to add members.', error: true);
      return;
    }
    final normalized = email.trim().toLowerCase();
    final selfEmail = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (selfEmail != null && selfEmail == normalized) {
      _snack('You cannot invite your own email.', error: true);
      return;
    }
    try {
      if (await _repo.isAlreadyActiveMember(organizationId: widget.organizationId, email: email)) {
        _snack('This person is already a member.', error: true);
        return;
      }
      final existing = await _repo.findActiveInvitation(organizationId: widget.organizationId, email: email);
      if (existing != null && !existing.isExpired) {
        _snack('An invitation is already pending.', error: true);
        return;
      }
      if (await _repo.isRoleOccupied(organizationId: widget.organizationId, role: role)) {
        _snack(
          '${role.label == 'Staff' ? 'A Member' : 'An Admin'} account is already assigned to this organization. '
          'Multiple accounts for the same role are not supported yet.',
          error: true,
        );
        return;
      }

      // No `users` lookup gate here on purpose — invitations are addressed
      // by normalized email and remain pending until that person signs up
      // or logs in and matches it at acceptance time (see
      // OrganizationInvitationRepository.acceptInvitation), so someone
      // without an existing account is never incorrectly told their email
      // is invalid or unrecognized.
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
      final orgName = doc.data()?['name'] as String? ?? '';
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _repo.createInvitation(organizationId: widget.organizationId, organizationName: orgName, email: email, role: role, invitedBy: uid);
      _snack('Invitation sent to $email.');
    } catch (e) {
      _snack('Invitation could not be sent: $e', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Colors.redAccent : null));
  }

  Future<void> _editMemberRole(String uid, OrgRole current) async {
    final role = await showDialog<OrgRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.background,
        title: Text('Edit Role', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        children: [
          for (final r in OrgRole.values)
            RadioListTile<OrgRole>(
              value: r,
              groupValue: current,
              title: Text(r == OrgRole.staff ? 'Member' : 'Admin'),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (role == null || role == current) return;
    // Demoting the organization's only Admin away from Admin would leave it
    // with none — same protection _removeMember already has for outright
    // removal, applied here too since a role change can cause the exact
    // same admin-less state.
    if (current == OrgRole.admin && role != OrgRole.admin) {
      if (await _repo.isFinalAdmin(organizationId: widget.organizationId, uid: uid)) {
        _snack('This is the only Admin on this organization and cannot be demoted.', error: true);
        return;
      }
    }
    try {
      await _repo.changeMemberRole(organizationId: widget.organizationId, uid: uid, role: role);
      _snack('Role updated.');
    } catch (e) {
      _snack('Could not update role: $e', error: true);
    }
  }

  Future<void> _removeMember(String uid, bool isSelf) async {
    if (await _repo.isFinalAdmin(organizationId: widget.organizationId, uid: uid)) {
      _snack('This is the only Admin on this organization and cannot be removed.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Remove this member?', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: const Text('They will lose access to this organization. This does not delete their account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE05353), foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.removeMember(organizationId: widget.organizationId, uid: uid);
      _snack('Member removed.');
    } catch (e) {
      _snack('Could not remove member: $e', error: true);
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
          Text('Staff Members', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _membersStream,
            builder: (context, snapshot) {
              // Loading is only the "before the first result ever" state —
              // once any data has arrived, a stale-but-valid list is always
              // preferred over a spinner or an empty state.
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
                    _MemberRow(
                      email: doc.data()['email'] as String? ?? doc.id,
                      role: OrgRole.fromName(doc.data()['role'] as String?),
                      isSelf: doc.id == currentUid,
                      onEditRole: () => _editMemberRole(doc.id, OrgRole.fromName(doc.data()['role'] as String?)),
                      onRemove: () => _removeMember(doc.id, doc.id == currentUid),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Pending Invitations', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          StreamBuilder<List<OrganizationInvitation>>(
            stream: _invitationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError && !snapshot.hasData) {
                return Text('Could not load invitations.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
              }
              // Deduped by normalized email — `createInvitation` now keys new
              // invitations by a deterministic organizationId_normalizedEmail
              // doc id so duplicates can't be newly created, but this is a
              // defensive backstop against any pre-existing legacy duplicate
              // docs. streamInvitations orders by createdAt descending, so
              // `seen.add(...)` (true only the first time) keeps the most
              // recent one.
              final seenEmails = <String>{};
              final invites = (snapshot.data ?? const [])
                  .where((i) => i.status == InvitationStatus.pending)
                  .where((i) => seenEmails.add(i.email.trim().toLowerCase()))
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
                        final role = await showDialog<OrgRole>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            backgroundColor: AppColors.background,
                            title: const Text('Change Role'),
                            children: [
                              for (final r in OrgRole.values)
                                RadioListTile<OrgRole>(
                                  value: r,
                                  groupValue: invite.role,
                                  title: Text(r == OrgRole.staff ? 'Member' : 'Admin'),
                                  onChanged: (v) => Navigator.pop(ctx, v),
                                ),
                            ],
                          ),
                        );
                        if (role != null && role != invite.role) {
                          await _repo.changeInvitationRole(invite.id, role);
                          _snack('Invitation role updated.');
                        }
                      },
                      onRevoke: () async {
                        await _repo.revokeInvitation(invite.id);
                        _snack('Invitation revoked.');
                      },
                      onCopyDevLink: () {
                        Clipboard.setData(ClipboardData(text: invite.id));
                        _snack('Dev-only: invitation ID copied. Real email delivery is not implemented.');
                      },
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
  final String email;
  final OrgRole role;
  final bool isSelf;
  final VoidCallback onEditRole;
  final VoidCallback onRemove;
  const _MemberRow({required this.email, required this.role, required this.isSelf, required this.onEditRole, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email + (isSelf ? ' (You)' : ''), style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(role == OrgRole.staff ? 'Member' : 'Admin', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? onEditRole() : onRemove(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit Role')),
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
  final VoidCallback onCopyDevLink;
  const _InvitationRow({
    required this.invitation,
    required this.onResend,
    required this.onChangeRole,
    required this.onRevoke,
    required this.onCopyDevLink,
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
                    Text(invitation.email, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('Invited as ${invitation.role == OrgRole.staff ? 'Member' : 'Admin'} · Sent $sentLabel',
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
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: onResend, child: const Text('Resend')),
              OutlinedButton(onPressed: onChangeRole, child: const Text('Change Role')),
              OutlinedButton(
                onPressed: onRevoke,
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE05353), side: const BorderSide(color: Color(0xFFE05353))),
                child: const Text('Revoke'),
              ),
              TextButton(onPressed: onCopyDevLink, child: const Text('Copy Dev Link')),
            ],
          ),
        ],
      ),
    );
  }
}
