import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/adoption_fit_assessment.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

/// Current scoring rubric version — bump this (and nothing else needs to
/// change for callers) whenever the weights/rules below change, so stored
/// or cached results can be told apart from a fresh calculation. See the
/// class doc comment on why nothing is actually stored yet.
const int kFitAssessmentVersion = 1;

/// One place for every point weight (spec's own requirement) — change a
/// number here, nothing else in this file or its callers needs to change.
/// Every category's own weights sum to that category's total, and every
/// category total sums to 100.
class FitAssessmentWeights {
  FitAssessmentWeights._();

  static const int housingTotal = 20;
  static const int housingPermission = 8;
  static const int housingResidenceType = 6;
  static const int housingPetStayLocation = 6;

  static const int carePlanTotal = 20;
  static const int careCaregiver = 4;
  static const int careHoursAlone = 4;
  static const int careAgreementCare = 4;
  static const int careAgreementFollowUp = 4;
  static const int careAgreementNoAbandon = 4;

  static const int financialTotal = 20;
  static const int financialFood = 3;
  static const int financialCareSupplies = 3;
  static const int financialGrooming = 2;
  static const int financialVaccinations = 4;
  static const int financialVetVisits = 4;
  static const int financialEmergencyCare = 4;

  static const int currentPetTotal = 15;
  static const int currentPetExperience = 5;
  static const int currentPetVaccinated = 5;
  static const int currentPetSpayedNeutered = 5;

  static const int compatibilityTotal = 20;
  static const int compatibilityOtherPets = 6;
  static const int compatibilityFirstTimeOwner = 6;
  static const int compatibilityMedicalNeeds = 8;

  static const int documentsTotal = 5;
  static const int documentsGovernmentId = 2;
  static const int documentsProofOfAddress = 2;
  static const int documentsHomePhotos = 1;
}

/// Tracks one category's running score/max plus the shared
/// strengths/concerns/unassessed lists and the completeness counters, so
/// each `_score...` function below stays a short, readable list of rules
/// instead of repeating the same bookkeeping every time.
class _Tally {
  int score = 0;
  int max = 0;
  int evaluatedItems = 0;
  int totalItems = 0;
  final List<String> strengths = [];
  final List<String> concerns = [];
  final List<String> unassessed = [];

  /// A rule that doesn't apply to this application/animal at all (e.g. no
  /// current pets, so vaccination-of-current-pets can't be a concern) —
  /// awarded in full and counted as "assessed" (there was enough
  /// information to conclude the rule simply doesn't apply), never
  /// treated as a failure.
  void notApplicable(int points, int weight) {
    score += points;
    max += weight;
    evaluatedItems += 1;
    totalItems += 1;
  }

  /// A rule that does apply but the data needed to evaluate it wasn't on
  /// file — awards nothing, penalizes nothing beyond the missed points,
  /// and is surfaced under "Not assessed" rather than silently dropped.
  void unknown(int weight, String label) {
    max += weight;
    totalItems += 1;
    unassessed.add(label);
  }

  void satisfied(int weight, int max_, {String? strength}) {
    score += weight;
    max += max_;
    evaluatedItems += 1;
    totalItems += 1;
    if (strength != null) strengths.add(strength);
  }

  void failed(int max_, {String? concern}) {
    max += max_;
    evaluatedItems += 1;
    totalItems += 1;
    if (concern != null) concerns.add(concern);
  }
}

bool _looksLikeUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

/// Same shape-tolerance as
/// adoption_application_detail_page.dart's _DocumentsSection._urlsFor —
/// legacy applications wrote a single URL string, current ones write a
/// list; some very old entries nested the URL in a map. Reused logic, not
/// re-derived, so the two never disagree about what counts as "uploaded".
List<String> _urlsFor(dynamic value) {
  if (value == null) return const [];
  if (value is String) return _looksLikeUrl(value) ? [value] : const [];
  if (value is List) {
    final urls = <String>[];
    for (final item in value) {
      if (item is String && _looksLikeUrl(item)) {
        urls.add(item);
      } else if (item is Map) {
        final url = item['url'] ?? item['downloadUrl'] ?? item['imageUrl'];
        if (url is String && _looksLikeUrl(url)) urls.add(url);
      }
    }
    return urls;
  }
  return const [];
}

/// Calculates a transparent, rule-based Fit Assessment from the
/// application's own submitted form data (`household`/`petExperience`/
/// `lifestyle`/`agreement`/`uploads` — the exact nested structure
/// adoption_process.dart writes, traced directly rather than assumed) and
/// the selected animal's real AnimalRecord fields. No machine learning, no
/// speculative personality scoring — every point awarded or withheld maps
/// to one specific, readable rule below.
///
/// Deliberately NOT persisted to Firestore in this pass — recalculated
/// every time an admin opens the application, which is always correct by
/// construction (never a stale stored score) at the cost of doing the
/// (cheap, synchronous, no-network) arithmetic on every open. See this
/// feature's own report for what a future cached/versioned snapshot would
/// need.
AdoptionFitAssessment calculateFitAssessment({
  required AdoptionApplication application,
  required AnimalRecord animal,
}) {
  final raw = application.raw;
  final household = (raw['household'] as Map?) ?? const {};
  final petExperience = (raw['petExperience'] as Map?) ?? const {};
  final lifestyle = (raw['lifestyle'] as Map?) ?? const {};
  final agreement = (raw['agreement'] as Map?) ?? const {};
  final uploads = (raw['uploads'] as Map?) ?? const {};
  final canAfford = (lifestyle['canAfford'] as Map?) ?? const {};
  final currentPetsMap = (petExperience['currentPets'] as Map?) ?? const {};

  final housing = _scoreHousing(household, lifestyle);
  final carePlan = _scoreCarePlan(lifestyle, agreement);
  final financial = _scoreFinancial(canAfford);
  final currentPetReadiness = _scoreCurrentPetReadiness(petExperience, currentPetsMap);
  final compatibility = _scoreCompatibility(petExperience, currentPetsMap, canAfford, animal);
  final documents = _scoreDocuments(uploads);

  final tallies = [housing, carePlan, financial, currentPetReadiness, compatibility, documents];
  final totalScore = tallies.fold<int>(0, (sum, t) => sum + t.score);
  final totalEvaluated = tallies.fold<int>(0, (sum, t) => sum + t.evaluatedItems);
  final totalItems = tallies.fold<int>(0, (sum, t) => sum + t.totalItems);
  final completeness = totalItems == 0 ? 0 : ((totalEvaluated / totalItems) * 100).round();

  final categoryScores = [
    FitAssessmentCategoryScore(label: 'Housing and permission', score: housing.score, maxScore: FitAssessmentWeights.housingTotal),
    FitAssessmentCategoryScore(label: 'Care plan and commitment', score: carePlan.score, maxScore: FitAssessmentWeights.carePlanTotal),
    FitAssessmentCategoryScore(label: 'Financial care readiness', score: financial.score, maxScore: FitAssessmentWeights.financialTotal),
    FitAssessmentCategoryScore(label: 'Current-pet readiness', score: currentPetReadiness.score, maxScore: FitAssessmentWeights.currentPetTotal),
    FitAssessmentCategoryScore(label: 'Animal compatibility', score: compatibility.score, maxScore: FitAssessmentWeights.compatibilityTotal),
    FitAssessmentCategoryScore(label: 'Documents and completeness', score: documents.score, maxScore: FitAssessmentWeights.documentsTotal),
  ];

  final strengths = tallies.expand((t) => t.strengths).toList();
  final concerns = tallies.expand((t) => t.concerns).toList();
  final unassessedItems = tallies.expand((t) => t.unassessed).toList();

  // Too little usable information to say anything meaningful — never
  // manufacture a confident-looking score from mostly-missing data.
  final insufficientData = completeness < 30;

  return AdoptionFitAssessment(
    score: totalScore,
    band: FitAssessmentBand.fromScore(totalScore),
    completeness: completeness,
    categoryScores: categoryScores,
    strengths: strengths,
    concerns: concerns,
    unassessedItems: unassessedItems,
    version: kFitAssessmentVersion,
    calculatedAt: DateTime.now(),
    insufficientData: insufficientData,
  );
}

// ---- Housing and permission ------------------------------------------

/// `household.ownershipStatus`'s only real values in this app are 'Owned',
/// 'Renting (Allowed Pets)', and 'Living with Parents' — there is no
/// "renting without permission" option in the current adoption form (see
/// adoption_process.dart's own `_RadioGroup` options), so a
/// `landlordAllowsPets`-style conflict can never actually occur with
/// today's data; any answered value is treated as permission satisfied.
/// Only a genuinely unanswered field is "not assessed".
_Tally _scoreHousing(Map household, Map lifestyle) {
  final t = _Tally();
  final ownershipStatus = household['ownershipStatus'] as String?;
  if (ownershipStatus != null && ownershipStatus.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.housingPermission, FitAssessmentWeights.housingPermission,
        strength: 'Housing/ownership status was provided ($ownershipStatus).');
  } else {
    t.unknown(FitAssessmentWeights.housingPermission, 'Ownership status');
  }

  final residenceType = household['residenceType'] as String?;
  if (residenceType != null && residenceType.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.housingResidenceType, FitAssessmentWeights.housingResidenceType);
  } else {
    t.unknown(FitAssessmentWeights.housingResidenceType, 'Residence type');
  }

  final petStayLocation = lifestyle['petStayLocation'] as String?;
  if (petStayLocation != null && petStayLocation.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.housingPetStayLocation, FitAssessmentWeights.housingPetStayLocation);
  } else {
    t.unknown(FitAssessmentWeights.housingPetStayLocation, 'Where the pet will stay');
  }

  return t;
}

// ---- Care plan and commitment -----------------------------------------

/// primaryCaregiver's three options (Me/Family/Housekeeper) are treated as
/// equally valid — none scores higher than another, only whether the
/// question was actually answered.
_Tally _scoreCarePlan(Map lifestyle, Map agreement) {
  final t = _Tally();

  final caregiver = lifestyle['primaryCaregiver'] as String?;
  if (caregiver != null && caregiver.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.careCaregiver, FitAssessmentWeights.careCaregiver, strength: 'A primary caregiver ($caregiver) was identified.');
  } else {
    t.unknown(FitAssessmentWeights.careCaregiver, 'Primary caregiver');
  }

  // Never compared against an animal's care needs — no such field exists
  // on AnimalRecord today, so this is presence-only context, per the
  // spec's own instruction to avoid inventing a comparison that isn't
  // backed by real data.
  final hoursAlone = lifestyle['hoursAlone'] as String?;
  if (hoursAlone != null && hoursAlone.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.careHoursAlone, FitAssessmentWeights.careHoursAlone);
  } else {
    t.unknown(FitAssessmentWeights.careHoursAlone, 'Hours the animal will be left alone');
  }

  final care = agreement['care'] as bool?;
  if (care == true) {
    t.satisfied(FitAssessmentWeights.careAgreementCare, FitAssessmentWeights.careAgreementCare, strength: 'The care-responsibility agreement was accepted.');
  } else if (care == false) {
    t.failed(FitAssessmentWeights.careAgreementCare, concern: 'The care-responsibility agreement was not accepted.');
  } else {
    t.unknown(FitAssessmentWeights.careAgreementCare, 'Care agreement');
  }

  final followUp = agreement['followUp'] as bool?;
  if (followUp == true) {
    t.satisfied(FitAssessmentWeights.careAgreementFollowUp, FitAssessmentWeights.careAgreementFollowUp);
  } else if (followUp == false) {
    t.failed(FitAssessmentWeights.careAgreementFollowUp, concern: 'The post-adoption follow-up agreement was not accepted.');
  } else {
    t.unknown(FitAssessmentWeights.careAgreementFollowUp, 'Follow-up agreement');
  }

  final noAbandon = agreement['noAbandon'] as bool?;
  if (noAbandon == true) {
    t.satisfied(FitAssessmentWeights.careAgreementNoAbandon, FitAssessmentWeights.careAgreementNoAbandon);
  } else if (noAbandon == false) {
    t.failed(FitAssessmentWeights.careAgreementNoAbandon, concern: 'The no-abandonment agreement was not accepted.');
  } else {
    t.unknown(FitAssessmentWeights.careAgreementNoAbandon, 'No-abandonment agreement');
  }

  return t;
}

// ---- Financial care readiness ------------------------------------------

/// `lifestyle.monthlyBudget` is intentionally never read here — the spec
/// is explicit that it's display-only context, not a scoring input.
_Tally _scoreFinancial(Map canAfford) {
  final t = _Tally();
  void rule(String key, int weight, String readableLabel, {bool isCritical = false}) {
    final value = canAfford[key] as bool?;
    if (value == true) {
      t.satisfied(weight, weight);
    } else if (value == false) {
      t.failed(weight, concern: '$readableLabel was not included in the applicant\'s care budget.');
    } else {
      t.unknown(weight, readableLabel);
    }
  }

  rule('food', FitAssessmentWeights.financialFood, 'Food');
  rule('careSupplies', FitAssessmentWeights.financialCareSupplies, 'Care supplies');
  rule('grooming', FitAssessmentWeights.financialGrooming, 'Grooming');
  rule('vaccinations', FitAssessmentWeights.financialVaccinations, 'Vaccinations');
  rule('vetVisits', FitAssessmentWeights.financialVetVisits, 'Routine vet visits');
  rule('emergencyMedicalCare', FitAssessmentWeights.financialEmergencyCare, 'Emergency medical care');
  return t;
}

// ---- Current-pet readiness ---------------------------------------------

_Tally _scoreCurrentPetReadiness(Map petExperience, Map currentPetsMap) {
  final t = _Tally();

  final hadPetsBefore = petExperience['hadPetsBefore'] as bool?;
  if (hadPetsBefore != null) {
    // Answered either way scores the same — a first-time applicant must
    // not automatically receive a poor score just for being first-time.
    t.satisfied(FitAssessmentWeights.currentPetExperience, FitAssessmentWeights.currentPetExperience,
        strength: hadPetsBefore ? 'The applicant has previous pet ownership experience.' : null);
  } else {
    t.unknown(FitAssessmentWeights.currentPetExperience, 'Previous pet ownership experience');
  }

  final totalCurrentPets = ['dogs', 'cats', 'birds', 'fish', 'reptiles', 'other']
      .map((k) => (currentPetsMap[k] as num?)?.toInt() ?? 0)
      .fold<int>(0, (a, b) => a + b);

  if (totalCurrentPets == 0) {
    // Not applicable, never a failure — see the service's own note on why
    // "no current pets" isn't scored as a gap.
    t.notApplicable(FitAssessmentWeights.currentPetVaccinated, FitAssessmentWeights.currentPetVaccinated);
    t.notApplicable(FitAssessmentWeights.currentPetSpayedNeutered, FitAssessmentWeights.currentPetSpayedNeutered);
  } else {
    final vaccinated = petExperience['currentPetsVaccinated'] as String?;
    if (vaccinated == 'Yes') {
      t.satisfied(FitAssessmentWeights.currentPetVaccinated, FitAssessmentWeights.currentPetVaccinated, strength: 'Current pets are vaccinated.');
    } else if (vaccinated == 'No') {
      t.failed(FitAssessmentWeights.currentPetVaccinated, concern: 'Current pets are not fully vaccinated.');
    } else if (vaccinated != null) {
      // e.g. a partial/"Some" answer — informative, but not a clean pass.
      t.failed(FitAssessmentWeights.currentPetVaccinated, concern: 'Current pets\' vaccination status is only partially complete.');
    } else {
      t.unknown(FitAssessmentWeights.currentPetVaccinated, 'Current pets\' vaccination status');
    }

    final spayed = petExperience['currentPetsSpayedNeutered'] as String?;
    if (spayed == 'Yes') {
      t.satisfied(FitAssessmentWeights.currentPetSpayedNeutered, FitAssessmentWeights.currentPetSpayedNeutered,
          strength: 'Current pets are spayed/neutered.');
    } else if (spayed == 'No') {
      t.failed(FitAssessmentWeights.currentPetSpayedNeutered, concern: 'Current pets are not spayed/neutered.');
    } else if (spayed != null) {
      t.failed(FitAssessmentWeights.currentPetSpayedNeutered, concern: 'Current pets\' spay/neuter status is only partially complete.');
    } else {
      t.unknown(FitAssessmentWeights.currentPetSpayedNeutered, 'Current pets\' spay/neuter status');
    }
  }

  return t;
}

// ---- Animal-specific compatibility --------------------------------------

/// Only compares traits that genuinely exist on both sides. "Good with
/// children" and energy/space needs are NOT scored here — this form has
/// no "do you have children" question and AnimalRecord has no energy-
/// level/space-requirement field, so there is nothing real to compare
/// (adding one would mean inferring from missing data, which the spec
/// explicitly forbids). Absence of a positive trait tag
/// (e.g. keyCharacteristics not containing 'Good with other pets') is
/// never treated as "explicitly incompatible" — this codebase only stores
/// positive tags, never a negative one, so that absence is marked
/// unassessed, not a concern.
_Tally _scoreCompatibility(Map petExperience, Map currentPetsMap, Map canAfford, AnimalRecord animal) {
  final t = _Tally();
  final traits = animal.keyCharacteristics;

  final totalCurrentPets = ['dogs', 'cats', 'birds', 'fish', 'reptiles', 'other']
      .map((k) => (currentPetsMap[k] as num?)?.toInt() ?? 0)
      .fold<int>(0, (a, b) => a + b);
  if (totalCurrentPets == 0) {
    t.notApplicable(FitAssessmentWeights.compatibilityOtherPets, FitAssessmentWeights.compatibilityOtherPets);
  } else if (traits.contains('Good with other pets')) {
    // One of kCompatibilityValues — see animal_characteristics.dart.
    t.satisfied(FitAssessmentWeights.compatibilityOtherPets, FitAssessmentWeights.compatibilityOtherPets,
        strength: 'The animal is marked as good with other pets.');
  } else {
    t.unknown(FitAssessmentWeights.compatibilityOtherPets, 'Whether the animal is good with other pets');
  }

  final hadPetsBefore = petExperience['hadPetsBefore'] as bool?;
  if (hadPetsBefore == null) {
    t.unknown(FitAssessmentWeights.compatibilityFirstTimeOwner, 'First-time-owner compatibility');
  } else if (hadPetsBefore == true) {
    t.notApplicable(FitAssessmentWeights.compatibilityFirstTimeOwner, FitAssessmentWeights.compatibilityFirstTimeOwner);
  } else if (traits.contains('First-time owner friendly')) {
    // One of kCompatibilityValues — see animal_characteristics.dart.
    t.satisfied(FitAssessmentWeights.compatibilityFirstTimeOwner, FitAssessmentWeights.compatibilityFirstTimeOwner,
        strength: 'The animal is marked as first-time-owner friendly.');
  } else {
    t.unknown(FitAssessmentWeights.compatibilityFirstTimeOwner, 'First-time-owner compatibility');
  }

  final hasOngoingMedicalNeeds = animal.health.chronicConditions?.trim().isNotEmpty == true || animal.health.currentMedications?.trim().isNotEmpty == true;
  if (!hasOngoingMedicalNeeds) {
    t.notApplicable(FitAssessmentWeights.compatibilityMedicalNeeds, FitAssessmentWeights.compatibilityMedicalNeeds);
  } else {
    final vetVisits = canAfford['vetVisits'] as bool?;
    final emergencyCare = canAfford['emergencyMedicalCare'] as bool?;
    if (vetVisits == null || emergencyCare == null) {
      t.unknown(FitAssessmentWeights.compatibilityMedicalNeeds, 'Readiness for the animal\'s ongoing medical needs');
    } else if (vetVisits && emergencyCare) {
      t.satisfied(FitAssessmentWeights.compatibilityMedicalNeeds, FitAssessmentWeights.compatibilityMedicalNeeds,
          strength: 'The applicant\'s care budget covers this animal\'s ongoing medical needs.');
    } else {
      t.failed(FitAssessmentWeights.compatibilityMedicalNeeds,
          concern: 'This animal has ongoing medical needs, but the applicant\'s care budget does not fully cover veterinary/emergency care.');
    }
  }

  return t;
}

// ---- Documents and completeness -----------------------------------------

_Tally _scoreDocuments(Map uploads) {
  final t = _Tally();

  final governmentId = _urlsFor(uploads['governmentId']);
  if (governmentId.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.documentsGovernmentId, FitAssessmentWeights.documentsGovernmentId);
  } else {
    t.failed(FitAssessmentWeights.documentsGovernmentId, concern: 'Government ID has not been uploaded.');
  }

  final proofOfAddress = _urlsFor(uploads['proofOfAddress']);
  if (proofOfAddress.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.documentsProofOfAddress, FitAssessmentWeights.documentsProofOfAddress);
  } else {
    t.failed(FitAssessmentWeights.documentsProofOfAddress, concern: 'Proof of address has not been uploaded.');
  }

  // Never the animal's own photoUrls — a completely different field on a
  // different document (AnimalRecord vs this application's own
  // uploads.homePhotos).
  final homePhotos = _urlsFor(uploads['homePhotos']);
  if (homePhotos.isNotEmpty) {
    t.satisfied(FitAssessmentWeights.documentsHomePhotos, FitAssessmentWeights.documentsHomePhotos);
  } else {
    t.failed(FitAssessmentWeights.documentsHomePhotos, concern: 'Home photos have not been uploaded.');
  }

  return t;
}
