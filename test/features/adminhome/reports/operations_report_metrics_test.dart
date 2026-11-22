import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/operations_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

Timestamp _d(int m, int d) => Timestamp.fromDate(DateTime(2026, m, d));
final _nov = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));

void main() {
  test('admissions, readmissions, discharges and length of stay', () {
    final f = shelterFlowIn(_nov, [
      {'createdAt': _d(11, 2)},
      {'createdAt': _d(9, 1), 'adoptedAt': _d(11, 10)},
      {'createdAt': _d(1, 1), 'returnedAt': _d(11, 1), 'adoptedAt': _d(11, 21)},
      {'createdAt': _d(10, 1), 'deceasedAt': _d(11, 5)},
      {'createdAt': _d(10, 1), 'transferStatus': 'pending', 'transferredAt': _d(11, 6)},
      {'createdAt': _d(11, 3), 'isDemo': true},
    ]);
    expect((f.admissions, f.readmissions), (1, 1));
    expect(f.discharges, {'Adopted': 2, 'Died': 1, 'Transferred': 1});
    // 70, 20, 35 and 36 days.
    expect(f.stayDays.median, 35.5);
  });

  test('volunteers: participation and attendance', () {
    final s = volunteerStatsIn(_nov, [
      (startAt: DateTime(2026, 11, 5), isPast: true, registrations: [
        {'uid': 'a', 'attended': true}, {'uid': 'b', 'attended': false}, {'uid': 'c'},
      ]),
      (startAt: DateTime(2026, 10, 5), isPast: true, registrations: [{'uid': 'd', 'attended': true}]),
      (startAt: DateTime(2026, 11, 28), isPast: false, registrations: [{'uid': 'e'}]),
    ]);
    expect((s.registered, s.active, s.eventsHeld, s.signUps), (5, 1, 1, 3));
    expect(s.participation, const Ratio(1, 5));
    expect(s.attendance, const Ratio(1, 2));
  });
}
