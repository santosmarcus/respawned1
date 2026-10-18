// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'dart:io';

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
