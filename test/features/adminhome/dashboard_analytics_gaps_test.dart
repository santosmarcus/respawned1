import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/features/adminhome/dashboard/analytics_export.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/case_location.dart';
import 'package:respawnd1/features/care/care_rounds.dart';

void main() {
  group('care roster (Dashboard gap 3)', () {
    const am = CareShift('am', 'Morning', '06:00', '14:00');
    const pm = CareShift('pm', 'Evening', '14:00', '22:00');
    const ana = RosterEntry('u1', 'Ana');

    test('no roster reads as not set, not covered', () {
      expect(CareSetup.defaults.hasRoster, isFalse);
    });

    test('every uncovered shift in the next 7 days is a gap', () {
      final setup = CareSetup(
        areas: CareSetup.defaults.areas,
        tasks: CareSetup.defaults.tasks,
        shifts: const [am, pm],
        roster: {
          for (var w = 1; w <= 7; w++) rosterKey(w, 'am'): const [ana],
          for (var w = 1; w <= 7; w++)
            if (w != 3) rosterKey(w, 'pm'): const [ana],
        },
      );
      final monday = DateTime(2026, 11, 16); // a Monday
      final gaps = rosterGaps(setup, monday);
      expect(gaps, hasLength(1));
      expect(gaps.single.day.weekday, DateTime.wednesday);
      expect(gaps.single.shift.id, 'pm');
    });

    test('setup survives a round trip; a removed task stops counting', () {
      final setup = CareSetup.defaults.copyWith(roster: {rosterKey(1, 'am'): const [ana]});
      final back = CareSetup.fromMap(setup.toMap());
      expect(back.saved, isTrue);
      expect(back.onShift(1, 'am').single.name, 'Ana');
      final round = CareRound.fromMap({
        'done': {
          roundKey('main', 'water'): {'byName': 'Ana'},
          roundKey('main', 'gone'): {'byName': 'Ana'},
        },
      });
      expect(round.doneCount(back), 1);
      expect(back.roundKeys, hasLength(4));
    });

    test('ids are safe in a Firestore field path and unique', () {
      expect(careId('Puppy room #2', const []), 'puppy_room_2');
      expect(careId('Puppy room', const ['puppy_room']), 'puppy_room_2');
      expect(careDayKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('analytics periods (Analytics gap 2)', () {
    final now = DateTime(2026, 11, 17, 10);

    test('a calendar month compares with the previous calendar month', () {
      final p = const AnalyticsRange.month(2026, 10).period(now);
      expect(p.from, DateTime(2026, 10));
      expect(p.to, DateTime(2026, 11));
      expect(p.previous.from, DateTime(2026, 9));
      expect(p.previous.to, DateTime(2026, 10));
    });

    test('the current month and quarter stop at now', () {
      expect(const AnalyticsRange.month(2026, 11).period(now).to, now);
      final q = const AnalyticsRange.quarter(2026, 1).period(now);
      expect(q.from, DateTime(2026));
      expect(q.to, DateTime(2026, 4));
      expect(q.previous.from, DateTime(2025, 10));
      expect(const AnalyticsRange.quarter(2026, 1).previousLabel, 'Q4 2025');
    });

    test('a custom range includes its last day', () {
      final r = AnalyticsRange.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 15));
      final p = r.period(now);
      expect(p.has(DateTime(2026, 10, 15, 23, 59)), isTrue);
      expect(p.has(DateTime(2026, 10, 16)), isFalse);
      expect(p.previous.to, DateTime(2026, 10, 1));
      expect(r.label, 'Oct 1 – Oct 15, 2026');
    });
  });

  group('rescues by location (Analytics gap 4)', () {
    test('barangay and city from a Philippine formatted address', () {
      final p = placeOf('12 Mabini St, San Jose, Rodriguez, 1860 Rizal, Philippines');
      expect(p.city, 'Rodriguez');
      expect(p.barangay, 'San Jose');
    });

    test('an explicit Brgy. part wins; a street is never a barangay', () {
      expect(placeOf('Brgy. Burgos, Rodriguez, Rizal, Philippines').barangay, 'Burgos');
      final street = placeOf('123 Mabini St, Quezon City, Metro Manila, Philippines');
      expect(street.city, 'Quezon City');
      expect(street.barangay, isNull);
    });

    test('too little to tell is left out', () {
      expect(placeOf(null).city, isNull);
      expect(placeOf('Philippines').city, isNull);
      expect(placeOf('').city, isNull);
    });
  });

  group('export (Analytics gap 1)', () {
    test('CSV fields are quoted only when needed', () {
      expect(csvField('plain'), 'plain');
      expect(csvField('a, b'), '"a, b"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField(null), '');
      expect(toCsv(['a', 'b'], [
        [1, 'x,y'],
      ]), 'a,b\n1,"x,y"\n');
    });

    test('PDF text avoids characters the built-in fonts lack', () {
      expect(pdfSafe('₱1,000 – Oct’s “best” …'), 'PHP 1,000 - Oct\'s "best" ...');
    });
  });
}
