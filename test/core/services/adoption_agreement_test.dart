import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/services/adoption_agreement_service.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_terms_page.dart';

AnimalRecord _animal(Map<String, dynamic> data) =>
    AnimalRecord.fromMap('a1', {'name': 'Mochi', 'species': 'Dog', ...data});

void main() {
  group('careDisclosures', () {
    test('a healthy, spayed animal has nothing to disclose', () {
      expect(AdoptionAgreementService.careDisclosures(_animal({'spayedNeutered': true})), isEmpty);
    });

    test('lists medications, conditions, special needs and sterilization', () {
      final lines = AdoptionAgreementService.careDisclosures(_animal({
        'spayedNeutered': false,
        'currentMedications': 'Doxycycline twice daily',
        'chronicConditions': 'Mild hip dysplasia',
        'specialNeeds': true,
        'specialNeedsTypes': ['Blind'],
        'specialNeedsNotes': 'Needs guided indoor movement.',
      }));
      expect(lines, contains('Current medications: Doxycycline twice daily'));
      expect(lines, contains('Ongoing conditions: Mild hip dysplasia'));
      expect(lines, contains('Special needs: Blind; Needs guided indoor movement.'));
      expect(lines, contains('Not yet spayed/neutered.'));
    });

    test('no animal record means no disclosures', () {
      expect(AdoptionAgreementService.careDisclosures(null), isEmpty);
    });
  });

  test('the agreement and the in-app terms share one list', () {
    final terms = adoptionTermsFor('Mochi');
    expect(terms, isNotEmpty);
    expect(terms[1], contains('Mochi'));
  });
}
