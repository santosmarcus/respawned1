// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// One media slot (photo or video) picked for the report.
class RescueMediaItem {
  final XFile file;
  final bool isVideo;

  /// Taken with the camera inside the report form, rather than picked from
  /// the gallery. Saved with the report as evidence for staff.
  final bool fromCamera;

  RescueMediaItem({required this.file, required this.isVideo, this.fromCamera = false});
}

/// One animal in a (possibly multi-animal) report.
class FoundAnimalEntry {
  String? species; // 'Dog' | 'Cat'
  String? breed; // one of breedOptionsFor(species), or kOthersBreedLabel
  final TextEditingController breedOtherController = TextEditingController();
  final TextEditingController colorController = TextEditingController();
  String? sex;
  String? size;

  // Health & Behavior Assessment — per animal, never applied across other
  // animals in the same multi-animal report; each entry owns its own
  // values. See core/utils/animal_health_assessment.dart for each field's
  // option list. Single-select:
  String? bodyCondition;
  String? mobility;
  String? alertness;
  String? eyesNoseMouth;
  String? skinAndCoat;
  String? appetiteHydration;
  // Multi-select:
  final Set<String> behavior = {};
  // Multi-select + reporter-added custom entries beyond the predefined
  // list (see EnvironmentSafetySection).
  final Set<String> environmentSafety = {};
  final TextEditingController environmentSafetyOtherController =
  TextEditingController();

  // Per-animal safety risk — never applied across other animals in the
  // same multi-animal report; each entry owns its own values.
  String? biteRisk;
  String? escapeRisk;

  // Injury, Illness and Neglect or Abuse — asked per animal inside its
  // card (see visibleSignsOptionsFor).
  final Set<String> visibleSigns = {};
  String? needsMedical;

  // Pet Surrender only — asked per animal inside its card.
  final TextEditingController ageController = TextEditingController();
  final TextEditingController stayDurationController = TextEditingController();
  String? acquisitionSource;
  String? vaccination;
  String? spayNeuter;
  final Set<String> compatibility = {};

  /// Came from another rescue org: the surrender flow stops and the owner
  /// is redirected back to that org instead.
  bool get isRescueOrgAcquisition => acquisitionSource == 'Rescue Org';

  // Scroll target + error-highlight flag for this animal's card — set on a
  // failed submit so the form can scroll to and visually flag exactly
  // which animal still needs its Health & Behavior Assessment completed,
  // never all of them at once.
  final GlobalKey cardKey = GlobalKey();
  bool hasAssessmentError = false;

  /// Whether this animal's card is open. Only matters when the report has
  /// two or more animals: the card being filled stays open and the rest
  /// collapse to their header until tapped.
  bool expanded = true;

  bool get hasCompleteAssessment => isAssessmentComplete();

  /// Whether every field in this animal's card is answered. On Pet
  /// Surrender ([isSurrender]) Environment and Safety is hidden (the owner
  /// has the pet at home) and the surrender questions are required instead.
  bool isAssessmentComplete({
    bool isSurrender = false,
    bool requireVisibleSigns = false,
  }) =>
      (!requireVisibleSigns ||
          (visibleSigns.isNotEmpty && needsMedical != null)) &&
          bodyCondition != null &&
          mobility != null &&
          alertness != null &&
          eyesNoseMouth != null &&
          skinAndCoat != null &&
          appetiteHydration != null &&
          behavior.isNotEmpty &&
          biteRisk != null &&
          escapeRisk != null &&
          (isSurrender ? hasSurrenderDetails : environmentSafety.isNotEmpty);

  bool get hasSurrenderDetails =>
      ageController.text.trim().isNotEmpty &&
          stayDurationController.text.trim().isNotEmpty &&
          acquisitionSource != null &&
          vaccination != null &&
          spayNeuter != null &&
          compatibility.isNotEmpty;

  void dispose() {
    breedOtherController.dispose();
    colorController.dispose();
    environmentSafetyOtherController.dispose();
    ageController.dispose();
    stayDurationController.dispose();
  }

  String get speciesText => species ?? '';
  String get breedText {
    if (breed == null) return '';
    return breed == kOthersBreedLabel
        ? breedOtherController.text.trim()
        : breed!;
  }
}

/// All user-entered state of the Report a Stray form, plus the form's
/// validation rules. Owned by `_RescuePageState`, which still drives
/// rebuilds with `setState` exactly as before; this class only holds the
/// values so the page's sections can be split into separate widgets.
///
/// Location state (the map pin and its resolved address) stays on the page
/// because it is tied to the map controller and geocoding lifecycle.
class RescueFormController {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController conditionController = TextEditingController();
  final TextEditingController witnessNameController = TextEditingController();
  final TextEditingController witnessNumberController = TextEditingController();
  final TextEditingController accessInstructionsController =
  TextEditingController();
  final TextEditingController bestTimeContactController =
  TextEditingController();

  String? selectedUrgency;
  String? selectedRescueType;
  String? coordinateChoice;
  String? adoptionChoice;
  // Only asked/answered when adoptionChoice == 'yes' — resets to false if
  // the reporter changes their mind and un-checks Yes, so a stale consent
  // never survives under a "No" answer.
  bool adoptionCommitmentAccepted = false;
  String? selectedAnimalType;

  // Additional stray-rescue triage questions
  String? onSiteChoice; // 'yes' | 'no'
  bool reportAnonymously = false;

  /// Analytics gap 5: the cat lives outdoors in the community with no
  /// owner. Only asked when a cat is reported on a stray report.
  bool communityCat = false;
  bool get asksCommunityCat => !isPetSurrenderType && !isLostPetType && validAnimals.any((a) => a.species == 'Cat');

  bool? isOwner;
  String? scannedTagId;

  // Owner-side controllers
  final TextEditingController petNameController = TextEditingController();
  String? lostBreed;
  final TextEditingController lostBreedOtherController =
  TextEditingController();
  final TextEditingController lostColorController = TextEditingController();
  DateTime? lastSeenDate;
  TimeOfDay? lastSeenTime;
  final TextEditingController rewardAmountController = TextEditingController();
  final TextEditingController ownerContactController = TextEditingController();
  String? lostSex;
  String? temperament;
  bool offerReward = false;

  String get lostBreedText {
    if (lostBreed == null) return '';
    return lostBreed == kOthersBreedLabel
        ? lostBreedOtherController.text.trim()
        : lostBreed!;
  }

  // Pet Surrender — its own distinct question set (see SurrenderFields).
  // Age, stay, acquisition, vaccination, spay/neuter and compatibility are
  // asked per animal (FoundAnimalEntry).
  String? surrenderReason;
  final TextEditingController surrenderReasonOtherController =
  TextEditingController();
  final TextEditingController surrenderExplanationController =
  TextEditingController();
  String? surrenderTimeline;

  /// Optional photos of vaccination cards or vet records (Pet Surrender).
  final List<XFile> vetRecordPhotos = [];

  /// The reporter's declaration that the report is truthful and accurate.
  /// Required before any report type is submitted.
  bool truthfulnessDeclared = false;

  // Only these reasons need the reporter to explain what's actually wrong
  // and what they've already tried — a plain checkbox reason isn't enough
  // for staff to assess these two specifically.
  bool get surrenderNeedsExplanation =>
      surrenderReason == 'Medical issues (pet)' ||
          surrenderReason == 'Behavioral issues';

  // Once the pet came from another rescue org, this flow is meant to stop
  // here and redirect the owner back to that org rather than collect a
  // full surrender case for this one.
  bool get isRescueOrgAcquisition =>
      foundAnimals.any((a) => a.isRescueOrgAcquisition);

  // Finder-side: one card per animal found (supports a multi-animal group case)
  final List<FoundAnimalEntry> foundAnimals = [FoundAnimalEntry()];
  final TextEditingController finderContactController = TextEditingController();
  String? animalStatus; // 'with_finder' | 'still_roaming' | 'brought_to_vet'
  bool finderNeedsRescue = false;

  // Abandonment — follow-up questions (see AbandonmentFields).
  String? abandonmentDuration;
  String? abandonmentLocation;
  final TextEditingController abandonmentLocationOtherController =
  TextEditingController();
  String? abandonmentFoodWater;
  String? abandonmentCanProvideFood;
  String? abandonmentWitness;
  final TextEditingController abandonmentWitnessDetailsController =
  TextEditingController();
  String? abandonmentBelongings;
  final TextEditingController abandonmentBelongingsDetailsController =
  TextEditingController();

  bool get isAbandonmentType => selectedRescueType == kAbandonmentType;

  // Neglect or Abuse — follow-up questions (see NeglectAbuseFields).
  final Set<String> neglectObserved = {};
  final TextEditingController neglectObservedOtherController =
  TextEditingController();
  String? neglectHappeningNow;
  String? neglectOwnerKnown;
  final TextEditingController neglectOwnerDetailsController =
  TextEditingController();
  String? neglectFrequency;
  String? neglectReportedToAuthorities;
  final TextEditingController neglectReportReferenceController =
  TextEditingController();
  String? neglectWillingWitness;

  bool get isNeglectAbuseType => selectedRescueType == kNeglectAbuseType;

  /// Injury, Illness and Neglect or Abuse ask each animal's visible signs
  /// and whether it needs immediate medical attention.
  bool get asksVisibleSigns =>
      visibleSignsOptionsFor(selectedRescueType) != null;

  /// Only asked when the animal may be without food or water.
  bool get asksAbandonmentCanProvideFood =>
      abandonmentFoodWater != null && abandonmentFoodWater != 'Yes';

  bool get isLostPetType => selectedRescueType == 'Lost Pet';
  bool get isPetSurrenderType => selectedRescueType == 'Pet Surrender';

  final List<RescueMediaItem?> mediaFiles = [null, null, null, null];
  final List<double?> uploadProgress = [null, null, null, null];

  int get filledMediaCount => mediaFiles.where((f) => f != null).length;

  /// Animals with a species picked — the ones actually submitted.
  List<FoundAnimalEntry> get validAnimals =>
      foundAnimals.where((a) => a.speciesText.isNotEmpty).toList();

  /// The typed search address if any, otherwise the map pin's address.
  String resolvedAddress(String pinnedAddress) =>
      addressController.text.trim().isEmpty
          ? pinnedAddress
          : addressController.text.trim();

  /// Required-field checks for a stray / surrender report, in the same
  /// order as before. Returns the message to show, or null when valid.
  /// The per-animal Health & Behavior Assessment and the media-count check
  /// are handled separately by the page (they highlight/scroll or toggle
  /// the loading state).
  String? validateRescueReport() {
    final condition = conditionController.text.trim();
    final valid = validAnimals;

    if (isPetSurrenderType) {
      if (condition.isEmpty ||
          selectedUrgency == null ||
          valid.isEmpty ||
          surrenderReason == null ||
          surrenderTimeline == null) {
        return 'Please fill in all required fields.';
      }
      if (surrenderReason == 'Other (please specify)' &&
          surrenderReasonOtherController.text.trim().isEmpty) {
        return 'Please specify the reason for surrendering.';
      }
      if (surrenderNeedsExplanation &&
          surrenderExplanationController.text.trim().isEmpty) {
        return 'Please explain the issue and what you\'ve tried.';
      }
    } else if (condition.isEmpty ||
        selectedRescueType == null ||
        selectedUrgency == null ||
        valid.isEmpty ||
        onSiteChoice == null ||
        coordinateChoice == null ||
        adoptionChoice == null) {
      return 'Please fill in all required fields.';
    }

    if (isAbandonmentType &&
        (abandonmentDuration == null ||
            abandonmentLocation == null ||
            abandonmentFoodWater == null ||
            (asksAbandonmentCanProvideFood &&
                abandonmentCanProvideFood == null) ||
            abandonmentWitness == null ||
            abandonmentBelongings == null)) {
      return 'Please fill in all required fields.';
    }
    if (isNeglectAbuseType) {
      if (neglectObserved.isEmpty ||
          neglectHappeningNow == null ||
          neglectOwnerKnown == null ||
          neglectFrequency == null ||
          neglectReportedToAuthorities == null ||
          neglectWillingWitness == null) {
        return 'Please fill in all required fields.';
      }
      if (neglectObserved.contains(kNeglectObservedOther) &&
          neglectObservedOtherController.text.trim().isEmpty) {
        return 'Please describe what you are seeing.';
      }
    }

    if (isAbandonmentType &&
        abandonmentLocation == kAbandonmentLocationOther &&
        abandonmentLocationOtherController.text.trim().isEmpty) {
      return 'Please specify where the animal was left.';
    }

    if (!isPetSurrenderType &&
        adoptionChoice == 'yes' &&
        !adoptionCommitmentAccepted) {
      return 'Please agree to the adoption-interest terms before submitting.';
    }

    if (!isPetSurrenderType && coordinateChoice == 'no') {
      final witnessNameError = AppValidators.name(
        witnessNameController.text,
        fieldName: 'Witness name',
      );
      if (witnessNameError != null) return witnessNameError;
      final witnessPhoneError = AppValidators.phFlexiblePhone(
        witnessNumberController.text,
      );
      if (witnessPhoneError != null) return witnessPhoneError;
    }
    return null;
  }

  /// The truthfulness declaration every report type must accept before
  /// it is submitted. Returns the message to show, or null when accepted.
  String? validateDeclaration() => truthfulnessDeclared
      ? null
      : 'Please confirm that the information you provided is truthful and '
      'accurate.';

  /// Required-field checks for a Lost Pet report (owner or finder side), in
  /// the same order as before. Returns the message to show, or null.
  String? validateLostPetReport() {
    if (isOwner == null) {
      return 'Please tell us whether you are the owner.';
    }

    if (filledMediaCount < 1) {
      return 'Please add at least 1 photo.';
    }

    if (isOwner == true) {
      if (petNameController.text.trim().isEmpty ||
          selectedAnimalType == null ||
          lostColorController.text.trim().isEmpty ||
          lastSeenDate == null ||
          ownerContactController.text.trim().isEmpty) {
        return 'Please fill in all required fields.';
      }

      final ownerPhoneError = AppValidators.phFlexiblePhone(
        ownerContactController.text,
      );
      if (ownerPhoneError != null) return ownerPhoneError;

      if (offerReward) {
        final amountError = AppValidators.amount(
          rewardAmountController.text,
          fieldName: 'Reward amount',
        );
        if (amountError != null) return amountError;
      }
    } else {
      final hasEmptySpecies = foundAnimals.any((a) => a.speciesText.isEmpty);
      // No free-text condition on the finder side: each animal's Health &
      // Behavior Assessment (in its card) describes its condition.
      if (hasEmptySpecies ||
          animalStatus == null ||
          finderContactController.text.trim().isEmpty ||
          (finderNeedsRescue && selectedUrgency == null)) {
        return 'Please fill in all required fields.';
      }

      final finderPhoneError = AppValidators.phFlexiblePhone(
        finderContactController.text,
      );
      if (finderPhoneError != null) return finderPhoneError;
    }
    return null;
  }

  void dispose() {
    addressController.dispose();
    conditionController.dispose();
    witnessNameController.dispose();
    witnessNumberController.dispose();
    accessInstructionsController.dispose();
    bestTimeContactController.dispose();
    petNameController.dispose();
    lostBreedOtherController.dispose();
    lostColorController.dispose();
    rewardAmountController.dispose();
    ownerContactController.dispose();
    finderContactController.dispose();
    surrenderReasonOtherController.dispose();
    abandonmentWitnessDetailsController.dispose();
    abandonmentLocationOtherController.dispose();
    neglectObservedOtherController.dispose();
    neglectOwnerDetailsController.dispose();
    neglectReportReferenceController.dispose();
    abandonmentBelongingsDetailsController.dispose();
    surrenderExplanationController.dispose();
    for (final a in foundAnimals) {
      a.dispose();
    }
  }
}
