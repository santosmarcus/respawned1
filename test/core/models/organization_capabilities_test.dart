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
    test('Staff with money ticked by hand handles money but not members', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: {
        OrgPermission.campaigns,
        OrgPermission.financeManage,
        OrgPermission.insights,
      });
      expect(c.canManageFinances, isTrue);
      expect(c.canViewFinances, isTrue);
      expect(c.canRunCampaigns, isTrue);
      expect(c.canManageRescues, isFalse);
      expect(c.canManageMembers, isFalse);
      expect(c.canManageTeam, isFalse);
      expect(c.preset, OrgPreset.custom);
    });

    test('default Staff: rescues and daily care, no money until ticked', () {
      final c = OrganizationCapabilities.forAccess(ResolvedOrgRole.member, permissions: OrgPreset.staff.permissions);
      expect(c.canViewFinances, isFalse);
      expect(c.canManageFinances, isFalse);
      expect(c.canRunCampaigns, isFalse);
      expect(c.canManageRescues, isTrue);
      expect(c.canGiveCare, isTrue);
      expect(c.canOpenCareTasks, isTrue);
      expect(c.preset, OrgPreset.staff);
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

    test('no members doc: the default Staff set, never Admin', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: null);
      expect(c.isAdmin, isFalse);
      expect(c.preset, OrgPreset.staff);
    });

    test('inactive members get nothing', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'admin', 'status': 'removed'});
      expect(c.isActive, isFalse);
    });

    test('legacy carers were merged into Staff', () {
      final c = capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'carer'});
      expect(c.isCareOnly, isFalse);
      expect(c.canOpenCareTasks, isTrue);
      expect(c.preset, OrgPreset.staff);
    });
  });

  group('which home a member opens', () {
    test('admin shell, care tasks or no access', () {
      expect(orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'admin'})), OrgHome.admin);
      expect(orgHomeFor(capabilitiesFrom(uid: 'u', ownerId: 'o', member: {'role': 'carer'})), OrgHome.admin);
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
