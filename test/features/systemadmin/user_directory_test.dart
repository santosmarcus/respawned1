import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/features/systemadmin/user_directory.dart';

DirectoryUser user(String uid, {String role = 'general', String org = '', String name = ''}) =>
    DirectoryUser(uid: uid, name: name.isEmpty ? uid : name, role: role, organizationId: org);

void main() {
  group('DirectoryUser.fromMap', () {
    test('prefers first and last name, then name, then email', () {
      expect(DirectoryUser.fromMap('a', {'firstName': 'Ana', 'lastName': 'Cruz', 'name': 'x'}).name, 'Ana Cruz');
      expect(DirectoryUser.fromMap('b', {'name': 'Ben'}).name, 'Ben');
      expect(DirectoryUser.fromMap('c', {'email': 'c@x.ph'}).name, 'c@x.ph');
      expect(DirectoryUser.fromMap('d', const {}).name, 'No name');
    });

    test('reads role, organization, transporter status and join date', () {
      final u = DirectoryUser.fromMap('r', {
        'role': 'pet_transporter',
        'organizationId': 'org1',
        'transporterVerificationStatus': 'pending',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
        'photoUrl': 'not-a-url',
      });
      expect(u.role, 'pet_transporter');
      expect(u.organizationId, 'org1');
      expect(u.transporterStatus, 'pending');
      expect(u.createdAt, DateTime(2026, 11, 1));
      expect(u.photoUrl, isNull);
    });
  });

  test('account types land in their tab', () {
    expect(groupOf(user('a', role: 'pet_transporter')), AccountGroup.transporters);
    expect(groupOf(user('a', role: 'rescue_volunteer')), AccountGroup.volunteers);
    expect(groupOf(user('a', role: 'organization')), AccountGroup.organization);
    expect(groupOf(user('a', role: 'organization_member')), AccountGroup.organization);
    expect(groupOf(user('a', role: 'admin')), AccountGroup.admins);
    expect(groupOf(user('a', role: 'ngo_staff')), AccountGroup.admins);
    expect(groupOf(user('a', role: kSystemAdminRole)), AccountGroup.admins);
    expect(groupOf(user('a', role: 'general')), AccountGroup.general);
    expect(groupOf(user('a', role: '')), AccountGroup.general);
    expect(accountTypeLabelOf(''), 'Sign-up not finished');
    expect(accountTypeLabelOf(kSystemAdminRole), 'System admin');
  });

  test('transporter status labels', () {
    expect(transporterStatusLabel('approved'), 'Verified');
    expect(transporterStatusLabel('pending'), 'Waiting for organization review');
    expect(transporterStatusLabel('rejected'), 'Not approved');
    expect(transporterStatusLabel(''), 'Documents not submitted');
  });

  test('search matches name, email, phone and account type', () {
    const u = DirectoryUser(uid: 'u', name: 'Ana Cruz', email: 'ana@x.ph', phone: '0917', role: 'pet_transporter');
    expect(u.matches(''), isTrue);
    expect(u.matches('cruz'), isTrue);
    expect(u.matches('ANA@'), isTrue);
    expect(u.matches('0917'), isTrue);
    expect(u.matches('transporter'), isTrue);
    expect(u.matches('zzz'), isFalse);
  });

  group('buildOrgRoster', () {
    final users = {
      'owner': user('owner', role: 'admin', org: 'org1', name: 'Owen'),
      'carer': user('carer', role: 'organization_member', org: 'org1', name: 'Cara'),
      'staff': user('staff', role: 'organization_member', org: 'org1', name: 'Sam'),
      'gone': user('gone', role: 'organization_member', org: 'org1', name: 'Gabe'),
      'linked': user('linked', role: 'admin', org: 'org1', name: 'Lin'),
      'other': user('other', role: 'organization_member', org: 'org2'),
    };
    final roster = buildOrgRoster(
      organizationId: 'org1',
      ownerId: 'owner',
      members: {
        'owner': {'role': 'admin'},
        'carer': {'role': 'carer'},
        'staff': {'role': 'staff', 'status': 'active'},
        'gone': {'role': 'staff', 'status': 'removed'},
        'ghost': {'role': 'staff'},
      },
      usersById: users,
    );

    test('owner first, then admins, staff, carers, linked accounts, inactive last', () {
      expect(roster.map((e) => e.uid), ['owner', 'staff', 'ghost', 'carer', 'linked', 'gone']);
    });

    test('labels the role there', () {
      final byUid = {for (final e in roster) e.uid: e};
      expect(byUid['owner']!.roleLabel, 'Owner · Admin');
      expect(byUid['carer']!.role, OrgRole.carer);
      expect(byUid['linked']!.roleLabel, 'Linked account');
      expect(byUid['gone']!.inactive, isTrue);
      // A members doc with no profile is still listed.
      expect(byUid['ghost']!.user, isNull);
    });

    test('leaves out other organizations', () {
      expect(roster.any((e) => e.uid == 'other'), isFalse);
    });
  });

  test('organization accounts with no organization yet', () {
    final list = unlinkedOrganizationAccounts([
      user('b', role: 'organization_member', name: 'Bea'),
      user('a', role: 'organization', name: 'Abe'),
      user('c', role: 'organization_member', org: 'org1'),
      user('d', role: 'general'),
    ]);
    expect(list.map((u) => u.uid), ['a', 'b']);
  });
}
