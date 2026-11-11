import 'package:cloud_firestore/cloud_firestore.dart';
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

  test('editable map carries the map pin and cover image', () {
    final e = VolunteerEvent(
      id: 'e1',
      organizationId: 'org1',
      title: 'Clean-up',
      description: '',
      location: 'SM Rosario',
      addressFull: 'Gen. Trias Dr, Rosario, Cavite',
      organizerName: 'Org',
      startAt: DateTime(2026, 3, 21, 9),
      endAt: DateTime(2026, 3, 21, 11),
      lat: 14.41,
      lng: 120.85,
      placeId: 'place-1',
      imageUrl: 'https://example.com/cover.jpg',
    );
    final map = e.toEditableMap();
    expect(map['lat'], 14.41);
    expect(map['lng'], 120.85);
    expect(map['placeId'], 'place-1');
    expect(map['imageUrl'], 'https://example.com/cover.jpg');
    expect(map['location'], 'SM Rosario');
    expect(map['addressFull'], 'Gen. Trias Dr, Rosario, Cavite');
  });

  test('fromMap reads pin and image, and round-trips toEditableMap', () {
    final start = DateTime(2026, 3, 21, 9);
    final e = VolunteerEvent.fromMap('e9', {
      'organizationId': 'org1',
      'title': 'Walk',
      'description': 'd',
      'location': 'Park',
      'addressFull': 'Full address',
      'organizerName': 'Org',
      'startAt': Timestamp.fromDate(start),
      'endAt': Timestamp.fromDate(start.add(const Duration(hours: 2))),
      'lat': 14, // ints from the console still read as doubles
      'lng': 120.5,
      'placeId': 'p1',
      'imageUrl': 'https://example.com/a.jpg',
      'capacity': 20,
      'goingCount': 4,
    });
    expect(e.id, 'e9');
    expect(e.lat, 14.0);
    expect(e.lng, 120.5);
    expect(e.hasPin, isTrue);
    expect(e.placeId, 'p1');
    expect(e.hasImage, isTrue);
    expect(e.goingCount, 4);

    final again = VolunteerEvent.fromMap('e9', {
      ...e.toEditableMap(),
      'organizationId': e.organizationId,
      'goingCount': e.goingCount,
    });
    expect(again.lat, e.lat);
    expect(again.imageUrl, e.imageUrl);
    expect(again.startAt, e.startAt);
    expect(again.capacity, 20);
  });

  test('events saved before the map and image fields still load', () {
    final e = VolunteerEvent.fromMap('old', {
      'organizationId': 'org1',
      'title': 'Legacy',
      'location': 'General Trias, Cavite',
      'addressFull': 'General Trias, Cavite',
      'startAt': Timestamp.fromDate(DateTime(2026, 1, 1, 9)),
      'endAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10)),
      'imageUrl': '',
    });
    expect(e.lat, isNull);
    expect(e.lng, isNull);
    expect(e.placeId, isNull);
    expect(e.hasPin, isFalse);
    expect(e.imageUrl, isNull, reason: 'empty string is treated as no image');
    expect(e.hasImage, isFalse);
    expect(e.status, VolunteerEvent.statusPublished);
    expect(e.description, '');
  });
}
