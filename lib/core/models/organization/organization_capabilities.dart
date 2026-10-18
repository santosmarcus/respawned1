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
/// operational capabilities; only [canPublishToFacebook] is narrower
/// (Owner/Admin only) since that's the one action with an actual backend
/// authorization boundary. Future role restrictions should be introduced by
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

  /// Facebook Page Publishing Compatibility spec — the one capability that
  /// is NOT equal across roles during this phase. True only for Owner and
  /// active Admin. This is a UX/UI convenience only; it does not by itself
  /// authorize anything server-side (no such callable function exists yet
  /// in this codebase — see PROJECT NOTES).
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
    canPublishToFacebook: false,
  );

  factory OrganizationCapabilities.forRole(ResolvedOrgRole role) {
    final canPublishToFacebook = role == ResolvedOrgRole.owner || role == ResolvedOrgRole.admin;
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
      canPublishToFacebook: canPublishToFacebook,
    );
  }
}

/// Maps a raw stored [OrgRole] (admin/staff) to the display-facing
/// [ResolvedOrgRole] used by [OrganizationCapabilities] — never stored
/// itself, so no Firestore field/enum rename is needed.
ResolvedOrgRole resolvedRoleFromOrgRole(OrgRole role) =>
    role == OrgRole.admin ? ResolvedOrgRole.admin : ResolvedOrgRole.member;
