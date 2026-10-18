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

/// True for a real Firebase Storage download URL — false for a local
/// device path, a temporary picker URI, a bare Storage path (`gs://...`),
/// or an empty string. No writer in this codebase currently saves
/// anything but a real download URL, but this guards against ever
/// rendering one of those instead of just failing to load silently.
bool looksLikeDownloadUrl(String value) => value.startsWith('http://') || value.startsWith('https://');

/// `photoUrls` is the only field name any current writer in this codebase
/// uses for animal images (see create_animal_record_page.dart) — this
/// fallback chain exists only for documents written by something outside
/// this codebase (a script, a console edit, ...) that used a different
/// field name. Tries, in order: `photoUrls` -> legacy `images`/`imageUrls`
/// (also lists) -> legacy `photoUrl`/`imageUrl` (single strings). Every
/// candidate is filtered through [looksLikeDownloadUrl] so a local path or
/// empty string never gets treated as a usable photo.
List<String> _parsePhotoUrls(Map<String, dynamic> data) {
  for (final key in ['photoUrls', 'images', 'imageUrls']) {
    final list = parseStringList(data[key]).where(looksLikeDownloadUrl).toList();
    if (list.isNotEmpty) return list;
  }
  for (final key in ['photoUrl', 'imageUrl', 'profileImage']) {
    final single = parseOptionalString(data[key]);
    if (single != null && looksLikeDownloadUrl(single)) return [single];
  }
  return const [];
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
  // The visibility/control flag (spec: "Add Special Needs to Animal
  // Records" section 5). Backed by the legacy `specialNeeds` boolean
  // Firestore key — no migration/rename of that key was needed since the
  // structured selections/notes below live under new, separate keys
  // (`specialNeedsTypes`/`specialNeedsNotes`) rather than colliding with it.
  final bool hasSpecialNeeds;
  // Structured selections, e.g. ["Blind", "One-eyed"]. Firestore key:
  // `specialNeedsTypes` (new — deliberately not named `specialNeeds` to
  // avoid clashing with the legacy boolean field of that name).
  final List<String> specialNeedsTypes;
  // Optional free-text supporting info, e.g. "Requires guided indoor
  // movement." Firestore key: `specialNeedsNotes`.
  final String? specialNeedsNotes;
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
    required this.hasSpecialNeeds,
    this.specialNeedsTypes = const [],
    this.specialNeedsNotes,
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
  // 'transferStatus' only ever reaches 'pending' today (see
  // AnimalRecordRepository.transferAnimal's own doc comment — there is no
  // receiving-party accept/complete step yet), so "transferred out" reads
  // straight off [raw] rather than a dedicated constructor field; there is
  // no other value this could ever hold.
  bool get isTransferredOut => (raw['transferStatus'] as String?) == 'pending';

  /// The one canonical human-readable status — used by the record header,
  /// the Management tab's safety guards, and (via the same underlying
  /// fields) the Animal Records status filter, so no surface invents its
  /// own precedence between archived/deceased/adopted/reserved/etc.
  String get statusLabel {
    if (archived) return 'Archived';
    if (isDeceased) return 'Deceased';
    if (isAdopted) return 'Adopted';
    if (isTransferredOut) return 'Transferred';
    if (isReserved) return 'Reserved';
    if (currentCaseId != null) return 'In Treatment';
    if (isAdoptable) return 'Adoptable';
    return 'Not Ready for Adoption';
  }
  /// True only when there's something worth actually showing — a bare
  /// `hasSpecialNeeds: true` with no selected type and no notes renders
  /// nothing (spec: never show a "Special Needs / None" section).
  bool get hasMeaningfulSpecialNeedsInfo =>
      hasSpecialNeeds && (specialNeedsTypes.isNotEmpty || (specialNeedsNotes?.trim().isNotEmpty ?? false));

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
        hasSpecialNeeds: false,
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
    final specialNeedsTypes = parseStringList(data['specialNeedsTypes']);
    final specialNeedsNotes = parseOptionalString(data['specialNeedsNotes']);
    // Legacy documents only ever set the flat `specialNeeds` boolean.
    // Newer documents may also carry a non-empty `specialNeedsTypes`/notes
    // list without the legacy boolean being set explicitly true — derive
    // the flag from that presence rather than losing the data.
    final hasSpecialNeeds = parseBool(data['specialNeeds']) ||
        specialNeedsTypes.isNotEmpty ||
        (specialNeedsNotes?.trim().isNotEmpty ?? false);

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
      hasSpecialNeeds: hasSpecialNeeds,
      specialNeedsTypes: specialNeedsTypes,
      specialNeedsNotes: specialNeedsNotes,
      keyCharacteristics: parseStringList(data['keyCharacteristics']),
      rescueBackground: parseStringList(data['rescueBackground']),
      tags: parseStringList(data['tags']),
      adoptionStatus: parseRequiredString(data['adoptionStatus'], fallback: 'not_ready'),
      status: parseRequiredString(data['status'], fallback: 'intake'),
      linkedCaseId: parseRequiredString(data['linkedCaseId']),
      sourceAnimalIndex: parseOptionalInt(data['sourceAnimalIndex']),
      rescuedBy: parseRequiredString(data['rescuedBy']),
      photoUrls: _parsePhotoUrls(data),
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