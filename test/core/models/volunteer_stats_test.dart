import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_stats.dart';

void main() {
  group('VolunteerStats.fromUserData', () {
    test('is null without stats', () {
      expect(VolunteerStats.fromUserData(null), isNull);
      expect(VolunteerStats.fromUserData({'name': 'Ana'}), isNull);
      expect(VolunteerStats.fromUserData({'volunteerStats': 'bad'}), isNull);
    });

    test('parses counts and keeps badges in tier order, skipping unknown ids', () {
      final s = VolunteerStats.fromUserData({
        'volunteerStats': {
          'attendedCount': 6,
          'organizationCount': 3,
          'badges': ['community_helper', 'helping_paw', 'made_up', 'first_event'],
        },
      })!;
      expect(s.attendedCount, 6);
      expect(s.organizationCount, 3);
      expect(s.badges, [VolunteerBadge.firstEvent, VolunteerBadge.helpingPaw, VolunteerBadge.communityHelper]);
    });
  });

  group('next badge', () {
    VolunteerStats withCount(int n) =>
        VolunteerStats(attendedCount: n, organizationCount: 1, badges: const []);

    test('counts down to the next attendance tier', () {
      expect(withCount(0).nextEventBadge, VolunteerBadge.firstEvent);
      expect(withCount(1).nextEventBadge, VolunteerBadge.helpingPaw);
      expect(withCount(1).eventsToNextBadge, 4);
      expect(withCount(9).nextEventBadge, VolunteerBadge.regular);
      expect(withCount(9).eventsToNextBadge, 1);
      expect(withCount(10).nextEventBadge, VolunteerBadge.champion);
    });

    test('is null once every tier is earned', () {
      expect(withCount(25).nextEventBadge, isNull);
      expect(withCount(40).eventsToNextBadge, 0);
    });
  });
}
