import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/urgency_assessment.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';
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
    test('rescue types no longer carry an urgency', () {
      for (final option in kRescueTypeOptions) {
        expect(option.containsKey('urgency'), isFalse, reason: option['label']);
      }
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
      // No free-text condition on the finder side (the animal card's
      // Health & Behavior Assessment covers it).
      form
        ..animalStatus = 'With me, I can hold it for now'
        ..finderContactController.text = '+639171234567';
      expect(form.validateLostPetReport(), isNull);
      // Lost Pet never asks for an urgency or organization help.
      form.selectedRescueType = kRescueTypeLostPet;
      expect(form.urgencyAssessment, isNull);
      expect(form.asksOrgCoordination, isFalse);
      expect(form.orgInvolvement, OrgInvolvement.notFacilitated);
    });
  });

  group('validateRescueReport', () {
    RescueFormController strayReady() {
      final form = _form()
        ..selectedRescueType = 'Injury'
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
        ..surrenderReason = 'Other (please specify)'
        ..surrenderTimeline = 'Within a month';
      form.conditionController.text = 'Healthy';
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

  test('surrender requires the reason and timeline', () {
    final form = _form()
      ..selectedRescueType = 'Pet Surrender'
      ..surrenderReason = 'Lack of time';
    form.conditionController.text = 'Healthy';
    form.foundAnimals.first.species = kDogSpecies;
    expect(form.validateRescueReport(), 'Please fill in all required fields.');
    form.surrenderTimeline = 'Flexible';
    expect(form.validateRescueReport(), isNull);
  });

  test('a rescue-org acquisition on any animal stops the surrender', () {
    final form = _form()..selectedRescueType = 'Pet Surrender';
    form.foundAnimals.add(FoundAnimalEntry());
    expect(form.isRescueOrgAcquisition, isFalse);
    form.foundAnimals.last.acquisitionSource = 'Rescue Org';
    expect(form.isRescueOrgAcquisition, isTrue);
  });

  test('abandonment requires its follow-up answers', () {
    final form = _form()
      ..selectedRescueType = 'Abandonment'
      ..onSiteChoice = 'Yes, I am on-site'
      ..coordinateChoice = 'yes'
      ..adoptionChoice = 'no';
    form.conditionController.text = 'Thin, scared';
    form.foundAnimals.first.species = kDogSpecies;
    expect(form.validateRescueReport(), 'Please fill in all required fields.');

    form
      ..abandonmentDuration = '1–3 days'
      ..abandonmentLocation = 'Tied or caged outside'
      ..abandonmentFoodWater = 'No'
      ..abandonmentWitness = 'I found the animal alone'
      ..abandonmentBelongings = 'No';
    // No food or water: asks whether the reporter can provide some.
    expect(form.asksAbandonmentCanProvideFood, isTrue);
    expect(form.validateRescueReport(), 'Please fill in all required fields.');
    form.abandonmentCanProvideFood = 'Yes';
    expect(form.validateRescueReport(), isNull);

    form.abandonmentLocation = kAbandonmentLocationOther;
    expect(
      form.validateRescueReport(),
      'Please specify where the animal was left.',
    );
    form.abandonmentLocationOtherController.text = 'Under a bridge';
    expect(form.validateRescueReport(), isNull);

    form
      ..abandonmentFoodWater = 'Yes'
      ..abandonmentCanProvideFood = null;
    expect(form.asksAbandonmentCanProvideFood, isFalse);
    expect(form.validateRescueReport(), isNull);
  });

  test('neglect or abuse requires its follow-up answers', () {
    final form = _form()
      ..selectedRescueType = 'Neglect or Abuse'
      ..abuseReportPath = kAbusePathOrgAssistance;
    form.conditionController.text = 'Chained, thin';
    form.foundAnimals.first.species = kDogSpecies;
    expect(form.validateRescueReport(), 'Please fill in all required fields.');

    form
      ..neglectHappeningNow = 'No'
      ..neglectOwnerKnown = 'Yes'
      ..neglectFrequency = 'Ongoing for weeks or longer'
      ..neglectReportedToAuthorities = 'No'
      ..neglectWillingWitness = 'Yes'
      ..neglectOtherWitness = 'No';
    expect(form.validateRescueReport(), 'Please fill in all required fields.');
    form.neglectObserved.add(kNeglectObservedAbandoned);
    expect(form.validateRescueReport(), isNull);

    // A named witness needs a name and whether they would testify.
    form.neglectOtherWitness = 'Yes';
    expect(form.validateRescueReport(), contains("witness's name"));
    form.neglectWitnessNameController.text = 'Ana Cruz';
    expect(form.validateRescueReport(), contains('willing to testify'));
    form.neglectWitnessWilling = 'Yes';
    expect(form.validateRescueReport(), isNull);

    // "Other" is described in the report's own description.
    form.neglectObserved.add(kNeglectObservedOther);
    expect(form.validateRescueReport(), isNull);
  });

  test('every report needs the truthfulness declaration', () {
    final form = _form();
    expect(form.validateDeclaration(), isNotNull);
    form.truthfulnessDeclared = true;
    expect(form.validateDeclaration(), isNull);
  });

  test('surrender cards need their own details instead of environment', () {
    final entry = FoundAnimalEntry()
      ..bodyCondition = 'a'
      ..mobility = 'a'
      ..alertness = 'a'
      ..eyesNoseMouth = 'a'
      ..skinAndCoat = 'a'
      ..appetiteHydration = 'a'
      ..biteRisk = 'Low'
      ..escapeRisk = 'Low';
    addTearDown(entry.dispose);
    entry.behavior.add('Calm');
    expect(entry.hasCompleteAssessment, isFalse);
    expect(entry.isAssessmentComplete(isSurrender: true), isFalse);

    entry
      ..acquisitionSource = 'Breeder'
      ..vaccination = 'Unknown'
      ..spayNeuter = 'No';
    entry.ageController.text = '3 years old';
    entry.stayDurationController.text = '2 years';
    expect(entry.isAssessmentComplete(isSurrender: true), isFalse);
    entry.compatibility.add(kSurrenderCompatibilityUnknown);
    expect(entry.isAssessmentComplete(isSurrender: true), isTrue);
    expect(entry.hasCompleteAssessment, isFalse);
  });

  test('neglect cards need harm signs and medical attention', () {
    final entry = FoundAnimalEntry()
      ..injury = kInjuryNone
      ..bodyCondition = 'a'
      ..mobility = 'a'
      ..alertness = 'a'
      ..eyesNoseMouth = 'a'
      ..skinAndCoat = 'a'
      ..appetiteHydration = 'a'
      ..biteRisk = 'Low'
      ..escapeRisk = 'Low';
    addTearDown(entry.dispose);
    entry.behavior.add('Calm');
    entry.environmentSafety.add('Exposed to sun or rain');
    expect(entry.hasCompleteAssessment, isTrue);
    expect(entry.isAssessmentComplete(requireVisibleSigns: true), isFalse);
    entry.visibleSigns.add(kNeglectSignsNone);
    expect(entry.isAssessmentComplete(requireVisibleSigns: true), isFalse);
    entry.needsMedical = 'Not sure';
    expect(entry.isAssessmentComplete(requireVisibleSigns: true), isTrue);
  });

  test('injury, illness and neglect ask visible signs; others do not', () {
    expect(
      visibleSignsOptionsFor('Injury'),
      contains('Likely hit by a vehicle'),
    );
    expect(visibleSignsOptionsFor('Illness'), contains('Vomiting'));
    expect(visibleSignsOptionsFor('Neglect or Abuse'), isNotNull);
    expect(visibleSignsOptionsFor('Abandonment'), isNull);
    expect(visibleSignsOptionsFor('Pet Surrender'), isNull);
    expect(visibleSignsLabelFor('Illness'), 'Visible signs of illness');
    final form = _form()..selectedRescueType = 'Injury';
    expect(form.asksVisibleSigns, isTrue);
    form.selectedRescueType = 'Abandonment';
    expect(form.asksVisibleSigns, isFalse);
  });

  test('aggressive animal gets its own signs, environment and question', () {
    expect(
      visibleSignsOptionsFor('Aggressive Animal'),
      kAggressionSignsOptions,
    );
    expect(
      visibleSignsLabelFor('Aggressive Animal'),
      'Visible signs of aggression',
    );
    expect(
      environmentExtrasFor('Aggressive Animal'),
      kAggressiveEnvironmentOptions,
    );
    expect(environmentExtrasFor('Injury'), kNeglectEnvironmentOptions);
    expect(environmentExtrasFor('Abandonment'), isEmpty);
    expect(
      medicalQuestionFor('Aggressive Animal'),
      contains('injured or sick'),
    );
    final form = _form()..selectedRescueType = 'Aggressive Animal';
    expect(form.asksVisibleSigns, isTrue);
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

  group('registered collar-tag pet on the owner form', () {
    test('picking a pet fills the owner fields', () {
      final form = _form()..isOwner = true;
      form.applyCollarTag(CollarTagData(
        tagId: 't1',
        name: 'Bantay',
        breed: 'Dog - Aspin',
        sex: 'M',
        colorMarkings: 'Brown with white chest',
        ownerMobile: '+639171234567',
        petImageUrl: 'https://example.com/bantay.jpg',
      ));
      expect(form.linkedCollarTag?.tagId, 't1');
      expect(form.petNameController.text, 'Bantay');
      expect(form.selectedAnimalType, kDogSpecies);
      expect(form.lostBreedText, 'Aspin');
      expect(form.lostSex, 'Male');
      expect(form.lostColorController.text, 'Brown with white chest');
      expect(form.ownerContactController.text, '+639171234567');
    });

    test('a breed not on the list goes to Others with its name', () {
      final form = _form()..isOwner = true;
      form.applyCollarTag(CollarTagData(tagId: 't2', name: 'Kit', breed: 'Cat - Munchkin X'));
      expect(form.selectedAnimalType, kCatSpecies);
      expect(form.lostBreed, kOthersBreedLabel);
      expect(form.lostBreedText, 'Munchkin X');
    });

    test("the tag's photo counts as the report's photo", () {
      final form = _form()..isOwner = true;
      form.applyCollarTag(CollarTagData(
        tagId: 't1',
        name: 'Bantay',
        breed: 'Dog - Aspin',
        colorMarkings: 'Brown',
        ownerMobile: '+639171234567',
        petImageUrl: 'https://example.com/bantay.jpg',
      ));
      form.lastSeenDate = DateTime(2026, 11, 20);
      expect(form.validateLostPetReport(), isNull);

      form.linkedCollarTag = null;
      expect(form.validateLostPetReport(), 'Please add at least 1 photo.');
    });
  });

  group('owned-pet behavior', () {
    test('the owner form asks how the pet usually acts, not stray behavior', () {
      expect(kOwnedPetBehaviorOptions, contains('Comes when called'));
      expect(kOwnedPetBehaviorOptions, isNot(contains('Protecting young')));
      expect(kOwnedPetBehaviorOptions, isNot(contains('Hard to approach')));
    });

    test('conflicting choices exclude each other both ways', () {
      kOwnedPetBehaviorConflicts.forEach((option, others) {
        expect(kOwnedPetBehaviorOptions, contains(option));
        for (final other in others) {
          expect(kOwnedPetBehaviorConflicts[other], contains(option),
              reason: '$other should also clear $option');
        }
      });
    });
  });

  group('organization involvement', () {
    test('surrender: no organization coordination and no urgency', () {
      final form = _form()..selectedRescueType = kRescueTypePetSurrender;
      form.foundAnimals.first.species = kDogSpecies;
      expect(form.asksOrgCoordination, isFalse);
      expect(form.urgencyAssessment, isNull);
      expect(form.orgInvolvement, OrgInvolvement.notFacilitated);
    });

    test('other rescue types keep organization involvement', () {
      for (final type in ['Abandonment', 'Illness', 'Injury', 'Aggressive Animal']) {
        final form = _form()..selectedRescueType = type;
        expect(form.asksOrgCoordination, isTrue, reason: type);
        expect(form.orgInvolvement, OrgInvolvement.orgAssist, reason: type);
      }
    });

    test('stray report urgency is assessed from the animal answers', () {
      final form = _form()..selectedRescueType = 'Injury';
      final a = form.foundAnimals.first
        ..species = kDogSpecies
        ..injury = kInjuryMinor
        ..mobility = kMobilityOptions[0]
        ..alertness = kAlertnessOptions[0]
        ..bodyCondition = kBodyConditionOptions[1];
      expect(form.urgencyAssessment!.level, kUrgencyLow);
      a.visibleSigns.add('Active or heavy bleeding');
      expect(form.urgencyAssessment!.level, kUrgencyCritical);
    });
  });

  group('neglect or abuse paths', () {
    RescueFormController abuseReady() {
      final form = _form()
        ..selectedRescueType = kNeglectAbuseType
        ..neglectHappeningNow = 'No'
        ..neglectOwnerKnown = 'Yes'
        ..neglectFrequency = 'Ongoing for weeks or longer'
        ..neglectReportedToAuthorities = 'Yes'
        ..neglectWillingWitness = 'Yes'
        ..neglectOtherWitness = 'No';
      form.neglectObserved.add(kNeglectObservedAbandoned);
      form.conditionController.text = 'Chained without water';
      form.foundAnimals.first.species = kDogSpecies;
      return form;
    }

    test('can be reported before or without the coverage check', () {
      final form = abuseReady();
      expect(form.orgInvolvement, OrgInvolvement.orgAssist);
      expect(form.validateRescueReport(), isNull);
    });

    test('inside coverage asks the organization; no stray-rescue questions', () {
      final form = abuseReady()..applyAbuseCoverage(true, ['Paws Org']);
      expect(form.abuseReportPath, kAbusePathOrgAssistance);
      expect(form.asksOrgCoordination, isFalse);
      expect(form.asksOnSite, isFalse);
      expect(form.validateRescueReport(), isNull);
    });

    test('outside coverage is still reported to the organizations', () {
      final form = abuseReady()..applyAbuseCoverage(false);
      expect(form.abuseAreaCovered, isFalse);
      expect(form.orgInvolvement, OrgInvolvement.orgAssist);
      expect(form.validateRescueReport(), isNull);
      expect(form.urgencyAssessment, isNotNull);
    });

    test('a stale independent choice does not leak into another type', () {
      final form = abuseReady()
        ..abuseReportPath = kAbusePathIndependent
        ..selectedRescueType = 'Injury';
      expect(form.orgInvolvement, OrgInvolvement.orgAssist);
      expect(form.isIndependentAbuseReport, isFalse);
    });
  });

  group('female questions and injury', () {
    FoundAnimalEntry complete() {
      final entry = FoundAnimalEntry()
        ..species = kDogSpecies
        ..injury = kInjuryNone
        ..bodyCondition = kBodyConditionOptions[1]
        ..mobility = kMobilityOptions[0]
        ..alertness = kAlertnessOptions[0]
        ..eyesNoseMouth = kEyesNoseMouthOptions[0]
        ..skinAndCoat = kSkinAndCoatOptions[0]
        ..appetiteHydration = 'Eating/drinking normally'
        ..biteRisk = 'Low'
        ..escapeRisk = 'Low'
        ..sex = 'Male';
      entry.behavior.add('Calm');
      entry.environmentSafety.add('Safe Location');
      addTearDown(entry.dispose);
      return entry;
    }

    test('litter and pregnancy answers are required only for a female animal', () {
      final entry = complete();
      expect(entry.hasCompleteAssessment, isTrue);
      entry.sex = 'Female';
      expect(entry.hasCompleteAssessment, isFalse);
      entry
        ..hasLitter = 'No'
        ..suspectedPregnancy = kSuspectedPregnancyOptions[0];
      expect(entry.hasCompleteAssessment, isTrue);
    });

    test('changing sex away from Female clears litter and pregnancy answers', () {
      final entry = complete()
        ..sex = 'Female'
        ..hasLitter = 'Yes'
        ..suspectedPregnancy = kSuspectedPregnancyOptions[0];
      entry.sex = 'Male';
      expect(entry.hasLitter, isNull);
      expect(entry.suspectedPregnancy, isNull);
      entry.sex = 'Female';
      expect(entry.hasLitter, isNull, reason: 'no stale answer comes back');
    });

    test('the injury answer is required on rescue reports, not on surrenders', () {
      final entry = complete()..injury = null;
      expect(entry.hasCompleteAssessment, isFalse);
      entry.injury = kInjuryModerate;
      expect(entry.hasCompleteAssessment, isFalse, reason: 'photo question pending');
      entry.injuryVisibleInPhotos = kInjuryPhotoOptions[0];
      expect(entry.hasCompleteAssessment, isTrue);
      entry.injury = kInjuryNone;
      expect(entry.injuryVisibleInPhotos, isNull);
    });
  });
}
