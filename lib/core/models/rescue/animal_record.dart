import 'package:cloud_firestore/cloud_firestore.dart';

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
      sterilized: data['spayedNeutered'] as bool?,
      dewormed: data['dewormed'] as bool?,
      allergies: data['allergies'] as String?,
      chronicConditions: data['chronicConditions'] as String?,
      currentMedications: data['currentMedications'] as String?,
      lastVetCheckup: checkup is Timestamp ? checkup.toDate() : null,
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      bodyCondition: data['bodyCondition'] as String?,
      microchipStatus: data['microchipStatus'] as String?,
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
  });

  bool get hasSourceCase => linkedCaseId.isNotEmpty;
  bool get isAdoptable => adoptionStatus == 'adoptable';
  bool get isReserved => adoptionStatus == 'reserved';
  bool get isAdopted => adoptionStatus == 'adopted';
  bool get isDeceased => adoptionStatus == 'deceased' || status == 'deceased';
  bool get isReturned => currentStatus == 'returned';

  factory AnimalRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AnimalRecord.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  /// Same parsing as [fromFirestore], for callers that only have the raw
  /// map and id (e.g. a page's fallback before its live stream has loaded,
  /// mirroring RescueCase.fromMap's own fallback role).
  factory AnimalRecord.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    final deceasedAt = data['deceasedAt'];
    return AnimalRecord(
      id: id,
      name: data['name'] as String? ?? '',
      age: data['age'] as String? ?? '',
      species: data['species'] as String? ?? '',
      breed: data['breed'] as String? ?? '',
      sex: data['sex'] as String? ?? '',
      size: data['size'] as String? ?? '',
      coatLength: data['coatLength'] as String? ?? '',
      description: data['description'] as String? ?? '',
      vaccinated: data['vaccinated'] as bool? ?? false,
      spayedNeutered: data['spayedNeutered'] as bool? ?? false,
      dewormed: data['dewormed'] as bool? ?? false,
      keyCharacteristics: List<String>.from(data['keyCharacteristics'] ?? const []),
      rescueBackground: List<String>.from(data['rescueBackground'] ?? const []),
      tags: List<String>.from(data['tags'] ?? const []),
      adoptionStatus: data['adoptionStatus'] as String? ?? 'not_ready',
      status: data['status'] as String? ?? 'intake',
      linkedCaseId: data['linkedCaseId'] as String? ?? '',
      sourceAnimalIndex: (data['sourceAnimalIndex'] as num?)?.toInt(),
      rescuedBy: data['rescuedBy'] as String? ?? '',
      photoUrls: List<String>.from(data['photoUrls'] ?? const []),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
      currentCaseId: data['currentCaseId'] as String?,
      archived: data['archived'] as bool? ?? false,
      deceasedAt: deceasedAt is Timestamp ? deceasedAt.toDate() : null,
      deceasedCause: data['deceasedCause'] as String?,
      reservedForUserId: data['reservedForUserId'] as String?,
      reservedApplicationId: data['reservedApplicationId'] as String?,
      reservedAt: data['reservedAt'] is Timestamp ? (data['reservedAt'] as Timestamp).toDate() : null,
      adoptedByUserId: data['adoptedByUserId'] as String?,
      adoptedApplicationId: data['adoptedApplicationId'] as String?,
      adoptedAt: data['adoptedAt'] is Timestamp ? (data['adoptedAt'] as Timestamp).toDate() : null,
      currentStatus: data['currentStatus'] as String?,
      latestReturnRequestId: data['latestReturnRequestId'] as String?,
      returnedAt: data['returnedAt'] is Timestamp ? (data['returnedAt'] as Timestamp).toDate() : null,
      previousAdoptionId: data['previousAdoptionId'] as String?,
      health: AnimalHealthDetails.fromMap(data),
      raw: data,
    );
  }
}
