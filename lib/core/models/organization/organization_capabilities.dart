import 'package:respawnd1/core/models/organization/org_permission.dart';

/// The caller's resolved position within an organization: the owner (from
/// `organizations/{orgId}.ownerId`, never stored as a role), an Admin, or a
/// Staff member.
enum ResolvedOrgRole { owner, admin, member }

/// What the signed-in account may do in its organization — the one place
/// screens read access from. Admins and the owner can do everything; Staff
/// can do what their [permissions] allow (members/{uid}.permissions, or the
/// legacy fallback in [staffPermissionsFrom]). firestore.rules,
/// storage.rules and functions/org_access.js enforce the same thing; this is
/// for deciding what to show.
class OrganizationCapabilities {
  final bool isActive;
  final ResolvedOrgRole? role;

  /// Owner or Admin: everything, including the Admin-only areas (members,
  /// org profile, shelter and care settings, Facebook connection).
  final bool isAdmin;
  final Set<OrgPermission> permissions;

  /// The Staff member's preset, or null for Admins.
  final OrgPreset? preset;

  const OrganizationCapabilities._({
    required this.isActive,
    required this.role,
    required this.isAdmin,
    required this.permissions,
    required this.preset,
  });

  /// No active organization relationship — a regular user, a pending
  /// invitee, or an inactive/removed member.
  static const OrganizationCapabilities none = OrganizationCapabilities._(
    isActive: false,
    role: null,
    isAdmin: false,
    permissions: {},
    preset: null,
  );

  /// [permissions] only matter for Staff ([ResolvedOrgRole.member]); the
  /// owner and Admins get every permission.
  factory OrganizationCapabilities.forAccess(ResolvedOrgRole role, {Set<OrgPermission> permissions = const {}}) {
    final admin = role != ResolvedOrgRole.member;
    final perms = admin ? OrgPermission.values.toSet() : normalizePermissions(permissions);
    return OrganizationCapabilities._(
      isActive: true,
      role: role,
      isAdmin: admin,
      permissions: perms,
      preset: admin ? null : OrgPreset.matching(perms),
    );
  }

  bool has(OrgPermission p) => isActive && permissions.contains(p);

  bool get canViewDashboard => isActive;
  bool get canManageRescues => has(OrgPermission.rescue);
  bool get canRejectCases => has(OrgPermission.rescue);
  bool get canManageRecords => has(OrgPermission.animals);
  bool get canGiveCare => has(OrgPermission.care) || has(OrgPermission.animals);
  bool get canManageAdoptions => has(OrgPermission.adoptions);
  bool get canRunCampaigns => has(OrgPermission.campaigns);
  bool get canViewFinances => has(OrgPermission.financeView) || has(OrgPermission.financeManage);
  bool get canManageFinances => has(OrgPermission.financeManage);
  bool get canManageVolunteers => has(OrgPermission.volunteers);
  bool get canViewAnalytics => has(OrgPermission.insights);
  bool get canViewAudits => has(OrgPermission.insights);

  /// Invite, edit and remove members; org profile; shelter and care
  /// settings. Admin only.
  bool get canManageTeam => isActive && isAdmin;
  bool get canManageMembers => isActive && isAdmin;
  bool get canManageOrgSettings => isActive && isAdmin;
  bool get canManageFacebookConnection => isActive && isAdmin;
  bool get canPublishToFacebook => has(OrgPermission.facebookPublish);

  /// Staff whose only permission is daily care: they get the care-tasks
  /// screen instead of the admin shell.
  bool get isCareOnly =>
      isActive && !isAdmin && permissions.length == 1 && permissions.contains(OrgPermission.care);

  /// Staff an Admin gave no permissions at all.
  bool get hasNoAccess => isActive && !isAdmin && permissions.isEmpty;
}

/// Capabilities from an organization's owner id and the account's members
/// doc (null when it has none). Pure, shared by the service and tests:
/// owner → Admin; no members doc (a legacy linked account) → Full staff;
/// inactive → none; role 'admin' → Admin; anything else → Staff with
/// [staffPermissionsFrom].
OrganizationCapabilities capabilitiesFrom({
  required String uid,
  required String? ownerId,
  required Map<String, dynamic>? member,
}) {
  if (ownerId != null && ownerId == uid) return OrganizationCapabilities.forAccess(ResolvedOrgRole.owner);
  if (member == null) {
    return OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: staffPermissionsFrom(null));
  }
  final status = member['status'] as String?;
  if (const {'inactive', 'removed', 'disabled'}.contains(status)) return OrganizationCapabilities.none;
  if (member['role'] == 'admin') return OrganizationCapabilities.forAccess(ResolvedOrgRole.admin);
  return OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: staffPermissionsFrom(member));
}

/// Which home an approved organization's member opens (lib/main.dart).
enum OrgHome {
  /// The admin shell (dashboard and modules).
  admin,

  /// The care-tasks screen: Staff whose only permission is daily care.
  care,

  /// Staff an Admin gave no permissions, or an inactive member.
  noAccess,
}

OrgHome orgHomeFor(OrganizationCapabilities c) {
  if (!c.isActive || c.hasNoAccess) return OrgHome.noAccess;
  if (c.isCareOnly) return OrgHome.care;
  return OrgHome.admin;
}
