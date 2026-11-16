import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';

void main() {
  group('availabilityFromAnimalState', () {
    test('an adoptable animal is open to new applicants', () {
      expect(
        availabilityFromAnimalState({'adoptionStatus': 'adoptable'}),
        AnimalAdoptionAvailability.available,
      );
    });

    test('only a reservation or an adoption takes the animal', () {
      expect(
        availabilityFromAnimalState({'adoptionStatus': 'reserved'}),
        AnimalAdoptionAvailability.reservedForOther,
      );
      expect(
        availabilityFromAnimalState({'adoptionStatus': 'adopted'}),
        AnimalAdoptionAvailability.adopted,
      );
    });

    test('a missing, archived, deceased or not-ready animal is closed', () {
      for (final data in <Map<String, dynamic>?>[
        null,
        {'adoptionStatus': 'adoptable', 'archived': true},
        {'adoptionStatus': 'adoptable', 'status': 'deceased'},
        {'adoptionStatus': 'not_ready'},
        {},
      ]) {
        expect(
          availabilityFromAnimalState(data),
          AnimalAdoptionAvailability.unavailable,
          reason: '$data',
        );
      }
    });
  });

  group('isReturnedToIntake', () {
    test('an adoption whose return reached Intake is over', () {
      expect(
        isReturnedToIntake({
          'status': 'adopted',
          'returnRequest': {'status': 'intake'},
        }),
        isTrue,
      );
    });

    test('a return still in progress, or none, is not', () {
      expect(isReturnedToIntake({'status': 'adopted'}), isFalse);
      expect(
        isReturnedToIntake({
          'status': 'adopted',
          'returnRequest': {'status': 'retrieved'},
        }),
        isFalse,
      );
    });
  });
}
