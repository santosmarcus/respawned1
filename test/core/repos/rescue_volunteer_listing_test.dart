import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';

void main() {
  test('reads an approved rescue volunteer, with defaults for missing limits', () {
    final v = RescueVolunteerListing.fromOrg('o1', {
      'name': ' Ana\'s Cat Rescue ',
      'location': 'Brgy. 1, Quezon City',
      'contactNumber': '0917',
      'activeCaseCount': 1,
      'memberCount': 3,
      'avatarUrl': 'not-a-url',
    });
    expect(v.name, 'Ana\'s Cat Rescue');
    expect(v.phone, '0917');
    expect(v.avatarUrl, isNull);
    expect(v.activeCases, 1);
    expect(v.memberCount, 3);
    expect(v.isAvailable, isTrue);
    expect(v.matches('quezon'), isTrue);
    expect(v.matches('zzz'), isFalse);
  });

  test('paused, at the case limit or full is not available', () {
    expect(RescueVolunteerListing.fromOrg('a', {'acceptingCases': false}).unavailableReason, 'Paused');
    expect(
      RescueVolunteerListing.fromOrg('b', {'activeCaseCount': 2, 'maxActiveCases': 2}).unavailableReason,
      'At case limit',
    );
    expect(
      RescueVolunteerListing.fromOrg('c', {'animalsInCareCount': 5, 'maxAnimalsInCare': 5}).unavailableReason,
      'Full',
    );
    expect(RescueVolunteerListing.fromOrg('d', const {}).name, 'Unnamed rescue volunteer');
  });
}
