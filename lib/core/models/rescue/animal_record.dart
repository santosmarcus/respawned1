import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/utils/firestore_parsing.dart';

/// Structured health fields (spec section 6) — every value defaults to
/// "unknown"/absent rather than a guessed default; nothing here is ever
/// invented. Sterilization/deworming reuse the existing boolean fields
/// (spayedNeutered/dewormed) as their status source since those already
/// exist and this is deliberately not a parallel structure — the rest are
/// new, genuinely-missing-before fields.
class AnimalHealthDetails {
  final bool? sterilized;
  final bool? dewormed;
  final String? allergies;
  final String? chronicConditions;
  final String? currentMedications;
  final DateTime? lastVetCheckup;
  final double? weightKg;
  final String? bodyCondition;
  final String? microchipStatus;

  const AnimalHealthDetails({
    this.sterilized,
    this.dewormed,
    this.allergies,
    this.chronicConditions,
    this.currentMedications,
    this.lastVetCheckup,
    this.weightKg,
    this.bodyCondition,
    this.microchipStatus,
  });

  factory AnimalHealthDetails.fromMap(Map<String, dynamic> data) {
    final checkup = data['lastVetCheckup'];
    return AnimalHealthDetails(
      sterilized: data['spayedNeutered'] == null ? null : parseBool(data['spayedNeutered']),
      dewormed: data['dewormed'] == null ? null : parseBool(data['dewormed']),
      allergies: parseOptionalString(data['allergies']),
      chronicConditions: parseOptionalString(data['chronicConditions']),
      currentMedications: parseOptionalString(data['currentMedications']),
      lastVetCheckup: checkup is Timestamp ? checkup.toDate() : null,
      weightKg: parseOptionalDouble(data['weightKg']),
      bodyCondition: parseOptionalString(data['bodyCondition']),
      microchipStatus: parseOptionalString(data['microchipStatus']),
    );
  }

  Map<String, dynamic> toMap() => {
        if (allergies != null) 'allergies': allergies,
        if (chronicConditions != null) 'chronicConditions': chronicConditions,
        if (currentMedications != null) 'currentMedications': currentMedications,
        if (lastVetCheckup != null) 'lastVetCheckup': Timestamp.fromDate(lastVetCheckup!),
        if (weightKg != null) 'weightKg': weightKg,
        if (bodyCondition != null) 'bodyCondition': bodyCondition,
        if (microchipStatus != null) 'microchipStatus': microchipStatus,
      };
}

/// Parses `animals/{id}` — the same collection/doc CreateAnimalRecordPage
/// already writes to; this is a typed read-side view of it, not a new
/// collection. Every field here already exists on that doc (see
/// create_animal_record_page.dart's write map) except [currentCaseId]
/// (points at the active/most-recent medical-episode case) and [archived],
/// both additive.
///
/// Every field is parsed through the centralized helpers in
/// core/utils/firestore_parsing.dart rather than a bare `as String?`/
/// `as bool?` cast — real documents predating the current write path have
/// been observed storing e.g. `age` as an int64 instead of a string, and a
/// bare cast throws on that instead of coercing it. See [fromFirestore] for
/// the last-resort per-document safety net on top of that.
class AnimalRecord {
  final String id;
  final String name;
  final String age;
  final String species;
  final String breed;
  final String sex;
  final String size;
  final String coatLength;
  final String description;
  final bool vaccinated;
  final bool spayedNeutered;
  final bool dewormed;
  final List<String> keyCharacteristics;
  final List<String> rescueBackground;
  final List<String> tags;
  final String adoptionStatus;
  final String status;
  final String linkedCaseId;
  final int? sourceAnimalIndex;
  final String rescuedBy;
  final List<String> photoUrls;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? currentCaseId;
  final bool archived;
  final DateTime? deceasedAt;
  final String? deceasedCause;
  // Reservation/adoption — written by AdoptionApplicationRepository's
  // reserve/unreserve/release transactions (lib/core/repos/
  // adoption_application_repository.dart), never directly by this model.
  final String? reservedForUserId;
  final String? reservedApplicationId;
  final DateTime? reservedAt;
  final String? adoptedByUserId;
  final String? adoptedApplicationId;
  final DateTime? adoptedAt;
  // Return-from-adoption — written by AnimalRecordRepository.
  // returnFromAdoption. adoptedByUserId/adoptedApplicationId/adoptedAt above
  // are never cleared by a return: they stay as the historical record of
  // the completed adoption, while these fields describe current state.
  final String? currentStatus;
  final String? latestReturnRequestId;
  final DateTime? returnedAt;
  final String? previousAdoptionId;
  final AnimalHealthDetails health;
  final Map<String, dynamic> raw;
  /// Set only by [fromFirestore]'s fallback path when this document's
  /// shape couldn't be fully parsed even through the safe helpers below —
  /// lets the UI show a "could not display this record" placeholder for
  /// just this row instead of guessing at unset fields silently.
  final bool isMalformed;

  const AnimalRecord({
    required this.id,
    required this.name,
    required this.age,
    required this.species,
    required this.breed,
    required this.sex,
    required this.size,
    required this.coatLength,
    required this.description,
    required this.vaccinated,
    required this.spayedNeutered,
    required this.dewormed,
    required this.keyCharacteristics,
    required this.rescueBackground,
    required this.tags,
    required this.adoptionStatus,
    required this.status,
    required this.linkedCaseId,
    required this.sourceAnimalIndex,
    required this.rescuedBy,
    required this.photoUrls,
    required this.createdAt,
    required this.updatedAt,
    required this.currentCaseId,
    required this.archived,
    required this.deceasedAt,
    required this.deceasedCause,
    this.reservedForUserId,
    this.reservedApplicationId,
    this.reservedAt,
    this.adoptedByUserId,
    this.adoptedApplicationId,
    this.adoptedAt,
    this.currentStatus,
    this.latestReturnRequestId,
    this.returnedAt,
    this.previousAdoptionId,
    required this.health,
    required this.raw,
    this.isMalformed = false,
  });

  bool get hasSourceCase => linkedCaseId.isNotEmpty;
  bool get isAdoptable => adoptionStatus == 'adoptable';
  bool get isReserved => adoptionStatus == 'reserved';
  bool get isAdopted => adoptionStatus == 'adopted';
  bool get isDeceased => adoptionStatus == 'deceased' || status == 'deceased';
  bool get isReturned => currentStatus == 'returned';

  /// Never throws — a document whose shape defeats even the safe per-field
  /// helpers below falls back to a minimal, clearly-flagged record (see
  /// [isMalformed]) instead of taking the whole list down with it. Callers
  /// that read every document in a snapshot (e.g.
  /// AnimalRecordRepository.streamAllAnimalRecords) should still wrap this
  /// in their own try/catch as a second layer, but this factory itself is
  /// the primary safety net.
  factory AnimalRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    try {
      return AnimalRecord.fromMap(doc.id, data);
    } catch (e, st) {
      debugPrint('[AnimalRecord] doc ${doc.id} failed to parse ($e) — falling back to a minimal record.\n$st');
      return AnimalRecord(
        id: doc.id,
        name: parseRequiredString(data['name']),
        age: parseRequiredString(data['age']),
        species: parseRequiredString(data['species']),
        breed: '',
        sex: '',
        size: '',
        coatLength: '',
        description: '',
        vaccinated: false,
        spayedNeutered: false,
        dewormed: false,
        keyCharacteristics: const [],
        rescueBackground: const [],
        tags: const [],
        adoptionStatus: 'not_ready',
        status: 'intake',
        linkedCaseId: parseRequiredString(data['linkedCaseId']),
        sourceAnimalIndex: null,
        rescuedBy: '',
        photoUrls: const [],
        createdAt: null,
        updatedAt: null,
        currentCaseId: null,
        archived: false,
        deceasedAt: null,
        deceasedCause: null,
        health: const AnimalHealthDetails(),
        raw: data,
        isMalformed: true,
      );
    }
  }

  /// Same parsing as [fromFirestore], for callers that only have the raw
  /// map and id (e.g. a page's fallback before its live stream has loaded,
  /// mirroring RescueCase.fromMap's own fallback role). Every field goes
  /// through the safe helpers in core/utils/firestore_parsing.dart, so a
  /// legacy document storing e.g. `age` as a number or `tags` as a single
  /// string (instead of a list) coerces cleanly instead of throwing.
  factory AnimalRecord.fromMap(String id, Map<String, dynamic> data) {
    final createdAtRaw = data['createdAt'];
    final updatedAtRaw = data['updatedAt'];
    final deceasedAtRaw = data['deceasedAt'];
    final reservedAtRaw = data['reservedAt'];
    final adoptedAtRaw = data['adoptedAt'];
    final returnedAtRaw = data['returnedAt'];
    // 'intakeDate' is the field name a now-removed older intake form used —
    // 'createdAt' is the standardized field every current writer sets;
    // fall back only when createdAt itself is missing.
    final intakeDateRaw = data['intakeDate'];

    return AnimalRecord(
      id: id,
      name: parseRequiredString(data['name']),
      age: parseRequiredString(data['age']),
      species: parseRequiredString(data['species']),
      breed: parseRequiredString(data['breed']),
      sex: parseRequiredString(data['sex']),
      size: parseRequiredString(data['size']),
      coatLength: parseRequiredString(data['coatLength']),
      description: parseRequiredString(data['description']),
      vaccinated: parseBool(data['vaccinated']),
      spayedNeutered: parseBool(data['spayedNeutered']),
      dewormed: parseBool(data['dewormed']),
      keyCharacteristics: parseStringList(data['keyCharacteristics']),
      rescueBackground: parseStringList(data['rescueBackground']),
      tags: parseStringList(data['tags']),
      adoptionStatus: parseRequiredString(data['adoptionStatus'], fallback: 'not_ready'),
      status: parseRequiredString(data['status'], fallback: 'intake'),
      linkedCaseId: parseRequiredString(data['linkedCaseId']),
      sourceAnimalIndex: parseOptionalInt(data['sourceAnimalIndex']),
      rescuedBy: parseRequiredString(data['rescuedBy']),
      photoUrls: parseStringList(data['photoUrls']),
      createdAt: createdAtRaw is Timestamp
          ? createdAtRaw.toDate()
          : (intakeDateRaw is Timestamp ? intakeDateRaw.toDate() : null),
      updatedAt: updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null,
      currentCaseId: parseOptionalString(data['currentCaseId']),
      archived: parseBool(data['archived']),
      deceasedAt: deceasedAtRaw is Timestamp ? deceasedAtRaw.toDate() : null,
      deceasedCause: parseOptionalString(data['deceasedCause']),
      reservedForUserId: parseOptionalString(data['reservedForUserId']),
      reservedApplicationId: parseOptionalString(data['reservedApplicationId']),
      reservedAt: reservedAtRaw is Timestamp ? reservedAtRaw.toDate() : null,
      adoptedByUserId: parseOptionalString(data['adoptedByUserId']),
      adoptedApplicationId: parseOptionalString(data['adoptedApplicationId']),
      adoptedAt: adoptedAtRaw is Timestamp ? adoptedAtRaw.toDate() : null,
      currentStatus: parseOptionalString(data['currentStatus']),
      latestReturnRequestId: parseOptionalString(data['latestReturnRequestId']),
      returnedAt: returnedAtRaw is Timestamp ? returnedAtRaw.toDate() : null,
      previousAdoptionId: parseOptionalString(data['previousAdoptionId']),
      health: AnimalHealthDetails.fromMap(data),
      raw: data,
    );
  }
}
