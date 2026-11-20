import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';

void main() {
  group('presets', () {
    test('one default set without money; anything else is Custom', () {
      expect(OrgPreset.choices, [OrgPreset.staff]);
      expect(OrgPreset.matching({...OrgPreset.staff.permissions}), OrgPreset.staff);
      expect(OrgPreset.matching({...OrgPreset.staff.permissions, OrgPermission.financeView}), OrgPreset.custom);
      expect(OrgPreset.matching({OrgPermission.care}), OrgPreset.custom);
      expect(OrgPreset.matching({}), OrgPreset.custom);
      for (final money in OrgPermission.values.where((p) => p.group == OrgPermissionGroup.money)) {
        expect(OrgPreset.staff.permissions, isNot(contains(money)));
      }
      expect(OrgPreset.staff.permissions, isNot(contains(OrgPermission.facebookPublish)));
    });

    test('staff titles', () {
      expect(staffTitle(OrgPreset.staff), 'Staff');
      expect(staffTitle(null), 'Staff');
      expect(staffTitle(OrgPreset.custom), 'Staff · Custom access');
    });

    test('normalize adds View donations to Manage money', () {
      expect(normalizePermissions({OrgPermission.financeManage}),
          {OrgPermission.financeManage, OrgPermission.financeView});
    });

    test('keys are stored in a fixed order', () {
      expect(permissionKeys({OrgPermission.insights, OrgPermission.rescue}), ['rescue', 'insights']);
    });
  });

  group('staffPermissionsFrom (legacy fallback)', () {
    test('an explicit list wins, unknown keys ignored', () {
      expect(staffPermissionsFrom({'role': 'carer', 'permissions': ['adoptions', 'nope']}), {OrgPermission.adoptions});
    });

    test('former carers, other Staff and no doc get the default set', () {
      expect(staffPermissionsFrom({'role': 'carer'}), OrgPreset.staff.permissions);
      expect(staffPermissionsFrom({'role': 'staff'}), OrgPreset.staff.permissions);
      expect(staffPermissionsFrom(null), OrgPreset.staff.permissions);
    });

    test('the old Facebook flag adds posting', () {
      expect(staffPermissionsFrom({'role': 'staff', 'facebookPublisher': true}), contains(OrgPermission.facebookPublish));
    });
  });

  group('OrgMembership.fromMemberData', () {
    test('Staff with money ticked by hand is Custom', () {
      final m = OrgMembership.fromMemberData('o', {'role': 'staff', 'permissions': ['campaigns', 'financeView', 'financeManage', 'insights']});
      expect(m.role, OrgRole.staff);
      expect(m.preset, OrgPreset.custom);
    });

    test('legacy carer reads as Staff, raw role kept', () {
      final m = OrgMembership.fromMemberData('o', {'role': 'carer', 'status': 'active'});
      expect(m.role, OrgRole.staff);
      expect(m.rawRole, 'carer');
      expect(m.preset, OrgPreset.staff);
    });

    test('Admins have everything and no preset', () {
      final m = OrgMembership.fromMemberData('o', {'role': 'admin'});
      expect(m.permissions, OrgPermission.values.toSet());
      expect(m.preset, isNull);
    });
  });

  test('matches functions/org_permissions.json', () {
    final json = jsonDecode(File('functions/org_permissions.json').readAsStringSync()) as Map<String, dynamic>;
    expect(List<String>.from(json['permissions'] as List), OrgPermission.values.map((p) => p.key).toList());
    final presets = json['presets'] as Map<String, dynamic>;
    expect(presets.keys.toSet(), OrgPreset.choices.map((p) => p.name).toSet());
    for (final p in OrgPreset.choices) {
      expect(Set<String>.from(presets[p.name] as List), p.permissions.map((x) => x.key).toSet(), reason: p.name);
    }
    final legacy = json['legacy'] as Map<String, dynamic>;
    expect(legacy['carer'], OrgPreset.staff.name);
    expect(legacy['staff'], OrgPreset.staff.name);
  });
}
