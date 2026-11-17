import 'package:cloud_functions/cloud_functions.dart';

import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';

/// Changes what an organization member can do: Admin, or Staff with a set
/// of permissions. Goes through the setMemberAccess callable
/// (functions/org_members.js), the only writer of a member's role,
/// permissions and preset: it checks the caller is an Admin, keeps the owner
/// an Admin and at least one active Admin, and writes the audit entry.
class OrgMemberAccessRepository {
  OrgMemberAccessRepository({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> setAccess({
    required String organizationId,
    required String memberUid,
    required OrgRole role,
    Set<OrgPermission> permissions = const {},
  }) async {
    await _functions.httpsCallable('setMemberAccess').call<Object?>({
      'organizationId': organizationId,
      'memberUid': memberUid,
      'role': role.name,
      if (role == OrgRole.staff) 'permissions': permissionKeys(normalizePermissions(permissions)),
    });
  }

  /// The callable's message for a refusal (last Admin, owner, not an
  /// Admin), or a generic one.
  static String errorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      return switch (e.code) {
        'failed-precondition' || 'permission-denied' || 'invalid-argument' => e.message ?? 'This change was refused.',
        'unavailable' || 'deadline-exceeded' => 'No connection. Try again.',
        _ => 'Could not save the change.',
      };
    }
    return 'Could not save the change.';
  }
}
