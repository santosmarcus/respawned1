import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/litter_report_link.dart';

FoundAnimalEntry _motherDog() {
  final e = FoundAnimalEntry()
    ..species = 'Dog'
    ..sex = 'Female'
    ..hasLitter = 'Yes';
  addTearDown(e.dispose);
  return e;
}

void main() {
  test('asked only for a female dog with a litter', () {
    final e = _motherDog();
    expect(e.asksLitterDetails, isTrue);
    e.hasLitter = 'Not sure';
    expect(e.asksLitterDetails, isFalse);

    final cat = FoundAnimalEntry()
      ..species = 'Cat'
      ..sex = 'Female'
      ..hasLitter = 'Yes';
    addTearDown(cat.dispose);
    expect(cat.asksLitterDetails, isFalse);
    expect(cat.litterMap, isNull);
    // A suspected pregnancy alone is not a litter.
    final pregnant = FoundAnimalEntry()
      ..species = 'Dog'
      ..sex = 'Female'
      ..hasLitter = 'No'
      ..suspectedPregnancy = 'Yes, suspected';
    addTearDown(pregnant.dispose);
    expect(pregnant.asksLitterDetails, isFalse);
  });

  test('validates count, location, condition and puppies needing attention', () {
    final e = _motherDog();
    expect(e.litterError, contains('how many puppies'));
    e.litterCountController.text = '0';
    expect(e.litterError, contains('at least 1'));
    e.litterCountController.text = '${kMaxLitterSize + 1}';
    expect(e.litterError, contains('or fewer'));
    e.litterCountController.text = '5';
    expect(e.litterError, contains('where'));
    e.litterLocation = kLitterSomeSeparated;
    expect(e.litterError, contains('look'));
    e.litterCondition = kLitterSomeSick;
    expect(e.litterError, contains('1 to 5'));
    e.puppiesNeedingAttentionController.text = '6';
    expect(e.litterError, contains('1 to 5'));
    e.puppiesNeedingAttentionController.text = '2';
    expect(e.litterError, isNull);
  });

  test('saves the litter, with group places only when split', () {
    final e = _motherDog()
      ..litterLocation = kLitterScattered
      ..litterCondition = kLitterAllHealthy;
    e.litterCountController.text = '4';
    e.litterGroupControllers
      ..add(TextEditingController(text: 'Under the stairs'))
      ..add(TextEditingController(text: ''));
    e.litterNotesController.text = 'Eyes still closed';
    expect(e.litterMap, {
      'count': 4,
      'location': kLitterScattered,
      'groupLocations': ['Under the stairs'],
      'condition': kLitterAllHealthy,
      'notes': 'Eyes still closed',
    });
    e.litterLocation = kLitterTogether;
    expect(e.litterMap!.containsKey('groupLocations'), isFalse);
  });

  test('changing species, sex or the litter answer clears the details', () {
    for (final change in <void Function(FoundAnimalEntry)>[
      (e) => e.species = 'Cat',
      (e) => e.sex = 'Male',
      (e) => e.hasLitter = 'No',
    ]) {
      final e = _motherDog()..litterCondition = kLitterAllHealthy;
      e.litterCountController.text = '3';
      change(e);
      expect(e.litterCountController.text, isEmpty);
      expect(e.litterCondition, isNull);
    }
  });

  test('offers a linked puppy report only when puppies need attention', () {
    final e = _motherDog()
      ..litterLocation = kLitterTogether
      ..litterCondition = kLitterAllHealthy;
    e.litterCountController.text = '4';
    expect(litterReportOffer('case1', [e]), isNull);
    e.litterCondition = kLitterSomeWeak;
    e.puppiesNeedingAttentionController.text = '2';
    final offer = litterReportOffer('case1', [FoundAnimalEntry()..species = 'Cat', e])!;
    expect(offer.motherIndex, 1);
    expect(offer.puppyCount, 2);
    expect(offer.toMap(), {'caseId': 'case1', 'animalIndex': 1, 'puppyCount': 2});

    final saved = {
      'animals': [
        {'litter': {'condition': kLitterSomeSick, 'puppiesNeedingAttention': 3}},
      ],
    };
    expect(litterReportOfferFromCase('case1', saved)!.puppyCount, 3);
    expect(litterReportOfferFromCase('case1', {...saved, 'litterReportCaseIds': ['p1']}), isNull);
  });

  test('a puppy report starts as Illness with one small dog per puppy', () {
    final form = RescueFormController();
    addTearDown(form.dispose);
    form.startLitterReport(const LitterReportLink(parentCaseId: 'case1', motherIndex: 0, puppyCount: 3));
    expect(form.selectedRescueType, 'Illness');
    expect(form.foundAnimals, hasLength(3));
    expect(form.foundAnimals.every((a) => a.species == 'Dog' && a.size == 'Small'), isTrue);
    expect(form.litterLink!.parentCaseId, 'case1');
  });
}
