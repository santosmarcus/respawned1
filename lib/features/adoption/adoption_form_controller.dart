// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/features/adoption/interview_scheduling.dart';

// Dropdown, not freeform text — a small closed set of real answers, same
// reasoning as the rest of this form's radio questions.
const List<String> kCaregiverOptions = ['Me', 'Family', 'Housekeeper'];

/// Everything the applicant enters across the adoption steps (the form, the
/// uploads, the agreements and the interview appointment). Owned by
/// `_AdoptionProcessState`, which still rebuilds with `setState`; this class
/// only holds the values so each step can live in its own widget.
class AdoptionFormController {
  // Form fields
  final formKey = GlobalKey<FormState>();

  // Personal Information
  final nameCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final homeAddressCtrl = TextEditingController();

  // Household & Living Information
  String? residenceType;
  final residenceOtherCtrl = TextEditingController();
  String? ownershipStatus;
  int householdMembers = 0;

  //Pet Experience
  bool hadPetsBefore = false;
  int currentDogs = 0;
  int currentCats = 0;
  int currentBirds = 0;
  int currentFish = 0;
  int currentReptiles = 0;
  int currentOther = 0;
  final currentOtherTypeCtrl = TextEditingController();
  String? petsVaccinated;
  String? petsSpayedNeutered;

  //Lifestyle & Care
  String? hoursAlone;
  // Dropdown, not freeform text — a small closed set of real answers, same
  // reasoning as the rest of this form's radio questions.
  String? primaryCaregiver;
  String? petStayLocation;
  bool canAffordFood = false;
  bool canAffordVaccinations = false;
  bool canAffordVetVisits = false;
  bool canAffordEmergencyCare = false;
  bool canAffordGrooming = false;
  bool canAffordCareSupplies = false;
  final reasonCtrl = TextEditingController();

  //Required Uploads
  File? governmentIdFile;
  File? proofOfAddressFile;
  //File? _digitalSignatureFile;
  // Home Photos supports multiple images — a newly-picked list plus,
  // when resuming an in-progress application, whatever was already
  // uploaded in an earlier session (kept separate so removing one only
  // removes that one, exactly like CreateAnimalRecordPage's own
  // existing/newly-picked image split).
  final List<File> homePhotosFiles = [];
  List<String> existingHomePhotoUrls = [];

  String? governmentIdUrl;
  String? proofOfAddressUrl;
  //String? _digitalSignatureUrl;

  bool isUploadingGovId = false;
  bool isUploadingProof = false;
  bool isUploadingSignature = false;
  bool isUploadingHomePhotos = false;

  // Agreements
  bool agreeCare = false;
  bool agreeNoAbandon = false;
  bool agreeFollowup = false;
  bool agreeAccurate = false;
  bool agreeNotGuaranteed = false;

  // Appointment
  DateTime? appointmentDate;
  String appointmentType = 'On-site Visit';
  String? appointmentTime;

  // Interview visit types + day-of-week time slots — now the shared
  // interview_scheduling.dart source of truth (also used by the admin's
  // Reschedule action), not a copy private to this screen.
  List<String> get slotsForDate {
    if (appointmentDate == null) return [];
    return interviewSlotsForDate(appointmentDate!);
  }

  /// Prefills the contact fields from the signed-in user's `users/{uid}`
  /// doc ([authEmail] wins over the doc's own email).
  void fillFromAccount(Map<String, dynamic> data, {String? authEmail}) {
    nameCtrl.text = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
        .trim();
    phoneCtrl.text = data['phone'] ?? '';
    emailCtrl.text = authEmail ?? data['email'] ?? '';
    homeAddressCtrl.text =
        data['homeAddress']?.toString() ??
        data['address']?.toString() ??
        data['city']?.toString() ??
        '';
  }

  /// Reloads every saved answer from an `adoptions/{id}` doc.
  void applySavedApplication(Map<String, dynamic> data) {
    final personal = (data['personal'] as Map?) ?? {};
    final household = (data['household'] as Map?) ?? {};
    final petExperience = (data['petExperience'] as Map?) ?? {};
    final currentPets = (petExperience['currentPets'] as Map?) ?? {};
    final lifestyle = (data['lifestyle'] as Map?) ?? {};
    final canAfford = (lifestyle['canAfford'] as Map?) ?? {};
    final uploads = (data['uploads'] as Map?) ?? {};
    final agreement = (data['agreement'] as Map?) ?? {};

    // Personal Information
    nameCtrl.text = personal['adopterName'] as String? ?? '';
    emailCtrl.text = personal['adopterEmail'] as String? ?? '';
    ageCtrl.text = personal['adopterAge'] as String? ?? '';
    phoneCtrl.text = personal['adopterPhone'] as String? ?? '';
    homeAddressCtrl.text =
        personal['homeAddress']?.toString() ??
        personal['adopterHomeAddress']?.toString() ??
        personal['adopterCity']?.toString() ??
        '';

    // Household & Living Information
    residenceType = household['residenceType'] as String?;
    residenceOtherCtrl.text = household['residenceOther'] as String? ?? '';
    ownershipStatus = household['ownershipStatus'] as String?;
    householdMembers = household['householdMembers'] as int? ?? 0;

    // Pet Experience
    hadPetsBefore = petExperience['hadPetsBefore'] as bool? ?? false;
    currentDogs = currentPets['dogs'] as int? ?? 0;
    currentCats = currentPets['cats'] as int? ?? 0;
    currentBirds = currentPets['birds'] as int? ?? 0;
    currentFish = currentPets['fish'] as int? ?? 0;
    currentReptiles = currentPets['reptiles'] as int? ?? 0;
    currentOther = currentPets['other'] as int? ?? 0;
    currentOtherTypeCtrl.text = currentPets['otherType'] as String? ?? '';
    petsVaccinated = petExperience['currentPetsVaccinated'] as String?;
    petsSpayedNeutered = petExperience['currentPetsSpayedNeutered'] as String?;

    // Lifestyle & Care
    hoursAlone = lifestyle['hoursAlone'] as String?;
    // Only accepted if it matches one of the dropdown's own options —
    // an older application may have freeform text here from before
    // this became a closed set; that legacy value just isn't
    // preselected rather than being force-mapped to a guess.
    final savedCaregiver = lifestyle['primaryCaregiver'] as String?;
    primaryCaregiver = kCaregiverOptions.contains(savedCaregiver)
        ? savedCaregiver
        : null;
    petStayLocation = lifestyle['petStayLocation'] as String?;
    canAffordFood = canAfford['food'] as bool? ?? false;
    canAffordVaccinations = canAfford['vaccinations'] as bool? ?? false;
    canAffordVetVisits = canAfford['vetVisits'] as bool? ?? false;
    canAffordEmergencyCare =
        canAfford['emergencyMedicalCare'] as bool? ?? false;
    canAffordGrooming = canAfford['grooming'] as bool? ?? false;
    canAffordCareSupplies = canAfford['careSupplies'] as bool? ?? false;
    reasonCtrl.text = agreement['reason'] as String? ?? '';

    // Required Uploads (already uploaded — keep the saved URLs)
    governmentIdUrl = uploads['governmentId'] as String?;
    proofOfAddressUrl = uploads['proofOfAddress'] as String?;
    //_digitalSignatureUrl = uploads['digitalSignature'] as String?;
    // homePhotos may be a single legacy String or the current List —
    // same dual-shape tolerance the admin document reader already has.
    final homePhotosRaw = uploads['homePhotos'];
    existingHomePhotoUrls = homePhotosRaw is List
        ? homePhotosRaw.whereType<String>().toList()
        : (homePhotosRaw is String && homePhotosRaw.isNotEmpty
              ? [homePhotosRaw]
              : []);

    // Agreements
    agreeCare = agreement['care'] as bool? ?? false;
    agreeNoAbandon = agreement['noAbandon'] as bool? ?? false;
    agreeFollowup = agreement['followUp'] as bool? ?? false;
    agreeAccurate = agreement['infoAccurate'] as bool? ?? false;
    agreeNotGuaranteed = agreement['approvalNotGuaranteed'] as bool? ?? false;

    // Appointment
    final appointmentTs = data['appointmentDate'];
    if (appointmentTs is Timestamp) {
      appointmentDate = appointmentTs.toDate();
    }
    appointmentType = data['appointmentType'] as String? ?? appointmentType;
    appointmentTime = data['appointmentTime'] as String?;
  }

  /// Radio questions and the caregiver dropdown aren't FormFields, so
  /// `formKey.validate()` never sees them — these are the unanswered ones.
  List<String> missingRequiredAnswers() => [
    if (residenceType == null) 'Residence Type',
    if (ownershipStatus == null) 'Ownership Status',
    if (petsVaccinated == null) 'current pets vaccinated status',
    if (petsSpayedNeutered == null) 'current pets spayed/neutered status',
    if (hoursAlone == null) 'hours animal will be left alone',
    if (primaryCaregiver == null) 'Primary Caregiver',
    if (petStayLocation == null) 'where pet will stay',
  ];

  bool get allAgreementsAccepted =>
      agreeCare &&
      agreeNoAbandon &&
      agreeFollowup &&
      agreeAccurate &&
      agreeNotGuaranteed;

  /// Clears every answer back to a blank application (contact details are
  /// kept, as before).
  void reset() {
    residenceType = null;
    residenceOtherCtrl.clear();
    ownershipStatus = null;
    householdMembers = 0;

    hadPetsBefore = false;
    currentDogs = 0;
    currentCats = 0;
    currentBirds = 0;
    currentFish = 0;
    currentReptiles = 0;
    currentOther = 0;
    currentOtherTypeCtrl.clear();
    petsVaccinated = null;
    petsSpayedNeutered = null;

    hoursAlone = null;
    primaryCaregiver = null;
    petStayLocation = null;
    canAffordFood = false;
    canAffordVaccinations = false;
    canAffordVetVisits = false;
    canAffordEmergencyCare = false;
    canAffordGrooming = false;
    canAffordCareSupplies = false;
    reasonCtrl.clear();

    governmentIdFile = null;
    proofOfAddressFile = null;
    //_digitalSignatureFile = null;
    homePhotosFiles.clear();
    existingHomePhotoUrls = [];
    governmentIdUrl = null;
    proofOfAddressUrl = null;
    //_digitalSignatureUrl = null;

    agreeCare = false;
    agreeNoAbandon = false;
    agreeFollowup = false;
    agreeAccurate = false;
    agreeNotGuaranteed = false;

    appointmentDate = null;
    appointmentType = 'On-site Visit';
    appointmentTime = null;
  }

  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    homeAddressCtrl.dispose();
    residenceOtherCtrl.dispose();
    currentOtherTypeCtrl.dispose();
    reasonCtrl.dispose();
  }
}
