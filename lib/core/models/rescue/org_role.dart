/// A user's role within a single organization, stored at
/// `organizations/{orgId}/members/{uid}.role`. Kept separate from the
/// legacy top-level `users/{uid}.role` (general/admin/ngo_staff/...),
/// which only distinguishes account *types*, not org-level permissions.
enum OrgRole {
  admin,
  staff,
  /// Animal care only: records doses and reads care instructions. Not staff;
  /// firestore.rules and storage.rules keep carers out of case, record and
  /// finance writes.
  carer;

  String get label => switch (this) {
        OrgRole.admin => 'Admin',
        OrgRole.staff => 'Staff',
        OrgRole.carer => 'Carer',
      };

  /// Title shown on member and invitation rows.
  String get memberTitle => switch (this) {
        OrgRole.admin => 'Organization Admin',
        OrgRole.staff => 'Organization Member',
        OrgRole.carer => 'Carer',
      };

  static OrgRole fromName(String? value) =>
      OrgRole.values.firstWhere((e) => e.name == value, orElse: () => OrgRole.staff);

  /// Staff can action day-to-day cases; only Admins can do org-level
  /// destructive/irreversible actions (merging duplicates, referring to
  /// another organization). UI call sites decide per-action which check to
  /// use — this is not itself an authorization decision.
  bool get canManageOrgSettings => this == OrgRole.admin;
}
