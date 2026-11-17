import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

void main() {
  const legacy = <String, dynamic>{
    'maxCapacity': 40,
    'isolationCapacity': 6,
    'monthlyBudget': 25000.0,
    'foodPerDayKg': 12.5,
    'ridersNeeded': 2,
    'updatedByName': 'Old Admin',
  };

  group('mergeShelterSettingsData', () {
    test('no own document: the old platform-wide values are used', () {
      expect(mergeShelterSettingsData(null, legacy), legacy);
    });

    test('no old document: the own values are used', () {
      const own = <String, dynamic>{'maxCapacity': 30};
      expect(mergeShelterSettingsData(own, null), own);
    });

    test('capacity saved from Organization Profile keeps the other old values', () {
      final merged = mergeShelterSettingsData(const {'maxCapacity': 55, 'updatedBy': 'uid1'}, legacy)!;
      final settings = ShelterSettings.fromMap(merged);
      expect(settings.capacity, 55);
      expect(settings.isolationCapacity, 6);
      expect(settings.monthlyBudget, 25000.0);
      expect(settings.foodPerDayKg, 12.5);
      expect(settings.ridersNeeded, 2);
    });

    test('a value the organization saved as not set stays not set', () {
      final merged = mergeShelterSettingsData(const {
        'maxCapacity': 55,
        'isolationCapacity': 4,
        'monthlyBudget': null,
        'foodPerDayKg': null,
        'ridersNeeded': null,
      }, legacy)!;
      final settings = ShelterSettings.fromMap(merged);
      expect(settings.isolationCapacity, 4);
      expect(settings.monthlyBudget, isNull);
      expect(settings.foodPerDayKg, isNull);
      expect(settings.ridersNeeded, isNull);
    });

    test('who last updated never comes from the old document', () {
      final merged = mergeShelterSettingsData(const {'maxCapacity': 55}, legacy)!;
      expect(merged.containsKey('updatedByName'), isFalse);
    });
  });
}
