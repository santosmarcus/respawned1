import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/transport_suitability.dart';

void main() {
  VehicleSuitability check(String? type, Object? capacity, int animals, [List<String> enclosed = const []]) =>
      vehicleSuitability(vehicleType: type, declaredCapacity: capacity, animals: animals, enclosedReasons: enclosed);

  test('one animal: a motorcycle or any registered vehicle', () {
    expect(check('Motorcycle', null, 1).suitable, isTrue);
    expect(check('Sedan', null, 1).suitable, isTrue);
    expect(check(null, 3, 1).suitable, isFalse);
  });

  test('two animals need a declared capacity of at least two', () {
    expect(check('Motorcycle', 5, 2).suitable, isFalse);
    expect(check('Sedan', null, 2).suitable, isFalse);
    expect(check('Sedan', 2, 2).suitable, isTrue);
  });

  test('more than two: a car or larger whose capacity covers them all', () {
    expect(check('Cargo Van/L300', 6, 5).suitable, isTrue);
    expect(check('SUV', 3, 5).suitable, isFalse);
    expect(check('SUV', 3, 5).reason, 'Carries up to 3; this trip has 5');
    expect(check('scooter', 10, 3).suitable, isFalse);
  });

  test('a motorcycle never takes an animal that needs an enclosed vehicle', () {
    final r = check('Motorcycle', 1, 1, ['a large animal']);
    expect(r.suitable, isFalse);
    expect(r.reason, contains('enclosed'));
    expect(check('Sedan', 1, 1, ['a large animal']).suitable, isTrue);
  });

  test('declared capacity is validated, never assumed', () {
    expect(declaredAnimalCapacity(3), 3);
    expect(declaredAnimalCapacity('4'), 4);
    expect(declaredAnimalCapacity(0), isNull);
    expect(declaredAnimalCapacity(kMaxDeclaredAnimals + 1), isNull);
    expect(declaredAnimalCapacity('two'), isNull);
  });

  test('trip size and enclosed-transport reasons come from the case', () {
    expect(animalsToTransport({}), 1);
    expect(animalsToTransport({'animals': [{}, {}, {}]}), 3);
    expect(enclosedTransportReasons({'animals': [{'size': 'Small'}]}), isEmpty);
    final reasons = enclosedTransportReasons({
      'urgency': 'Critical',
      'animals': [
        {'size': 'Large'},
        {'mobility': kMobilityOptions[2]},
        {'litter': {'count': 4}},
      ],
    });
    expect(reasons, containsAll(['critical urgency', 'a large animal', 'an animal that cannot walk', 'a mother with a litter']));
  });
}
