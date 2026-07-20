/// A user's role within a single organization, stored at
/// `organizations/{orgId}/members/{uid}.role`. Kept separate from the
/// legacy top-level `users/{uid}.role` (general/admin/ngo_staff/...),
/// which only distinguishes account *types*, not org-level permissions.
enum OrgRole {
  admin,
  staff;

  String get label => switch (this) {
        OrgRole.admin => 'Admin',
        OrgRole.staff => 'Staff',
      };

  static OrgRole fromName(String? value) =>
      OrgRole.values.firstWhere((e) => e.name == value, orElse: () => OrgRole.staff);

  /// Staff can action day-to-day cases; only Admins can do org-level
  /// destructive/irreversible actions (merging duplicates, referring to
  /// another organization). UI call sites decide per-action which check to
  /// use — this is not itself an authorization decision.
  bool get canManageOrgSettings => this == OrgRole.admin;
}
