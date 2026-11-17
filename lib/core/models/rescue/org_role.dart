/// A user's role within a single organization, stored at
/// `organizations/{orgId}/members/{uid}.role`. Kept separate from the
/// top-level `users/{uid}.role` account type (general/admin/ngo_staff/...).
///
/// Admins can do everything; Staff do what their permissions allow
/// (lib/core/models/organization/org_permission.dart). Members docs written
/// before permissions existed may still say 'carer'; that reads as Staff with
/// the Animal care preset (staffPermissionsFrom).
enum OrgRole {
  admin,
  staff;

  String get label => switch (this) {
        OrgRole.admin => 'Admin',
        OrgRole.staff => 'Staff',
      };

  /// Title shown on member and invitation rows.
  String get memberTitle => switch (this) {
        OrgRole.admin => 'Organization Admin',
        OrgRole.staff => 'Staff',
      };

  /// Unknown, missing and legacy 'carer' values read as [staff].
  static OrgRole fromName(String? value) => value == 'admin' ? OrgRole.admin : OrgRole.staff;
}
