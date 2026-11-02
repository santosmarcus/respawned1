// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// One media slot (photo or video) picked for the report.
class RescueMediaItem {
  final XFile file;
  final bool isVideo;

  RescueMediaItem({required this.file, required this.isVideo});
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

  // Scroll target + error-highlight flag for this animal's card — set on a
  // failed submit so the form can scroll to and visually flag exactly
  // which animal still needs its Health & Behavior Assessment completed,
  // never all of them at once.
  final GlobalKey cardKey = GlobalKey();
  bool hasAssessmentError = false;

  bool get hasCompleteAssessment =>
      bodyCondition != null &&
      mobility != null &&
      alertness != null &&
      eyesNoseMouth != null &&
      skinAndCoat != null &&
      appetiteHydration != null &&
      behavior.isNotEmpty &&
      environmentSafety.isNotEmpty &&
      biteRisk != null &&
      escapeRisk != null;

  void dispose() {
    breedOtherController.dispose();
    colorController.dispose();
    environmentSafetyOtherController.dispose();
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
  final TextEditingController surrenderDurationController =
      TextEditingController();
  final TextEditingController surrenderAgeController = TextEditingController();
  String? surrenderReason;
  final TextEditingController surrenderReasonOtherController =
      TextEditingController();
  final TextEditingController surrenderExplanationController =
      TextEditingController();
  String? petAcquisitionSource;

  // Only these reasons need the reporter to explain what's actually wrong
  // and what they've already tried — a plain checkbox reason isn't enough
  // for staff to assess these two specifically.
  bool get surrenderNeedsExplanation =>
      surrenderReason == 'Medical issues (pet)' ||
      surrenderReason == 'Behavioral issues';

  // Once the pet came from another rescue org, this flow is meant to stop
  // here and redirect the owner back to that org rather than collect a
  // full surrender case for this one.
  bool get isRescueOrgAcquisition => petAcquisitionSource == 'Rescue Org';

  // Finder-side: one card per animal found (supports a multi-animal group case)
  final List<FoundAnimalEntry> foundAnimals = [FoundAnimalEntry()];
  final TextEditingController finderContactController = TextEditingController();
  String? animalStatus; // 'with_finder' | 'still_roaming' | 'brought_to_vet'
  bool finderNeedsRescue = false;

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
          surrenderDurationController.text.trim().isEmpty ||
          surrenderAgeController.text.trim().isEmpty ||
          surrenderReason == null ||
          petAcquisitionSource == null) {
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
      if (hasEmptySpecies ||
          conditionController.text.trim().isEmpty ||
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
    surrenderDurationController.dispose();
    surrenderAgeController.dispose();
    surrenderReasonOtherController.dispose();
    surrenderExplanationController.dispose();
    for (final a in foundAnimals) {
      a.dispose();
    }
  }
}
