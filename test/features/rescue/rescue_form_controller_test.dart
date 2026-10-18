import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

RescueFormController _form() {
  final form = RescueFormController();
  addTearDown(form.dispose);
  return form;
}

void _addPhoto(RescueFormController form, int slot) {
  form.mediaFiles[slot] = RescueMediaItem(
    file: XFile('photo_$slot.jpg'),
    isVideo: false,
  );
}

void main() {
  group('options', () {
    test('rescue types carry their urgency', () {
      expect(urgencyForRescueType('Injury'), 'Critical');
      expect(urgencyForRescueType('Pet Surrender'), 'Low');
      expect(urgencyForRescueType(null), isNull);
      expect(urgencyForRescueType('Unknown'), isNull);
    });

    test('breed options follow species', () {
      expect(breedOptionsFor(kDogSpecies), kDogBreeds);
      expect(breedOptionsFor(kCatSpecies), kCatBreeds);
      expect(breedOptionsFor(null), [kOthersBreedLabel]);
    });
  });

  group('validateLostPetReport', () {
    test('asks whether the reporter is the owner first', () {
      final form = _form()..selectedRescueType = 'Lost Pet';
      expect(
        form.validateLostPetReport(),
        'Please tell us whether you are the owner.',
      );
    });

    test('requires at least one photo', () {
      final form = _form()..isOwner = true;
      expect(form.validateLostPetReport(), 'Please add at least 1 photo.');
    });

    test('owner side: required fields, then phone, then reward amount', () {
      final form = _form()..isOwner = true;
      _addPhoto(form, 0);
      expect(
        form.validateLostPetReport(),
        'Please fill in all required fields.',
      );

      form
        ..petNameController.text = 'Bantay'
        ..selectedAnimalType = kDogSpecies
        ..lostColorController.text = 'Brown'
        ..lastSeenDate = DateTime(2026, 10, 1)
        ..ownerContactController.text = '12345';
      expect(
        form.validateLostPetReport(),
        'Please enter a valid Philippine mobile number.',
      );

      form.ownerContactController.text = '09171234567';
      expect(form.validateLostPetReport(), isNull);

      form
        ..offerReward = true
        ..rewardAmountController.text = 'abc';
      expect(form.validateLostPetReport(), 'Enter a valid amount.');
    });

    test('finder side needs urgency only when rescue is requested', () {
      final form = _form()..isOwner = false;
      _addPhoto(form, 0);
      form.foundAnimals.first.species = kCatSpecies;
      form
        ..conditionController.text = 'Scared'
        ..animalStatus = 'With me, I can hold it for now'
        ..finderContactController.text = '+639171234567';
      expect(form.validateLostPetReport(), isNull);

      form.finderNeedsRescue = true;
      expect(
        form.validateLostPetReport(),
        'Please fill in all required fields.',
      );
      form.selectedUrgency = 'Low';
      expect(form.validateLostPetReport(), isNull);
    });
  });

  group('validateRescueReport', () {
    RescueFormController strayReady() {
      final form = _form()
        ..selectedRescueType = 'Injury'
        ..selectedUrgency = 'Critical'
        ..onSiteChoice = 'Yes, I am on-site'
        ..coordinateChoice = 'yes'
        ..adoptionChoice = 'no';
      form.conditionController.text = 'Bleeding leg';
      form.foundAnimals.first.species = kDogSpecies;
      return form;
    }

    test('empty form is missing required fields', () {
      expect(
        _form().validateRescueReport(),
        'Please fill in all required fields.',
      );
    });

    test('a complete stray report passes', () {
      expect(strayReady().validateRescueReport(), isNull);
    });

    test('adoption interest needs the commitment checkbox', () {
      final form = strayReady()..adoptionChoice = 'yes';
      expect(
        form.validateRescueReport(),
        'Please agree to the adoption-interest terms before submitting.',
      );
      form.adoptionCommitmentAccepted = true;
      expect(form.validateRescueReport(), isNull);
    });

    test('declining to coordinate requires a valid witness', () {
      final form = strayReady()..coordinateChoice = 'no';
      expect(form.validateRescueReport(), 'Witness name is required.');
      form.witnessNameController.text = 'Juan Dela Cruz';
      expect(form.validateRescueReport(), 'Mobile number is required.');
      form.witnessNumberController.text = '09171234567';
      expect(form.validateRescueReport(), isNull);
    });

    test('surrender: "Other" reason and medical/behavioral explanation', () {
      final form = _form()
        ..selectedRescueType = 'Pet Surrender'
        ..selectedUrgency = 'Low'
        ..surrenderReason = 'Other (please specify)'
        ..petAcquisitionSource = 'Breeder';
      form.conditionController.text = 'Healthy';
      form.surrenderDurationController.text = '2 years';
      form.surrenderAgeController.text = '3 years old';
      form.foundAnimals.first.species = kCatSpecies;
      expect(
        form.validateRescueReport(),
        'Please specify the reason for surrendering.',
      );

      form.surrenderReason = 'Behavioral issues';
      expect(
        form.validateRescueReport(),
        "Please explain the issue and what you've tried.",
      );
      form.surrenderExplanationController.text =
          'Bites visitors; tried training.';
      expect(form.validateRescueReport(), isNull);
    });
  });

  test('FoundAnimalEntry.breedText resolves "Others" to the typed breed', () {
    final entry = FoundAnimalEntry();
    addTearDown(entry.dispose);
    expect(entry.breedText, '');
    entry
      ..breed = kOthersBreedLabel
      ..breedOtherController.text = '  Mixed  ';
    expect(entry.breedText, 'Mixed');
  });
}
