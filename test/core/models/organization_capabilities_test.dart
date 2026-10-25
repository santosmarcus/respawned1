import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/core/models/organization/organization_capabilities.dart';

void main() {
  group('Facebook capabilities', () {
    test('owner and admin can manage the connection and publish', () {
      for (final role in [ResolvedOrgRole.owner, ResolvedOrgRole.admin]) {
        final c = OrganizationCapabilities.forRole(role);
        expect(c.canManageFacebookConnection, isTrue, reason: '$role');
        expect(c.canPublishToFacebook, isTrue, reason: '$role');
      }
    });

    test('member without the grant can do neither', () {
      final c = OrganizationCapabilities.forRole(ResolvedOrgRole.member);
      expect(c.canManageFacebookConnection, isFalse);
      expect(c.canPublishToFacebook, isFalse);
    });

    test('member with the grant can publish but not manage the connection', () {
      final c = OrganizationCapabilities.forRole(ResolvedOrgRole.member, facebookPublisher: true);
      expect(c.canPublishToFacebook, isTrue);
      expect(c.canManageFacebookConnection, isFalse);
      // The grant leaves every other capability at Member level.
      final plain = OrganizationCapabilities.forRole(ResolvedOrgRole.member);
      expect(c.canManageTeam, plain.canManageTeam);
      expect(c.canViewAudits, plain.canViewAudits);
    });

    test('unconfirmed membership withholds owner/admin-only actions', () {
      final c = OrganizationCapabilities.forRole(ResolvedOrgRole.admin, confirmedMembership: false);
      expect(c.canManageFacebookConnection, isFalse);
      expect(c.canPublishToFacebook, isFalse);
      expect(c.canManageMembers, isFalse);
      expect(c.canManageTeam, isTrue);
    });

    test('none has no Facebook access', () {
      expect(OrganizationCapabilities.none.canManageFacebookConnection, isFalse);
      expect(OrganizationCapabilities.none.canPublishToFacebook, isFalse);
    });
  });

  group('canManageMembers', () {
    test('owner and admin can manage members', () {
      expect(OrganizationCapabilities.forRole(ResolvedOrgRole.owner).canManageMembers, isTrue);
      expect(OrganizationCapabilities.forRole(ResolvedOrgRole.admin).canManageMembers, isTrue);
    });

    test('members cannot, even with the Facebook grant', () {
      expect(OrganizationCapabilities.forRole(ResolvedOrgRole.member).canManageMembers, isFalse);
      expect(
        OrganizationCapabilities.forRole(ResolvedOrgRole.member, facebookPublisher: true).canManageMembers,
        isFalse,
      );
      expect(OrganizationCapabilities.none.canManageMembers, isFalse);
    });
  });
}
