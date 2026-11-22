import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/rescue_report_metrics.dart';

final _p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
Timestamp _t(int day, [int hour = 9, int min = 0]) => Timestamp.fromDate(DateTime(2026, 11, day, hour, min));
final _oct = Timestamp.fromDate(DateTime(2026, 10, 20));

void main() {
  group('referral rate', () {
    final cases = <Map<String, dynamic>>[
      {'id': 'a', 'status': 'accepted', 'acceptedAt': _t(2)},
      // An older case: accepted only on the reporter timeline.
      {'id': 'b', 'status': 'ongoing', 'statusHistory': [
        {'status': 'Report submitted.', 'timestamp': _t(3, 8)},
        {'status': 'Rescue case has been accepted.', 'timestamp': _t(3, 9)},
      ]},
      {'id': 'c', 'status': 'referred', 'referral': {'referredAt': _t(4), 'type': 'anotherOrganization', 'referralReason': 'shelterAtCapacity'}},
      {'id': 'd', 'status': 'referred', 'referral': {'referredAt': _t(5), 'type': 'rescueVolunteer'}},
      {'id': 'e', 'status': 'referred', 'linkReferral': {'at': _t(6)}},
      {'id': 'f', 'status': 'rejected', 'rejectionReason': 'noShelterSpace', 'rejectedAt': _t(7)},
      {'id': 'g', 'status': 'accepted', 'acceptedAt': _oct},
      {'id': 'h', 'status': 'community_adoption', 'createdAt': _t(8)},
      {'id': 'i', 'status': 'accepted', 'acceptedAt': _t(9), 'isDemo': true},
    ];

    test('referred out of reports reviewed in the period, each once', () {
      final r = referralStatsIn(_p, cases);
      expect((r.reviewed, r.accepted, r.declined, r.referred), (6, 2, 1, 3));
      expect((r.toOrganization, r.toVolunteer, r.toBarangay), (1, 1, 1));
      expect(r.referralRate, const Ratio(3, 6));
      expect(r.dueToCapacity, 2);
      expect(r.referralRate.small, isTrue);
    });
  });

  group('rescue outcomes', () {
    final cases = <Map<String, dynamic>>[
      // Two puppies, picked up and at the clinic: 2 rescued, 2 treated.
      {'id': 'a', 'status': 'in_treatment', 'acceptedAt': _t(2), 'pickedUpAt': _t(2, 11), 'treatmentAcceptedAt': _t(2, 12), 'animals': [{}, {}]},
      // Discharged into the shelter.
      {'id': 'b', 'status': 'intake', 'acceptedAt': _t(3), 'dateAdmitted': _t(3, 12),
        'animals': [{'dischargedAt': _t(8), 'postTreatmentAction': 'intake', 'intakeCompletedAt': _t(9)}]},
      // Closed without the animal being found: unsuccessful.
      {'id': 'c', 'status': 'cancelled', 'closureReason': 'animalNotPresent', 'acceptedAt': _t(4)},
      // Reunited with the owner: not a failure, not a rescue.
      {'id': 'd', 'status': 'cancelled', 'closureReason': 'reunited', 'acceptedAt': _t(5)},
      // Still waiting for a transporter: left out of the rate.
      {'id': 'e', 'status': 'awaiting_assignment', 'acceptedAt': _t(6)},
      // Accepted last month.
      {'id': 'f', 'status': 'in_treatment', 'acceptedAt': _oct, 'pickedUpAt': _oct},
    ];

    test('success and treatment rates use the right denominators', () {
      final o = rescueOutcomesIn(_p, cases);
      expect(o.acceptedCases, 5);
      expect(o.totalAnimals, 6);
      expect(o.rescuedAnimals, 3);
      expect(o.successRate, const Ratio(3, 4));
      expect(o.treatmentRate, const Ratio(3, 3));
      expect(o.recoveredAnimals, 1);
      expect(o.byOutcome[RescueOutcome.inTreatment], 2);
      expect(o.byOutcome[RescueOutcome.shelter], 1);
      expect(o.byOutcome[RescueOutcome.unsuccessful], 1);
      expect(o.byOutcome[RescueOutcome.reunited], 1);
      expect(o.byOutcome[RescueOutcome.inProgress], 1);
    });
  });

  test('response and completion times', () {
    final cases = <Map<String, dynamic>>[
      {'id': 'a', 'createdAt': _t(2, 8), 'acceptedAt': _t(2, 9), 'treatmentAcceptedAt': _t(2, 14)},
      {'id': 'b', 'createdAt': _t(3, 8), 'acceptedAt': _t(3, 11), 'shelterDeliveredAt': _t(4, 8)},
      {'id': 'c', 'createdAt': _t(4, 8)},
    ];
    final r = responseHoursIn(_p, cases);
    expect((r.average, r.median, r.count), (2.0, 2.0, 2));
    final c = completionHoursIn(_p, cases);
    expect((c.average, c.count), (15.0, 2));
  });

  test('transport completion, utilization, response and cases nobody took', () {
    final offers = <Map<String, dynamic>>[
      {'caseId': 'a', 'riderId': 'r1', 'status': 'completed', 'offeredAt': _t(2, 9), 'acceptedAt': _t(2, 9, 10), 'completedAt': _t(2, 12)},
      {'caseId': 'a', 'riderId': 'r1', 'status': 'completed', 'offeredAt': _t(3, 9), 'acceptedAt': _t(3, 9, 20), 'completedAt': _t(3, 12)},
      {'caseId': 'b', 'riderId': 'r2', 'status': 'cancelled', 'offeredAt': _t(4), 'acceptedAt': _t(4, 9, 5), 'cancelledAt': _t(4, 10)},
      {'caseId': 'c', 'riderId': 'r3', 'status': 'accepted', 'offeredAt': _t(5), 'acceptedAt': _t(5, 9, 30)},
      {'caseId': 'd', 'riderId': 'r4', 'status': 'rejected', 'offeredAt': _t(6, 9), 'respondedAt': _t(6, 9, 2)},
      {'caseId': 'd', 'riderId': 'r5', 'status': 'expired', 'offeredAt': _t(6, 10)},
      {'caseId': 'z', 'riderId': 'demo', 'status': 'completed', 'offeredAt': _t(6), 'acceptedAt': _t(6), 'completedAt': _t(6), 'isDemo': true},
    ];
    final s = transportStatsIn(_p, offers);
    expect(s.completion, const Ratio(2, 3));
    expect((s.activeTransporters, s.tripsCompleted), (1, 2));
    expect(s.utilization(4), const Ratio(1, 4));
    expect((s.offersSent, s.offersAccepted, s.offersDeclined, s.offersExpired), (5, 3, 1, 1));
    // 10, 20, 30 and 2 minutes (the cancelled offer was excluded from "sent").
    expect(s.responseMinutes.median, 15);
    expect(s.casesWithNoTaker, 1);
  });

  test('trend buckets follow the period length', () {
    expect(bucketsOf(Period(DateTime(2026, 11, 1), DateTime(2026, 11, 8))).length, 7);
    // 1 Nov 2026 is a Sunday: weeks starting Oct 26 to Nov 30.
    expect(bucketsOf(Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1))).length, 6);
    expect(bucketsOf(Period(DateTime(2026, 1, 1), DateTime(2027, 1, 1))).length, 12);
    final sums = bucketed<int>(Period(DateTime(2026, 11, 1), DateTime(2026, 11, 4)), [1, 2, 3],
        (i) => DateTime(2026, 11, i), (i) => 10);
    expect(sums.values.toList(), [10, 10, 10]);
  });
}
