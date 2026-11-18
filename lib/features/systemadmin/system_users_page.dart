import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/features/systemadmin/user_directory.dart';

/// The system admin's read-only directory of every account: each
/// organization's people with their role there, and the other account types
/// (transporters, volunteers, general users, admins). Nothing here changes an
/// account; organization admins manage their own members, and organization
/// staff verify transporters.
class SystemUsersPage extends StatefulWidget {
  const SystemUsersPage({super.key, this.menuActions = const [], this.firestore});

  final List<AdminMenuAction> menuActions;
  final FirebaseFirestore? firestore;

  @override
  State<SystemUsersPage> createState() => _SystemUsersPageState();
}

class _SystemUsersPageState extends State<SystemUsersPage> {
  late final FirebaseFirestore _db = widget.firestore ?? FirebaseFirestore.instance;
  late final Stream<List<DirectoryUser>> _users = _db
      .collection('users')
      .snapshots()
      .map((s) => s.docs.map(DirectoryUser.fromFirestore).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _orgs = _db.collection('organizations').snapshots();

  final _search = TextEditingController();
  String _query = '';
  int _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DirectoryUser>>(
      stream: _users,
      builder: (context, snap) {
        final users = snap.data ?? const <DirectoryUser>[];
        int count(AccountGroup g) => users.where((u) => groupOf(u) == g).length;
        final group = AccountGroup.values[_tab];
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AdminAppBar(
            title: 'Users',
            showLeading: false,
            menuActions: widget.menuActions,
            bottom: AdminTabBar(
              tabs: [
                for (final g in AccountGroup.values)
                  AdminTab(g.label, count: snap.hasData && g != AccountGroup.organization ? count(g) : null),
              ],
              selectedIndex: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
          ),
          body: Column(
            children: [
              AdminSearchBar(
                controller: _search,
                hintText: 'Search name, email or phone…',
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              Expanded(
                child: AdminTabSwipe(
                  index: _tab,
                  count: AccountGroup.values.length,
                  onSelected: (i) => setState(() => _tab = i),
                  child: snap.hasError
                      ? const AdminListMessage('Could not load users.')
                      : !snap.hasData
                          ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
                          : group == AccountGroup.organization
                              ? _organizationsView(users)
                              : _groupView(users, group),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _groupView(List<DirectoryUser> users, AccountGroup group) {
    final list = users.where((u) => groupOf(u) == group && u.matches(_query)).toList();
    final note = switch (group) {
      AccountGroup.transporters => 'Organization staff verify transporters from their Transporters screen.',
      AccountGroup.admins =>
        'Platform admins run the organization tools. System admins only see this console. Both are set in the Firebase console.',
      _ => null,
    };
    if (list.isEmpty && note == null) {
      return AdminListMessage(_query.isEmpty ? 'No ${group.label.toLowerCase()} accounts.' : 'No accounts match your search.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (note != null) _Note(note),
        if (list.isEmpty)
          AdminListMessage(_query.isEmpty ? 'No ${group.label.toLowerCase()} accounts.' : 'No accounts match your search.'),
        for (final u in list)
          _UserTile(
            user: u,
            trailing: group == AccountGroup.transporters ? _transporterChip(u.transporterStatus) : null,
          ),
      ],
    );
  }

  Widget _organizationsView(List<DirectoryUser> users) {
    final byId = {for (final u in users) u.uid: u};
    final unlinked = unlinkedOrganizationAccounts(users).where((u) => u.matches(_query)).toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _orgs,
      builder: (context, snap) {
        if (snap.hasError) return const AdminListMessage('Could not load organizations.');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
        final orgs = snap.data!.docs.toList()
          ..sort((a, b) => ((a.data()['name'] as String?) ?? '').compareTo((b.data()['name'] as String?) ?? ''));
        if (orgs.isEmpty && unlinked.isEmpty) return const AdminListMessage('No organizations yet.');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final org in orgs)
              _OrganizationSection(db: _db, org: org, usersById: byId, query: _query),
            if (unlinked.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SectionTitle('Not on an organization yet', subtitle: '${unlinked.length}'),
              for (final u in unlinked) _UserTile(user: u),
            ],
          ],
        );
      },
    );
  }
}

Widget _transporterChip(String status) {
  final (label, color) = switch (status) {
    'approved' => ('Verified', AppColors.success),
    'pending' => ('Pending', AppColors.warning),
    'rejected' => ('Rejected', AppColors.error),
    _ => ('No documents', AppColors.textSecondary),
  };
  return _Chip(label, color);
}

/// One organization: its status and roster (members docs live in a
/// subcollection, so each section listens to its own).
class _OrganizationSection extends StatelessWidget {
  const _OrganizationSection({required this.db, required this.org, required this.usersById, required this.query});

  final FirebaseFirestore db;
  final QueryDocumentSnapshot<Map<String, dynamic>> org;
  final Map<String, DirectoryUser> usersById;
  final String query;

  @override
  Widget build(BuildContext context) {
    final d = org.data();
    final name = (d['name'] as String?)?.trim();
    // No verificationStatus = approved (bootstrapped or created before
    // verification existed), the same default firestore.rules uses.
    final status = d['verificationStatus'] == null
        ? OrgVerificationStatus.approved
        : OrgVerificationStatus.fromName(d['verificationStatus'] as String?);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('organizations').doc(org.id).collection('members').snapshots(),
      builder: (context, snap) {
        final members = <String, Map<String, dynamic>>{
          for (final m in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) m.id: m.data(),
        };
        final roster = buildOrgRoster(
          organizationId: org.id,
          ownerId: (d['ownerId'] as String?) ?? '',
          members: members,
          usersById: usersById,
        ).where((e) => query.isEmpty || (e.user?.matches(query) ?? false)).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(
                name == null || name.isEmpty ? 'Unnamed organization' : name,
                subtitle: snap.hasData ? '${roster.length} ${roster.length == 1 ? 'person' : 'people'}' : null,
                trailing: _orgStatusChip(status),
              ),
              if (snap.hasError) const _Note('Could not load this organization\'s members.'),
              if (snap.hasData && roster.isEmpty)
                _Note(query.isEmpty ? 'No members yet.' : 'No members match your search.'),
              for (final e in roster)
                e.user == null
                    ? _MissingProfileTile(uid: e.uid, roleLabel: e.roleLabel)
                    : _UserTile(
                        user: e.user!,
                        subtitleOverride: e.roleLabel,
                        trailing: e.inactive ? const _Chip('Inactive', AppColors.textSecondary) : null,
                        orgRoleLabel: e.roleLabel,
                        orgName: name,
                      ),
            ],
          ),
        );
      },
    );
  }
}

Widget _orgStatusChip(OrgVerificationStatus s) => switch (s) {
      OrgVerificationStatus.approved => const _Chip('Approved', AppColors.success),
      OrgVerificationStatus.pending => const _Chip('Under review', AppColors.warning),
      OrgVerificationStatus.requiresChanges => const _Chip('Needs changes', AppColors.warning),
      OrgVerificationStatus.rejected => const _Chip('Rejected', AppColors.error),
      OrgVerificationStatus.draft => const _Chip('Not submitted', AppColors.textSecondary),
    };

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                if (subtitle != null)
                  Text(subtitle!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, this.trailing, this.subtitleOverride, this.orgRoleLabel, this.orgName});

  final DirectoryUser user;
  final Widget? trailing;

  /// Shown instead of the email (an organization roster shows the role).
  final String? subtitleOverride;
  final String? orgRoleLabel;
  final String? orgName;

  @override
  Widget build(BuildContext context) {
    final contact = user.email.isNotEmpty ? user.email : user.phone;
    return Card(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.slaterspwn),
      ),
      child: ListTile(
        leading: _Avatar(user: user),
        title: Text(user.name, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        subtitle: Text(
          subtitleOverride ?? (contact.isEmpty ? user.accountTypeLabel : contact),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        trailing: trailing,
        onTap: () => _showUserDetails(context, user, orgRoleLabel: orgRoleLabel, orgName: orgName),
      ),
    );
  }
}

class _MissingProfileTile extends StatelessWidget {
  const _MissingProfileTile({required this.uid, required this.roleLabel});

  final String uid;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.slaterspwn),
      ),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: AppColors.slaterspwn, child: Icon(Icons.person_off_outlined)),
        title: Text('Profile not found', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
        subtitle: Text('$roleLabel · $uid', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, this.radius = 20});

  final DirectoryUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isNotEmpty ? user.name.characters.first.toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.tearspwn,
      foregroundImage: user.photoUrl == null ? null : NetworkImage(user.photoUrl!),
      child: Text(initial, style: GoogleFonts.tiltWarp(color: AppColors.textPrimary, fontSize: radius * 0.8)),
    );
  }
}

Future<void> _showUserDetails(BuildContext context, DirectoryUser u, {String? orgRoleLabel, String? orgName}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      final rows = <(String, String)>[
        ('Account type', u.accountTypeLabel),
        if (orgName != null) ('Organization', orgName),
        if (orgRoleLabel != null) ('Role there', orgRoleLabel),
        if (u.role == 'pet_transporter') ('Transporter status', transporterStatusLabel(u.transporterStatus)),
        ('Email', u.email.isEmpty ? 'Not given' : u.email),
        ('Phone', u.phone.isEmpty ? 'Not given' : u.phone),
        ('Joined', formatDateOr(u.createdAt, 'Unknown')),
      ];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Avatar(user: u, radius: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(u.name, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: Text(value,
                            style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: u.uid));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(appSnackBar('User ID copied.', kind: AppMessageKind.success));
                  }
                },
                icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
                label: Text('Copy user ID', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
