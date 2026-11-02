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

  test('statusAfterTreatmentAccepted routes to the interested adopter', () {
    expect(
      statusAfterTreatmentAccepted({'interestedToAdopt': 'yes'}).status,
      'awaiting_adopter_pickup',
    );
    expect(
      statusAfterTreatmentAccepted({'interestedToAdopt': 'no'}).status,
      'in_transit_shelter',
    );
    expect(statusAfterTreatmentAccepted({}).status, 'in_transit_shelter');
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

    test('Deceased / breakdown / Other end the transit', () {
      expect(resolve(kEndReasonDeceased).isTerminal, isTrue);
      expect(resolve(kEndReasonBreakdown).isTerminal, isTrue);

      final other = resolve(kEndReasonOther, other: 'Flooded road');
      expect(other.status, 'ended');
      expect(other.reasonText, 'Flooded road');
      expect(other.statusLabel, 'Transit closed: Flooded road');

      expect(resolve(kEndReasonOther, other: '').reasonText, kEndReasonOther);
    });

    test('the dialog offers every reason', () {
      expect(kEndReasons, hasLength(7));
      expect(kSpecializedServiceTypes.last, 'Other');
    });
  });
}
