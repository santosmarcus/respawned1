import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';

VolunteerEvent _event({
  DateTime? startAt,
  DateTime? endAt,
  int? capacity,
  int goingCount = 0,
  String status = VolunteerEvent.statusPublished,
}) {
  final start = startAt ?? DateTime.now().add(const Duration(days: 1));
  return VolunteerEvent(
    id: 'e1',
    organizationId: 'org1',
    title: 'Stray Dog Walking',
    description: '',
    location: 'General Trias, Cavite',
    addressFull: 'General Trias, Cavite',
    organizerName: 'Loved by the Gapz',
    startAt: start,
    endAt: endAt ?? start.add(const Duration(hours: 2)),
    capacity: capacity,
    goingCount: goingCount,
    status: status,
  );
}

void main() {
  test('formats date and time range for display', () {
    final e = _event(startAt: DateTime(2026, 3, 21, 9), endAt: DateTime(2026, 3, 21, 10, 30));
    expect(e.date, 'Saturday, March 21, 2026');
    // intl separates the AM/PM marker with a narrow no-break space.
    expect(e.time.replaceAll(' ', ' '), '9:00 AM - 10:30 AM');
  });

  test('upcoming published event with room is open', () {
    expect(_event(capacity: 10, goingCount: 3).isOpen, isTrue);
    expect(_event().isOpen, isTrue, reason: 'no capacity means no limit');
  });

  test('full, cancelled, and past events are not open', () {
    expect(_event(capacity: 2, goingCount: 2).isFull, isTrue);
    expect(_event(capacity: 2, goingCount: 2).isOpen, isFalse);
    expect(_event(status: VolunteerEvent.statusCancelled).isOpen, isFalse);
    final past = _event(startAt: DateTime.now().subtract(const Duration(days: 2)));
    expect(past.isPast, isTrue);
    expect(past.isOpen, isFalse);
  });

  test('editable map leaves status and goingCount to the repository', () {
    final map = _event(capacity: 5, goingCount: 3).toEditableMap();
    expect(map.containsKey('status'), isFalse);
    expect(map.containsKey('goingCount'), isFalse);
    expect(map['capacity'], 5);
  });
}
