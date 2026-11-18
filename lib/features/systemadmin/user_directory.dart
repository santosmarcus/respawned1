import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';

/// Account role of a system administrator (`users/{uid}.role`). Set in the
/// Firebase console only (firestore.rules never lets a client choose it). It
/// opens the system admin console and nothing else: no case, animal, medical
/// or finance access.
const String kSystemAdminRole = 'system_admin';

/// The tabs of the system admin's user directory. [organization] is built from
/// each organization's members; the others group accounts by type.
enum AccountGroup {
  organization('Organization'),
  transporters('Transporters'),
  volunteers('Volunteers'),
  general('General'),
  admins('Admins');

  const AccountGroup(this.label);
  final String label;
}

/// One `users/{uid}` profile, as the directory shows it.
class DirectoryUser {
  const DirectoryUser({
    required this.uid,
    required this.name,
    this.email = '',
    this.phone = '',
    this.role = '',
    this.organizationId = '',
    this.transporterStatus = '',
    this.createdAt,
    this.photoUrl,
    this.disabled = false,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String organizationId;

  /// `transporterVerificationStatus`: pending / approved / rejected, or ''
  /// before the transporter submits their documents.
  final String transporterStatus;
  final DateTime? createdAt;
  final String? photoUrl;

  /// Suspended by a system admin (adminSetUserDisabled): can't sign in.
  final bool disabled;

  /// Admin accounts are set in the Firebase console; the directory can't
  /// disable or remove them.
  bool get isManagedInConsole => const ['admin', 'ngo_staff', kSystemAdminRole].contains(role);

  factory DirectoryUser.fromMap(String uid, Map<String, dynamic> d) {
    String str(String key) => d[key] is String ? (d[key] as String).trim() : '';
    final full = '${str('firstName')} ${str('lastName')}'.trim();
    final name = full.isNotEmpty ? full : str('name');
    final created = d['createdAt'];
    final photo = str('photoUrl');
    return DirectoryUser(
      uid: uid,
      name: name.isNotEmpty ? name : (str('email').isNotEmpty ? str('email') : 'No name'),
      email: str('email'),
      phone: str('phone'),
      role: str('role'),
      organizationId: str('organizationId'),
      transporterStatus: str('transporterVerificationStatus'),
      createdAt: created is Timestamp ? created.toDate() : null,
      photoUrl: photo.startsWith('http') ? photo : null,
      disabled: d['disabled'] == true,
    );
  }

  factory DirectoryUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DirectoryUser.fromMap(doc.id, doc.data() ?? const {});

  /// What kind of account this is, in words.
  String get accountTypeLabel => accountTypeLabelOf(role);

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q) ||
        phone.contains(q) ||
        accountTypeLabel.toLowerCase().contains(q);
  }
}

String accountTypeLabelOf(String role) => switch (role) {
      'general' => 'General user',
      'pet_transporter' => 'Pet transporter',
      'rescue_volunteer' => 'Rescue volunteer',
      'organization' => 'Organization owner',
      'organization_member' => 'Organization member',
      'admin' => 'Platform admin',
      'ngo_staff' => 'Platform staff',
      kSystemAdminRole => 'System admin',
      '' => 'Sign-up not finished',
      _ => role,
    };

/// Which account-type tab a user is listed under. Organization accounts
/// (owner and member roles) are listed under their organization instead, so
/// they map to [AccountGroup.organization].
AccountGroup groupOf(DirectoryUser u) => switch (u.role) {
      'pet_transporter' => AccountGroup.transporters,
      'rescue_volunteer' => AccountGroup.volunteers,
      'organization' || 'organization_member' => AccountGroup.organization,
      'admin' || 'ngo_staff' || kSystemAdminRole => AccountGroup.admins,
      _ => AccountGroup.general,
    };

/// A transporter's verification state in words. Organization staff approve
/// transporters; the directory only shows where they stand.
String transporterStatusLabel(String status) => switch (status) {
      'approved' => 'Verified',
      'pending' => 'Waiting for organization review',
      'rejected' => 'Rejected',
      _ => 'Documents not submitted',
    };

/// One person on an organization's roster: their profile (null when the
/// profile can't be found) and their role there.
class OrgRosterEntry {
  const OrgRosterEntry({
    required this.uid,
    this.user,
    this.role,
    this.preset,
    this.isOwner = false,
    this.inactive = false,
  });

  final String uid;
  final DirectoryUser? user;

  /// Null for an account linked to the organization with no members doc
  /// (created before membership records existed).
  final OrgRole? role;

  /// A Staff member's preset (or Custom); null for Admins and linked
  /// accounts.
  final OrgPreset? preset;
  final bool isOwner;
  final bool inactive;

  String get roleLabel {
    if (isOwner) return 'Owner · ${OrgRole.admin.label}';
    if (role == OrgRole.staff) return 'Staff · ${preset?.label ?? OrgPreset.fullStaff.label}';
    return role?.memberTitle ?? 'Linked account';
  }
}

/// An organization's roster: its members docs, plus any account whose
/// `organizationId` points at it without a members doc. Owner first, then
/// Admins, Staff, care-only Staff, inactive members last, each by name.
List<OrgRosterEntry> buildOrgRoster({
  required String organizationId,
  required String ownerId,
  required Map<String, Map<String, dynamic>> members,
  required Map<String, DirectoryUser> usersById,
}) {
  final entries = <OrgRosterEntry>[];
  members.forEach((uid, m) {
    final status = m['status'] is String ? m['status'] as String : 'active';
    final role = OrgRole.fromName(m['role'] as String?);
    entries.add(OrgRosterEntry(
      uid: uid,
      user: usersById[uid],
      role: role,
      preset: role == OrgRole.staff ? OrgPreset.matching(staffPermissionsFrom(m)) : null,
      isOwner: uid == ownerId,
      inactive: const ['inactive', 'removed', 'disabled'].contains(status),
    ));
  });
  for (final u in usersById.values) {
    if (u.organizationId != organizationId || members.containsKey(u.uid)) continue;
    entries.add(OrgRosterEntry(uid: u.uid, user: u, isOwner: u.uid == ownerId));
  }
  int rank(OrgRosterEntry e) {
    if (e.inactive) return 9;
    if (e.isOwner) return 0;
    return switch (e.role) {
      OrgRole.admin => 1,
      OrgRole.staff => e.preset == OrgPreset.animalCare ? 3 : 2,
      null => 4,
    };
  }

  entries.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    // A members doc with no profile goes after the named people of its rank.
    if ((a.user == null) != (b.user == null)) return a.user == null ? 1 : -1;
    return (a.user?.name ?? '').toLowerCase().compareTo((b.user?.name ?? '').toLowerCase());
  });
  return entries;
}

/// Organization accounts not on any organization yet: an owner whose draft
/// organization was never created, or a member still waiting for an
/// invitation.
List<DirectoryUser> unlinkedOrganizationAccounts(Iterable<DirectoryUser> users) => users
    .where((u) => groupOf(u) == AccountGroup.organization && u.organizationId.isEmpty)
    .toList()
  ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
