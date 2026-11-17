import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';

void main() {
  group('case location helpers', () {
    test('latLngFrom reads numeric pairs only', () {
      expect(
        latLngFrom({'lat': 14.5, 'lng': 121}, 'lat', 'lng'),
        const LatLng(14.5, 121.0),
      );
      expect(latLngFrom({'lat': '14.5', 'lng': 121}, 'lat', 'lng'), isNull);
      expect(latLngFrom({}, 'lat', 'lng'), isNull);
    });

    test('clinicLatLngFrom prefers the dropoff over the vet clinic', () {
      expect(
        clinicLatLngFrom({
          'dropoffLat': 1,
          'dropoffLng': 2,
          'vetClinicLat': 3,
          'vetClinicLng': 4,
        }),
        const LatLng(1, 2),
      );
      expect(
        clinicLatLngFrom({'vetClinicLat': 3, 'vetClinicLng': 4}),
        const LatLng(3, 4),
      );
    });

    test('clinicAddressFrom trims and falls back', () {
      expect(clinicAddressFrom({'dropoffAddress': '  A St  '}), 'A St');
      expect(
        clinicAddressFrom({'dropoffAddress': '  ', 'vetClinicAddress': 'B'}),
        'B',
      );
      expect(clinicAddressFrom({}), '');
    });
  });

  group('clinic profiles', () {
    test('clinicProfileId uses the place id, else an address slug', () {
      expect(clinicProfileId(placeId: 'abc', address: 'x'), 'abc');
      expect(
        clinicProfileId(placeId: '', address: '  12 Vet Clinic, Manila! '),
        '12_vet_clinic_manila',
      );
      expect(clinicProfileId(address: '!!!'), 'unknown_clinic');
    });

    test('clinicDeclineReasons keeps only clinic-relevant reasons', () {
      expect(clinicDeclineReasons(accepted: true, reason: 'x'), isEmpty);
      expect(
        clinicDeclineReasons(
          accepted: false,
          reason:
          'Clinic at full capacity, Owner unreachable, No Veterinarian/Specialist Available',
        ),
        ['Clinic at full capacity', 'No Veterinarian/Specialist Available'],
      );
    });

    test('capabilityDeclineCount ignores full-capacity declines', () {
      expect(
        capabilityDeclineCount({
          'Clinic at full capacity': 5,
          'No Veterinarian/Specialist Available': 1,
          'Insufficient Medication/Treatment Supplies': 1,
        }),
        kClinicCapabilityDeclineLimit,
      );
      expect(capabilityDeclineCount({}), 0);
    });
  });

  test('statusAfterTreatmentAccepted completes the trip only for a confirmed adopter', () {
    final confirmed = statusAfterTreatmentAccepted({
      'interestedToAdopt': 'yes',
      'adoptionRequest': {'applicationId': 'a1', 'status': 'approved'},
    });
    expect(confirmed.status, 'awaiting_adopter_pickup');
    expect(confirmed.completesTransit, isTrue);

    // Interested, or a request still waiting for the organization: the
    // transporter continues to the shelter.
    for (final data in [
      {'interestedToAdopt': 'yes'},
      {'willingAdopterId': 'u1'},
      {'interestedToAdopt': 'yes', 'adoptionRequest': {'applicationId': 'a1', 'status': 'pending'}},
    ]) {
      final next = statusAfterTreatmentAccepted(data);
      expect(next.status, 'in_transit_shelter');
      expect(next.completesTransit, isFalse);
      expect(next.label, contains('interested adopter'));
    }
    expect(statusAfterTreatmentAccepted({'interestedToAdopt': 'no'}).status, 'in_transit_shelter');
    expect(statusAfterTreatmentAccepted({}).label, 'Treatment accepted. On the way to shelter.');
  });

  group('resolveEndReason', () {
    EndReasonOutcome resolve(
        String reason, {
          String? other,
          String notes = '',
          String? serviceType,
        }) => resolveEndReason(
      EndReasonSelection(
        reason: reason,
        otherText: other,
        notes: notes,
        serviceType: serviceType,
      ),
    );

    test('Not Found waits for the reporter instead of ending', () {
      final o = resolve(kEndReasonNotFound, notes: 'gone');
      expect(o.status, RescueStatus.unableToLocate.firestoreValue);
      expect(o.awaitingReporter, isTrue);
      expect(o.excludeFromTransporterFault, isFalse);
      expect(o.isTerminal, isFalse);
      expect(o.notes, 'gone');
    });

    test('Reporter Unreachable is an unsuccessful pickup', () {
      final o = resolve(kEndReasonReporterUnreachable);
      expect(o.status, RescueStatus.pickupUnsuccessful.firestoreValue);
      expect(o.awaitingReporter, isTrue);
      expect(o.isTerminal, isFalse);
    });

    test('Aggressive escalates without blaming the transporter', () {
      final o = resolve(kEndReasonAggressive);
      expect(o.status, RescueStatus.needsSpecializedAssistance.firestoreValue);
      expect(o.excludeFromTransporterFault, isTrue);
      expect(o.serviceType, isNull);
    });

    test('Specialized transport carries the service type forward', () {
      final o = resolve(
        kEndReasonSpecializedTransport,
        serviceType: 'Secure crate/cage required',
      );
      expect(o.status, RescueStatus.needsSpecializedAssistance.firestoreValue);
      expect(o.serviceType, 'Secure crate/cage required');
      expect(o.statusLabel, contains('(Secure crate/cage required)'));
      expect(o.excludeFromTransporterFault, isTrue);

      final blank = resolve(kEndReasonSpecializedTransport, serviceType: '');
      expect(blank.serviceType, isNull);
      expect(blank.statusLabel, isNot(contains('(')));
    });

    test('Deceased, breakdown and Other end this transporter trip', () {
      expect(resolve(kEndReasonDeceased).isTerminal, isTrue);
      expect(resolve(kEndReasonBreakdown).isTerminal, isTrue);
      expect(resolve(kEndReasonOther).isTerminal, isTrue);
      expect(resolve(kEndReasonAggressive).isTerminal, isFalse);
      expect(resolve(kEndReasonNotFound).kind, isNull);
    });

    test('no end reason writes a status staff screens cannot read', () {
      for (final reason in kEndReasons) {
        final status = resolve(reason).status;
        expect(status, isNot('ended'), reason: reason);
        expect(
          RescueStatus.fromFirestoreValue(status),
          isNot(RescueStatus.pendingReview),
          reason: reason,
        );
      }
    });

    test('Vehicle breakdown goes back to Assign Transporter', () {
      final o = resolve(kEndReasonBreakdown, notes: 'flat tire');
      expect(
        RescueStatus.fromFirestoreValue(o.status),
        RescueStatus.awaitingAssignment,
      );
      expect(o.kind, kEndKindBreakdown);
      expect(o.notes, 'flat tire');
    });

    test('Deceased waits for staff to confirm', () {
      final o = resolve(kEndReasonDeceased);
      expect(RescueStatus.fromFirestoreValue(o.status), RescueStatus.transitEnded);
      expect(o.kind, kEndKindDeceased);
    });

    test('Other needs a staff decision and keeps the free text', () {
      final other = resolve(kEndReasonOther, other: 'Flooded road');
      expect(RescueStatus.fromFirestoreValue(other.status), RescueStatus.transitEnded);
      expect(other.kind, kEndKindOther);
      expect(other.reasonText, 'Flooded road');
      expect(other.statusLabel, contains('Flooded road'));

      expect(resolve(kEndReasonOther, other: '').reasonText, kEndReasonOther);
    });

    test('legacy ended cases read as needing a decision', () {
      expect(RescueStatus.fromFirestoreValue('ended'), RescueStatus.transitEnded);
    });

    test('shelter drop-off sends undecided animals to Intake', () {
      final at = DateTime(2026, 11, 17);
      final out = animalsAfterShelterDropoff([
        {'species': 'Dog'},
        {'species': 'Cat', 'outcome': 'deceased'},
        {'species': 'Dog', 'postTreatmentAction': 'release'},
      ], at);
      expect(out[0]['postTreatmentAction'], 'intake');
      expect(out[0]['postTreatmentStartedAt'], at);
      expect(out[1].containsKey('postTreatmentAction'), isFalse);
      expect(out[2]['postTreatmentAction'], 'release');
    });

    test('the dialog offers every reason', () {
      expect(kEndReasons, hasLength(7));
      expect(kSpecializedServiceTypes.last, 'Other');
    });
  });
}
