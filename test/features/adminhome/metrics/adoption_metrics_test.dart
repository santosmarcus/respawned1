import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/adoption_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';

Timestamp _d(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

void main() {
  test('check-ins: due ones answered, on time, and overdue now', () {
    final p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final now = DateTime(2026, 11, 20);
    final followUps = <Map<String, dynamic>>[
      {'scheduledDate': _d(2026, 11, 2), 'status': 'submitted', 'submittedAt': _d(2026, 11, 3)},
      {'scheduledDate': _d(2026, 11, 3), 'status': 'confirmed', 'submittedAt': _d(2026, 11, 19)},
      {'scheduledDate': _d(2026, 11, 4), 'status': 'reminderSent'},
      {'scheduledDate': _d(2026, 11, 5), 'status': 'completed', 'manualCompletionReason': 'Phoned the adopter'},
      {'scheduledDate': _d(2026, 11, 6), 'status': 'cancelled'},
      // Not due yet.
      {'scheduledDate': _d(2026, 11, 25), 'status': 'scheduled'},
      // Overdue from before the period.
      {'scheduledDate': _d(2026, 10, 1), 'status': 'scheduled'},
    ];
    final s = checkInsIn(p, followUps, now);
    expect(s.answered, const Fraction(2, 4));
    expect(s.onTime, const Fraction(1, 2));
    expect(s.overdueNow, 2);
  });

  group('success and returns', () {
    final adoptions = <Map<String, dynamic>>[
      // Window ended, returned inside it.
      {'releasedAt': _d(2026, 3, 1), 'returnRequest': {'status': 'retrieved', 'requestedAt': _d(2026, 4, 1), 'reason': 'Housing Restrictions'}},
      // Window ended, returned after it: still a success.
      {'adoptedAt': _d(2026, 3, 5), 'returnRequest': {'status': 'intake', 'requestedAt': _d(2026, 8, 1), 'reason': 'Behavioral Challenges'}},
      // Window ended, return declined.
      {'releasedAt': _d(2026, 3, 10), 'returnRequest': {'status': 'declined', 'requestedAt': _d(2026, 3, 20), 'reason': 'Other'}},
      // Window ended, never returned.
      {'releasedAt': _d(2026, 4, 1)},
      // Still inside its window: not measured.
      {'releasedAt': _d(2026, 10, 1)},
    ];

    test('only adoptions whose 90-day window ended are measured', () {
      final cohort = adoptionCohortIn(Period(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), adoptions, DateTime(2026, 11, 22));
      expect(cohort.measured, 4);
      expect(cohort.returned, 1);
      expect(cohort.success, const Fraction(3, 4));
    });

    test('reasons of returns that went ahead, with retention support', () {
      final reasons = returnReasonsIn(Period(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), adoptions);
      expect(reasons.map((r) => r.reason), ['Housing Restrictions', 'Behavioral Challenges']);
      expect(reasons.first.support, 'Temporary boarding');
      expect(reasons.last.support, 'Behavioural training');
    });
  });

  test('application funnel', () {
    final p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final apps = <Map<String, dynamic>>[
      {'createdAt': _d(2026, 11, 2), 'status': 'pending'},
      {'createdAt': _d(2026, 11, 3), 'status': 'approved', 'approvedAt': _d(2026, 11, 9)},
      {'createdAt': _d(2026, 11, 4), 'status': 'adopted', 'approvedAt': _d(2026, 11, 9), 'adoptedAt': _d(2026, 11, 15)},
      {'createdAt': _d(2026, 11, 5), 'status': 'rejected'},
      {'createdAt': _d(2026, 10, 5), 'status': 'adopted'},
    ];
    final f = applicationFunnelIn(p, apps);
    expect((f.applied, f.approved, f.adopted), (4, 2, 1));
    expect(f.adoptedShare, const Fraction(1, 2));
  });
}
