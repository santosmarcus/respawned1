import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/organization/organization_capabilities.dart';

void main() {
  group('Admins and the owner', () {
    test('have every permission and the Admin-only areas', () {
      for (final role in [ResolvedOrgRole.owner, ResolvedOrgRole.admin]) {
        final c = OrganizationCapabilities.forAccess(role);
        expect(c.isAdmin, isTrue);
        expect(c.permissions, OrgPermission.values.toSet());
        expect(c.canManageMembers, isTrue);
        expect(c.canManageOrgSettings, isTrue);
        expect(c.canManageFacebookConnection, isTrue);
        expect(c.canManageFinances, isTrue);
        expect(c.preset, isNull);
      }
    });
  });

  group('Staff', () {
    test('a Treasurer handles money but not rescues or members', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: OrgPreset.treasurer.permissions);
      expect(c.canManageFinances, isTrue);
      expect(c.canViewFinances, isTrue);
      expect(c.canRunCampaigns, isTrue);
      expect(c.canManageRescues, isFalse);
      expect(c.canManageMembers, isFalse);
      expect(c.canManageTeam, isFalse);
      expect(c.preset, OrgPreset.treasurer);
    });

    test('Full staff sees money but cannot manage it', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: OrgPreset.fullStaff.permissions);
      expect(c.canViewFinances, isTrue);
      expect(c.canManageFinances, isFalse);
      expect(c.canManageRescues, isTrue);
      expect(c.canPublishToFacebook, isFalse);
      expect(c.isCareOnly, isFalse);
    });

    test('Manage money always includes viewing it', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: {OrgPermission.financeManage});
      expect(c.has(OrgPermission.financeView), isTrue);
    });

    test('Facebook posting is its own permission', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: {OrgPermission.facebookPublish});
      expect(c.canPublishToFacebook, isTrue);
      expect(c.canManageFacebookConnection, isFalse);
    });
  });

  test('none has nothing', () {
    expect(OrganizationCapabilities.none.has(OrgPermission.care), isFalse);
    expect(OrganizationCapabilities.none.canManageMembers, isFalse);
    expect(OrganizationCapabilities.none.canViewDashboard, isFalse);
  });

  group('capabilitiesFrom (members doc)', () {
    test('owner is an Admin even with a Staff doc', () {
      final c = capabilitiesFrom(uid: 'o', ownerId: 'o', member: {'role': 'staff', 'permissions': <String>[]});
      expect(c.isAdmin, isTrue);
    });

    test('no members doc: Full staff, never Admin', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: null);
      expect(c.isAdmin, isFalse);
      expect(c.preset, OrgPreset.fullStaff);
    });

    test('inactive members get nothing', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'admin', 'status': 'removed'});
      expect(c.isActive, isFalse);
    });

    test('legacy carers are Animal care', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'carer'});
      expect(c.isCareOnly, isTrue);
      expect(c.preset, OrgPreset.animalCare);
    });
  });

  group('which home a member opens', () {
    test('admin shell, care tasks or no access', () {
      expect(orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'admin'})), OrgHome.admin);
      expect(orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'carer'})), OrgHome.care);
      expect(
        orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'staff', 'permissions': ['care']})),
        OrgHome.care,
      );
      expect(
        orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'staff', 'permissions': <String>[]})),
        OrgHome.noAccess,
      );
      expect(orgHomeFor(OrganizationCapabilities.none), OrgHome.noAccess);
      // Care plus anything else is the admin shell.
      expect(
        orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'staff', 'permissions': ['care', 'adoptions']})),
        OrgHome.admin,
      );
    });
  });
}
