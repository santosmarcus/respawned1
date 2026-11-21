import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/organization/adoption_promotion_schedule.dart';
import 'package:respawnd1/features/admin/animals/promote_adoptions_page.dart';

void main() {
  group('AdoptionPromotionSchedule', () {
    test('a missing doc, or one only stamped by a post, means no reminders', () {
      expect(AdoptionPromotionSchedule.fromMap(null).isOff, isTrue);
      final stamped = AdoptionPromotionSchedule.fromMap({
        'lastPostedAt': Timestamp.fromDate(DateTime(2026, 11, 20)),
        'lastPostUrl': 'https://www.facebook.com/1_2',
      });
      expect(stamped.isOff, isTrue);
      expect(stamped.lastPostedAt, DateTime(2026, 11, 20));
      expect(stamped.summary, 'No reminders');
    });

    test('reads a saved schedule and ignores out-of-range values', () {
      final s = AdoptionPromotionSchedule.fromMap({
        'enabled': true,
        'smartSuggestions': true,
        'intervalWeeks': 2,
        'dayOfWeek': 3,
        'hour': 18,
        'animalsPerPost': 4,
      });
      expect(s.summary, 'Every 2 weeks on Wednesday at 6:00 PM, plus smart suggestions');
      final bad = AdoptionPromotionSchedule.fromMap({
        'enabled': true,
        'intervalWeeks': 3,
        'dayOfWeek': 9,
        'hour': 30,
        'animalsPerPost': 20,
      });
      expect(bad.intervalWeeks, 1);
      expect(bad.dayOfWeek, DateTime.saturday);
      expect(bad.hour, 10);
      expect(bad.animalsPerPost, 3);
    });

    test('sends only the fields the callable accepts', () {
      final s = AdoptionPromotionSchedule.initial.copyWith(enabled: true, hour: 0);
      expect(s.toCallableMap(), {
        'enabled': true,
        'smartSuggestions': false,
        'intervalWeeks': 1,
        'dayOfWeek': DateTime.saturday,
        'hour': 0,
        'animalsPerPost': 3,
      });
      expect(AdoptionPromotionSchedule.hourLabel(0), '12:00 AM');
      expect(AdoptionPromotionSchedule.hourLabel(12), '12:00 PM');
      expect(AdoptionPromotionSchedule.initial.copyWith(smartSuggestions: true).summary, 'Smart suggestions only');
    });
  });

  group('PromotionCandidate', () {
    test('explains why an animal is suggested', () {
      final c = PromotionCandidate.fromMap({
        'id': 'a',
        'name': 'Bantay',
        'neverShared': false,
        'waiting': true,
        'lastSharedMs': DateTime(2026, 10, 1).millisecondsSinceEpoch,
      });
      expect(c.reason, 'Waiting without applicants');
      expect(c.lastSharedAt, DateTime(2026, 10, 1));
      expect(PromotionCandidate.fromMap({'id': 'b', 'neverShared': true}).reason, 'Never shared');
    });
  });

  test('caption matches the backend wording', () {
    expect(adoptionPostCaption(['Bantay']),
        'Meet Bantay! This animal is ready for a loving home. Message us or apply through the ResPAWnd app to adopt.');
    expect(adoptionPostCaption(['A', ' ', 'B', 'C']), startsWith('Meet A, B and C! They are'));
    expect(adoptionPostCaption([]), 'These animals are looking for a home. Message us to adopt!');
  });

  test('reminder animal ids from push data or a notification doc', () {
    expect(promotionIdsFrom('a, b,,c'), ['a', 'b', 'c']);
    expect(promotionIdsFrom(['a', 1, '']), ['a']);
    expect(promotionIdsFrom(null), isEmpty);
  });
}
