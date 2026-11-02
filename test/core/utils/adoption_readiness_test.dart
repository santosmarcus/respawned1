import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/adoption_readiness.dart';

ReadinessCheck _check(List<ReadinessCheck> checks, ReadinessItem item) => checks.firstWhere((c) => c.item == item);

void main() {
  test('an animal in active treatment is blocked whatever is ticked', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: true));
    expect(_check(checks, ReadinessItem.health).state, ReadinessState.blocked);
    expect(readinessSatisfied(checks, ReadinessItem.values.toSet()), isFalse);
  });

  test('vaccination alone is not enough: every confirmation must be ticked', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(
      inActiveTreatment: false,
      vaccineCount: 3,
      spayedNeutered: true,
    ));
    expect(readinessSatisfied(checks, {ReadinessItem.vaccines}), isFalse);
    expect(readinessSatisfied(checks, {ReadinessItem.health, ReadinessItem.behavior, ReadinessItem.vaccines}), isTrue);
  });

  test('spayed animals and animals with no ongoing care need no extra confirmation', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false, spayedNeutered: true));
    expect(_check(checks, ReadinessItem.spayNeuter).state, ReadinessState.ok);
    expect(_check(checks, ReadinessItem.continuingCare).state, ReadinessState.ok);
  });

  test('not spayed and ongoing care each need a confirmation', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(
      inActiveTreatment: false,
      currentMedications: 'Doxycycline',
      specialNeeds: ['Blind'],
    ));
    expect(_check(checks, ReadinessItem.spayNeuter).state, ReadinessState.needsConfirmation);
    final care = _check(checks, ReadinessItem.continuingCare);
    expect(care.state, ReadinessState.needsConfirmation);
    expect(care.finding, contains('Doxycycline'));
    expect(care.finding, contains('Blind'));
    expect(readinessSatisfied(checks, {ReadinessItem.health, ReadinessItem.behavior, ReadinessItem.vaccines}), isFalse);
    expect(readinessSatisfied(checks, ReadinessItem.values.toSet()), isTrue);
  });

  test('vaccine findings report overdue doses', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(
      inActiveTreatment: false,
      vaccineCount: 2,
      overdueVaccineCount: 1,
    ));
    expect(_check(checks, ReadinessItem.vaccines).finding, '2 vaccine record(s), 1 overdue.');
  });
}
