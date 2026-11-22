import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/rescue_metrics.dart';

final _p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
Timestamp _at(int day, [int hour = 9, int minute = 0]) => Timestamp.fromDate(DateTime(2026, 11, day, hour, minute));
final _before = Timestamp.fromDate(DateTime(2026, 10, 15));

void main() {
  group('referrals', () {
    final cases = <Map<String, dynamic>>[
      {'id': 'a', 'status': 'accepted', 'acceptedAt': _at(2)},
      {'id': 'b', 'status': 'referred', 'referral': {'referredAt': _at(3), 'type': 'anotherOrganization', 'referralReason': 'shelterAtCapacity'}},
      {'id': 'c', 'status': 'referred', 'referral': {'referredAt': _at(4), 'type': 'rescueVolunteer', 'referralReason': 'closerResponder'}},
      {'id': 'd', 'status': 'referred', 'linkReferral': {'at': _at(5)}},
      {'id': 'e', 'status': 'rejected', 'rejectionReason': 'noShelterSpace', 'rejectedAt': _at(6)},
      {'id': 'f', 'status': 'rejected', 'rejectionReason': 'healthyAnimalLowUrgency', 'rejectedAt': _at(7)},
      {'id': 'g', 'status': 'rejected', 'rejectionReason': 'duplicateReport', 'rejectedAt': _at(8)},
      // Outside the period, and a surrender (never an org decision).
      {'id': 'h', 'status': 'accepted', 'acceptedAt': _before},
      {'id': 'i', 'status': 'community_adoption', 'rescueType': 'Pet Surrender', 'createdAt': _at(9)},
    ];

    test('counts each kind, decided cases and capacity referrals', () {
      final r = referralsIn(_p, cases);
      expect(r.counts[ReferralKind.organization], 1);
      expect(r.counts[ReferralKind.volunteer], 1);
      expect(r.counts[ReferralKind.barangay], 1);
      expect(r.counts[ReferralKind.declinedAtCapacity], 1);
      expect(r.counts[ReferralKind.communityAdoption], 1);
      expect(r.rate, const Fraction(5, 7));
      expect(r.capacityShare, const Fraction(2, 5));
      expect(r.trackingSince, _before.toDate());
      expect(r.rate.tooFew, isTrue);
      expect(r.rate.percent, isNull);
    });
  });

  test('a case retrieved over two legs counts once; staff and legacy claims count', () {
    final offers = <Map<String, dynamic>>[
      {'caseId': 'a', 'status': 'completed', 'completedAt': _at(2), 'riderType': 'Pet Transporter'},
      {'caseId': 'a', 'status': 'completed', 'completedAt': _at(3), 'riderType': 'Pet Transporter'},
      {'caseId': 'b', 'status': 'completed', 'completedAt': _at(4), 'riderType': 'Rescue Volunteer'},
      {'caseId': 'z', 'status': 'completed', 'completedAt': _at(4), 'isDemo': true},
    ];
    final cases = <Map<String, dynamic>>[
      {'id': 'c', 'organizationTransport': {'startedAt': _at(5)}},
      {'id': 'd', 'riderId': 'r1', 'transitCompletedAt': _at(6)},
    ];
    final r = retrievalsIn(_p, cases, offers);
    expect(r[RetrievedBy.transporter], 2);
    expect(r[RetrievedBy.volunteer], 1);
    expect(r[RetrievedBy.staff], 1);
  });

  test('offer acceptance, minutes to accept and cases nobody took', () {
    final offers = <Map<String, dynamic>>[
      {'caseId': 'a', 'status': 'accepted', 'offeredAt': _at(2, 9), 'acceptedAt': _at(2, 9, 10)},
      {'caseId': 'b', 'status': 'completed', 'offeredAt': _at(3, 9), 'acceptedAt': _at(3, 9, 30)},
      {'caseId': 'c', 'status': 'rejected', 'offeredAt': _at(4)},
      {'caseId': 'c', 'status': 'expired', 'offeredAt': _at(4, 10)},
      {'caseId': 'd', 'status': 'cancelled', 'offeredAt': _at(5)},
      {'caseId': 'e', 'status': 'expired', 'offeredAt': _at(6), 'isDemo': true},
    ];
    final cases = <Map<String, dynamic>>[
      {'id': 'x', 'status': 'rejected', 'rejectionReason': 'noAvailableRiders', 'rejectedAt': _at(7)},
    ];
    final s = offerStatsIn(_p, offers, cases);
    expect(s.acceptance, const Fraction(2, 4));
    expect(s.minutesToAccept.value, 20);
    expect(s.minutesToAccept.count, 2);
    expect(s.declined, 1);
    expect(s.expired, 1);
    expect(s.casesWithNoTaker, 1);
    expect(s.declinedNoRiders, 1);
  });

  test('treatment exits by outcome, and median days', () {
    final cases = <Map<String, dynamic>>[
      {
        'id': 'a',
        'treatmentAcceptedAt': _at(1),
        'animals': [
          {'dischargedAt': _at(5), 'postTreatmentAction': 'intake'},
          {'dischargedAt': _at(11), 'postTreatmentAction': 'release'},
          {'deceasedAt': _at(3), 'outcome': 'deceased'},
        ],
      },
      {'id': 'b', 'dateAdmitted': _at(2), 'adopterPickupConfirmedAt': _at(9), 'dischargedAt': _at(9)},
    ];
    final r = treatmentExitsIn(_p, cases);
    expect(r.counts[TreatmentExit.shelter], 1);
    expect(r.counts[TreatmentExit.reporter], 1);
    expect(r.counts[TreatmentExit.adopter], 1);
    expect(r.counts[TreatmentExit.died], 1);
    expect(r.recoveredShare, const Fraction(3, 4));
    // 4, 10 and 7 days.
    expect(r.days.value, 7);
  });

  test('response time segments are medians of the cases reaching each step', () {
    final cases = <Map<String, dynamic>>[
      {'id': 'a', 'createdAt': _at(2, 8), 'acceptedAt': _at(2, 8, 30), 'pickedUpAt': _at(2, 10), 'treatmentAcceptedAt': _at(2, 11)},
      {'id': 'b', 'createdAt': _at(3, 8), 'acceptedAt': _at(3, 9, 30)},
      {'id': 'c', 'createdAt': _at(4, 8), 'acceptedAt': _at(4, 8, 10), 'pickedUpAt': _at(4, 9, 10)},
    ];
    final r = responseTimesIn(_p, cases);
    expect(r.reportToAccepted.value, 30);
    expect(r.reportToAccepted.count, 3);
    expect(r.acceptedToPickup.value, 75);
    expect(r.pickupToClinic.value, 60);
    expect(r.pickupToClinic.count, 1);
  });

  test('intake by urgency and how many are finished', () {
    final cases = <Map<String, dynamic>>[
      {'id': 'a', 'createdAt': _at(2), 'urgency': 'Critical', 'status': 'completed'},
      {'id': 'b', 'createdAt': _at(3), 'urgency': 'Critical', 'status': 'pending'},
      {'id': 'c', 'createdAt': _at(4), 'status': 'rejected'},
      {'id': 'd', 'createdAt': _at(4), 'status': 'community_adoption'},
      {'id': 'e', 'createdAt': _before, 'status': 'pending'},
    ];
    final r = intakeVolumeIn(_p, cases);
    expect(r.byUrgency, {'Critical': 2, 'Not assessed': 1});
    expect(r.resolved, const Fraction(2, 3));
  });

  test('median and counts of animals', () {
    expect(medianOf([5, 1, 3]).value, 3);
    expect(medianOf([1, 2, 3, 10]).value, 2.5);
    expect(medianOf(const []).isEmpty, isTrue);
    expect(animalCountOf({'animals': [{}, {}]}), 2);
    expect(animalCountOf({}), 1);
  });
}
