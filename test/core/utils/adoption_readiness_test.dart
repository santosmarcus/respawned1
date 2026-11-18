import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/adoption_readiness.dart';

ReadinessCheck _check(List<ReadinessCheck> checks, ReadinessItem item) => checks.firstWhere((c) => c.item == item);

final _ready = ReadinessInput(
  inActiveTreatment: false,
  vaccineCount: 2,
  dewormed: true,
  spayedNeutered: true,
  lastVetCheckup: DateTime(2026, 10, 3),
  temperament: const ['Calm'],
  photoCount: 1,
);

void main() {
  test('the checklist has the seven merged items in order', () {
    final checks = assessAdoptionReadiness(_ready);
    expect(checks.map((c) => c.label), [
      'Not in treatment',
      'Vaccinated',
      'Dewormed',
      'Spay/neuter',
      'Vet checkup',
      'Temperament/behavior',
      'Photo',
    ]);
    expect(readinessAllMet(checks), isTrue);
    expect(unmetReadiness(checks), isEmpty);
  });

  test('an animal in active treatment is not ready', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: true));
    final c = _check(checks, ReadinessItem.notInTreatment);
    expect(c.met, isFalse);
    expect(c.reason, contains('treatment'));
  });

  test('vaccine records decide vaccination; overdue doses are unmet', () {
    final overdue = assessAdoptionReadiness(const ReadinessInput(
      inActiveTreatment: false,
      vaccineCount: 2,
      overdueVaccineCount: 1,
    ));
    expect(_check(overdue, ReadinessItem.vaccinated).met, isFalse);
    expect(_check(overdue, ReadinessItem.vaccinated).reason, '2 vaccine record(s), 1 overdue.');

    final none = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false, vaccineCount: 0));
    expect(_check(none, ReadinessItem.vaccinated).met, isFalse);
    expect(_check(none, ReadinessItem.vaccinated).recorded, isTrue);
  });

  test('without vaccine records loaded, the legacy flag is used, else not recorded', () {
    final legacy = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false, vaccinated: true));
    expect(_check(legacy, ReadinessItem.vaccinated).met, isTrue);

    final unknown = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false));
    expect(_check(unknown, ReadinessItem.vaccinated).done, isNull);
  });

  test('unrecorded preventive care shows as not recorded, a recorded no as unmet', () {
    final checks = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false, dewormed: false));
    expect(_check(checks, ReadinessItem.dewormed).done, isFalse);
    expect(_check(checks, ReadinessItem.spayNeuter).done, isNull);
    expect(_check(checks, ReadinessItem.vetCheckup).done, isFalse);
    expect(_check(checks, ReadinessItem.photo).met, isFalse);
  });

  test('the stored record lists unmet items and keeps the override reason only when overridden', () {
    final unmet = assessAdoptionReadiness(const ReadinessInput(inActiveTreatment: false, photoCount: 1));
    final overridden = adoptionReadinessRecord(
      checks: unmet,
      confirmedBy: 'Staff',
      confirmedAt: 'now',
      overrideReason: 'Spay booked next week',
    );
    expect(overridden['overridden'], isTrue);
    expect(overridden['overrideReason'], 'Spay booked next week');
    expect(overridden['unmet'], containsAll(['vaccinated', 'dewormed', 'spayNeuter', 'vetCheckup', 'temperament']));
    expect(overridden['unmet'], isNot(contains('photo')));
    expect((overridden['checks'] as Map).keys, hasLength(7));

    final clean = adoptionReadinessRecord(
      checks: assessAdoptionReadiness(_ready),
      confirmedBy: 'Staff',
      confirmedAt: 'now',
      overrideReason: 'stale',
    );
    expect(clean['overridden'], isFalse);
    expect(clean['overrideReason'], isNull);
    expect(clean['unmet'], isEmpty);
  });
}
