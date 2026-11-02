import 'package:respawnd1/core/models/rescue/org_role.dart';

/// The caller's resolved position within an organization for capability
/// purposes — distinct from [OrgRole] (which only stores admin/staff on the
/// membership doc). `owner` is never stored as a role value; it's derived at
/// resolution time from `organizations/{orgId}.ownerId` so a legacy owner
/// with no membership subdoc, or one whose stored role is `admin`, is still
/// recognized correctly (Facebook Publishing Compatibility spec — owner
/// must never be blocked just because the backend/frontend only checks for
/// an explicit `admin` membership).
enum ResolvedOrgRole { owner, admin, member }

/// Temporary Organization Admin/Member Access Model spec — a single
/// centralized place every screen and (eventually) callable function
/// resolves operational access from, instead of scattering
/// `membership.role == OrgRole.admin` checks across widgets and
/// repositories. For the current phase, Owner/Admin/Member get identical
/// operational capabilities; only the Facebook capabilities are narrower
/// since those are the actions with an actual backend authorization
/// boundary (functions/facebook.js). Future role restrictions should be introduced by
/// changing [OrganizationCapabilities.forRole] alone, not by editing every
/// call site again.
class OrganizationCapabilities {
  final bool isActive;
  final ResolvedOrgRole? role;

  final bool canViewDashboard;
  final bool canManageRescues;
  final bool canRejectCases;
  final bool canManageRecords;
  final bool canManageAdoptions;
  final bool canViewAnalytics;
  final bool canViewAudits;
  final bool canManageTeam;

  /// Change member roles, remove members. Owner and active Admin with a
  /// confirmed membership only — firestore.rules denies these writes to
  /// everyone else, so the UI must not offer them.
  final bool canManageMembers;

  /// Connect/reconnect/disconnect the org's Facebook Page and grant or
  /// revoke [canPublishToFacebook] for members. Owner and active Admin only.
  final bool canManageFacebookConnection;

  /// Publish Animal Records to the connected Page. Owner, active Admin, or
  /// a Member granted `facebookPublisher` on their membership doc — that
  /// grant adds nothing else, they keep Member privileges everywhere.
  /// UI convenience only; functions/facebook.js re-checks server-side.
  final bool canPublishToFacebook;

  const OrganizationCapabilities._({
    required this.isActive,
    required this.role,
    required this.canViewDashboard,
    required this.canManageRescues,
    required this.canRejectCases,
    required this.canManageRecords,
    required this.canManageAdoptions,
    required this.canViewAnalytics,
    required this.canViewAudits,
    required this.canManageTeam,
    required this.canManageMembers,
    required this.canManageFacebookConnection,
    required this.canPublishToFacebook,
  });

  /// No active organization relationship — a regular authenticated user, a
  /// pending invitee, or an inactive/removed member. Every capability is
  /// false; this must never gate or affect community/user-side access,
  /// which is resolved entirely independently of this model.
  static const OrganizationCapabilities none = OrganizationCapabilities._(
    isActive: false,
    role: null,
    canViewDashboard: false,
    canManageRescues: false,
    canRejectCases: false,
    canManageRecords: false,
    canManageAdoptions: false,
    canViewAnalytics: false,
    canViewAudits: false,
    canManageTeam: false,
    canManageMembers: false,
    canManageFacebookConnection: false,
    canPublishToFacebook: false,
  );

  /// [facebookPublisher] is the member doc's grant; it only matters for
  /// [ResolvedOrgRole.member] since Owner/Admin can always publish.
  /// [confirmedMembership] false is the fail-open no-membership-doc case:
  /// the app treats it as Admin, but the backend and firestore.rules don't,
  /// so it gets none of the owner/admin-only capabilities.
  factory OrganizationCapabilities.forRole(
    ResolvedOrgRole role, {
    bool facebookPublisher = false,
    bool confirmedMembership = true,
  }) {
    final isOwnerOrAdmin =
        confirmedMembership && (role == ResolvedOrgRole.owner || role == ResolvedOrgRole.admin);
    final canPublishToFacebook = isOwnerOrAdmin || (confirmedMembership && facebookPublisher);
    return OrganizationCapabilities._(
      isActive: true,
      role: role,
      canViewDashboard: true,
      canManageRescues: true,
      canRejectCases: true,
      canManageRecords: true,
      canManageAdoptions: true,
      canViewAnalytics: true,
      canViewAudits: true,
      canManageTeam: true,
      canManageMembers: isOwnerOrAdmin,
      canManageFacebookConnection: isOwnerOrAdmin,
      canPublishToFacebook: canPublishToFacebook,
    );
  }
}

/// Maps a raw stored [OrgRole] (admin/staff) to the display-facing
/// [ResolvedOrgRole] used by [OrganizationCapabilities] — never stored
/// itself, so no Firestore field/enum rename is needed.
ResolvedOrgRole resolvedRoleFromOrgRole(OrgRole role) =>
    role == OrgRole.admin ? ResolvedOrgRole.admin : ResolvedOrgRole.member;
