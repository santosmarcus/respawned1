import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/facebook/record_post_text.dart';
import 'package:respawnd1/features/donation/models.dart';

DonationListing _campaign({String type = 'donation', String status = 'active', double? monthly}) => DonationListing(
      id: 'c1',
      title: 'Surgery for Bantay',
      target: 20000,
      collected: 5000,
      organizer: 'Paws Shelter',
      endDate: DateTime(2026, 12, 31),
      time: '',
      description: 'Bantay needs leg surgery.',
      numdonated: 3,
      address: '',
      type: type,
      animalName: 'Bantay',
      status: status,
      monthlyAmount: monthly,
    );

VolunteerEvent _event({int? capacity, int going = 0, DateTime? start}) {
  final s = start ?? DateTime(2030, 1, 5, 9);
  return VolunteerEvent(
    id: 'e1',
    organizationId: 'org1',
    title: 'Shelter clean-up',
    description: 'Bring gloves.',
    location: 'Imus, Cavite',
    addressFull: '12 Main St, Imus, Cavite',
    organizerName: 'Paws Shelter',
    startAt: s,
    endAt: s.add(const Duration(hours: 3)),
    capacity: capacity,
    goingCount: going,
  );
}

void main() {
  test('donation campaign post shows progress, deadline and a call to give', () {
    final text = composeCampaignPost(_campaign(), now: DateTime(2026, 11, 20));
    expect(text, startsWith('💛 Surgery for Bantay'));
    expect(text, contains('Bantay needs leg surgery.'));
    expect(text, contains('₱5,000 raised of ₱20,000 (25%)'));
    expect(text, contains('Until December 31, 2026'));
    expect(text, contains('Organized by Paws Shelter'));
    expect(text, contains('Donate'));
  });

  test('sponsorship post names the animal and the monthly amount', () {
    final text = composeCampaignPost(_campaign(type: 'sponsorship', monthly: 500), now: DateTime(2026, 11, 20));
    expect(text, startsWith('💛 Sponsor Bantay'));
    expect(text, contains('₱500 a month'));
    expect(text, isNot(contains('raised of')));
  });

  test('a finished campaign thanks donors instead of asking', () {
    final text = composeCampaignPost(_campaign(status: 'goal_met'), now: DateTime(2026, 11, 20));
    expect(text, contains('Goal reached'));
    expect(text, contains('See where the funds went'));
  });

  test('event post has when, where, spots and how to join', () {
    final text = composeEventPost(_event(capacity: 20, going: 5));
    expect(text, startsWith('📣 Shelter clean-up'));
    expect(text, contains('📍 12 Main St, Imus, Cavite'));
    expect(text, contains('15 of 20 spots left'));
    expect(text, contains('Bring gloves.'));
    expect(text, contains('Home → Events'));
  });

  test('full and past events say so', () {
    expect(composeEventPost(_event(capacity: 10, going: 10)), contains('All 10 spots are taken'));
    expect(composeEventPost(_event(start: DateTime(2020, 1, 1))), contains('Thank you to everyone who came'));
  });
}
