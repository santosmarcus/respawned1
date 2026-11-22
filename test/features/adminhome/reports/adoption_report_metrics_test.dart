import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/adoption_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

Timestamp _d(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));
final _nov = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));

void main() {
  test('intake to adoption uses the last return when an animal came back', () {
    final animals = <Map<String, dynamic>>[
      {'id': 'a', 'createdAt': _d(2026, 10, 2), 'adoptedAt': _d(2026, 11, 1)},
      {'id': 'b', 'createdAt': _d(2026, 1, 1), 'returnedAt': _d(2026, 11, 1), 'adoptedAt': _d(2026, 11, 11)},
      {'id': 'c', 'createdAt': _d(2026, 9, 1), 'adoptedAt': _d(2026, 10, 1)},
    ];
    final s = intakeToAdoptionDaysIn(_nov, animals);
    expect((s.count, s.average, s.median), (2, 20.0, 20.0));
  });

  test('adoption rate counts only animals available in the period', () {
    final animals = <Map<String, dynamic>>[
      {'id': 'a', 'readyForAdoptionAt': _d(2026, 10, 1), 'adoptedAt': _d(2026, 11, 5), 'adoptionStatus': 'adopted'},
      {'id': 'b', 'readyForAdoptionAt': _d(2026, 11, 10), 'adoptionStatus': 'adoptable'},
      {'id': 'c', 'adoptionStatus': 'reserved'},
      {'id': 'd', 'readyForAdoptionAt': _d(2026, 9, 1), 'adoptedAt': _d(2026, 10, 1), 'adoptionStatus': 'adopted'},
      {'id': 'e', 'adoptionStatus': 'not_ready'},
      {'id': 'f', 'readyForAdoptionAt': _d(2026, 12, 5), 'adoptionStatus': 'adoptable'},
    ];
    // f is listed now (after the period) but still counts as listed: its
    // status is adoptable today. Listed-now animals are included because
    // older records have no ready date.
    expect(adoptionRateIn(_nov, animals), const Ratio(1, 4));
  });

  test('follow-ups: answered and completed, out of those due', () {
    final now = DateTime(2026, 11, 20);
    final fs = <Map<String, dynamic>>[
      {'scheduledDate': _d(2026, 11, 2), 'status': 'confirmed', 'submittedAt': _d(2026, 11, 3)},
      {'scheduledDate': _d(2026, 11, 3), 'status': 'submitted', 'submittedAt': _d(2026, 11, 4)},
      {'scheduledDate': _d(2026, 11, 4), 'status': 'completed', 'manualCompletionReason': 'Phoned'},
      {'scheduledDate': _d(2026, 11, 5), 'status': 'reminderSent'},
      {'scheduledDate': _d(2026, 11, 6), 'status': 'cancelled'},
      {'scheduledDate': _d(2026, 11, 25), 'status': 'scheduled'},
      {'scheduledDate': _d(2026, 10, 1), 'status': 'scheduled'},
    ];
    final s = followUpStatsIn(_nov, fs, now);
    expect(s.responses, const Ratio(2, 4));
    expect(s.completion, const Ratio(2, 4));
    expect(s.overdueNow, 2);
  });

  test('returns: rate on finished windows, reasons, time, where they are, rehomed', () {
    final now = DateTime(2026, 11, 22);
    final year = Period(DateTime(2026, 1, 1), DateTime(2027, 1, 1));
    final adoptions = <Map<String, dynamic>>[
      {'id': 'x1', 'animalRecordId': 'a', 'releasedAt': _d(2026, 3, 1),
        'returnRequest': {'status': 'retrieved', 'requestedAt': _d(2026, 3, 31), 'reason': 'Housing Restrictions'}},
      {'id': 'x2', 'animalRecordId': 'b', 'releasedAt': _d(2026, 3, 5),
        'returnRequest': {'status': 'intake', 'requestedAt': _d(2026, 8, 2), 'reason': 'Other', 'reasonOther': 'Moving abroad'}},
      {'id': 'x3', 'animalRecordId': 'c', 'releasedAt': _d(2026, 4, 1),
        'returnRequest': {'status': 'declined', 'requestedAt': _d(2026, 4, 9), 'reason': 'Behavioral Challenges'}},
      {'id': 'x4', 'animalRecordId': 'd', 'releasedAt': _d(2026, 4, 2)},
      {'id': 'x5', 'animalRecordId': 'e', 'releasedAt': _d(2026, 10, 1)},
    ];
    final animals = <Map<String, dynamic>>[
      {'id': 'a', 'adoptionStatus': 'adopted', 'adoptedAt': _d(2026, 6, 1), 'adoptedApplicationId': 'y9'},
      {'id': 'b', 'adoptionStatus': 'adoptable'},
    ];
    final r = returnStatsIn(year, adoptions, animals, now);
    expect(r.total, 2);
    expect(r.success, const Ratio(3, 4));
    expect(r.returnRate, const Ratio(1, 4));
    expect(r.reasons, {'Housing Restrictions': 1, 'Other: Moving abroad': 1});
    expect(r.daysBeforeReturn.count, 2);
    expect(r.statusNow, {'Adopted again': 1, 'Listed for adoption': 1});
    expect(r.rehomed, const Ratio(1, 2));
  });

  test('funnel separates engagement from applications; tracking start is known', () {
    final engagement = <Map<String, dynamic>>[
      {'animalId': 'a', 'day': '2026-11-02', 'views': 30, 'saves': 6},
      {'animalId': 'b', 'day': '2026-11-03', 'views': 4},
      {'animalId': 'a', 'day': '2026-10-20', 'views': 50},
    ];
    final apps = <Map<String, dynamic>>[
      {'animalRecordId': 'b', 'createdAt': _d(2026, 11, 4), 'status': 'pending'},
      {'animalRecordId': 'b', 'createdAt': _d(2026, 11, 5), 'status': 'adopted', 'approvedAt': _d(2026, 11, 8), 'adoptedAt': _d(2026, 11, 9)},
    ];
    final f = adoptionFunnelIn(_nov, engagement, apps);
    expect((f.views, f.saves, f.applications, f.approved, f.adopted), (34, 6, 2, 1, 1));
    expect(f.viewToSave, const Ratio(6, 34));
    expect(f.trackingSince, DateTime(2026, 10, 20));

    final rows = listingRows(_nov, [
      {'id': 'a', 'name': 'Bantay', 'adoptionStatus': 'adoptable', 'readyForAdoptionAt': _d(2026, 8, 1)},
      {'id': 'b', 'name': 'Mingming', 'adoptionStatus': 'adoptable', 'readyForAdoptionAt': _d(2026, 10, 25)},
      {'id': 'c', 'name': 'Old', 'adoptionStatus': 'adopted'},
    ], engagement, apps, DateTime(2026, 11, 22), trackingSince: f.trackingSince);
    expect(rows.map((r) => r.name), ['Bantay', 'Mingming']);
    expect(rows.first.flags, [ListingFlag.viewedNoApplications, ListingFlag.savedNoApplications, ListingFlag.longListed]);
    // Listed after tracking started, 28 days, 4 views: low engagement.
    expect(rows.last.flags, [ListingFlag.lowEngagement]);
  });
}
