import 'package:cloud_firestore/cloud_firestore.dart';

/// Derived, never stored — recomputed from [VaccinationRecord.nextDueDate]
/// every time it's displayed, so changing [kDueSoonWindow] instantly
/// reclassifies every existing record without a backfill.
enum VaccineStatus {
  noRecord,
  upToDate,
  dueSoon,
  overdue;

  String get label => switch (this) {
        VaccineStatus.noRecord => 'No record',
        VaccineStatus.upToDate => 'Up to date',
        VaccineStatus.dueSoon => 'Due soon',
        VaccineStatus.overdue => 'Overdue',
      };
}

/// Single configurable threshold for "due soon" — kept in one place rather
/// than embedded throughout the UI, per the vaccine-status spec. Changing
/// this one constant is the only thing needed to retune every vaccine card
/// and every "needs attention" indicator on the Animal Records list.
const Duration kDueSoonWindow = Duration(days: 30);

VaccineStatus vaccineStatusFor(DateTime? nextDueDate, {DateTime? now}) {
  if (nextDueDate == null) return VaccineStatus.noRecord;
  final today = now ?? DateTime.now();
  if (nextDueDate.isBefore(today)) return VaccineStatus.overdue;
  if (nextDueDate.isBefore(today.add(kDueSoonWindow))) return VaccineStatus.dueSoon;
  return VaccineStatus.upToDate;
}

/// A built-in *suggestion* only — species-appropriate vaccine name +
/// default validity, both editable before saving (per the spec: "Treat
/// built-in intervals as configurable suggestions"). Never the sole source
/// of truth for an actual vaccination's validity once recorded — that's
/// always [VaccinationRecord.validityDurationDays], which starts from this
/// template's default but can be overridden per the priority order:
/// template -> vet-entered duration -> manually entered next-due date.
class VaccineTemplate {
  final String name;
  final int defaultValidityDays;
  const VaccineTemplate({required this.name, required this.defaultValidityDays});

  static const List<VaccineTemplate> dog = [
    VaccineTemplate(name: 'Rabies', defaultValidityDays: 365),
    VaccineTemplate(name: '5-in-1 (DHPP)', defaultValidityDays: 365),
    VaccineTemplate(name: 'Bordetella', defaultValidityDays: 365),
    VaccineTemplate(name: 'Leptospirosis', defaultValidityDays: 365),
  ];

  static const List<VaccineTemplate> cat = [
    VaccineTemplate(name: 'Rabies', defaultValidityDays: 365),
    VaccineTemplate(name: '3-in-1 (FVRCP)', defaultValidityDays: 365),
    VaccineTemplate(name: 'FeLV', defaultValidityDays: 365),
  ];

  /// Species-appropriate catalog — dog templates are never offered for a
  /// cat record and vice versa. Falls back to the dog list for any other/
  /// unrecognized species rather than showing nothing.
  static List<VaccineTemplate> forSpecies(String? species) {
    final s = species?.trim().toLowerCase();
    if (s == 'cat') return cat;
    return dog;
  }
}

/// A single doc under
/// `animalRecords/{animalId}/vaccinations/{vaccinationId}` — the source of
/// truth for vaccine status; the old flat `vaccinated`/`vaccinesGiven`
/// fields on the animal doc remain only as a lightweight derived summary
/// (see AnimalRecordRepository.vaccinationSummary), never written to
/// directly by this flow.
class VaccinationRecord {
  final String id;
  final String animalId;
  final String vaccineName;
  final String species;
  final DateTime dateAdministered;
  /// Validity window in days — always stored explicitly (never re-derived
  /// from the template later), so a past record's validity never silently
  /// changes if the template's own default is edited going forward.
  final int validityDurationDays;
  final DateTime nextDueDate;
  final String? clinicOrProvider;
  final String? batchOrLotNumber;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;

  const VaccinationRecord({
    required this.id,
    required this.animalId,
    required this.vaccineName,
    required this.species,
    required this.dateAdministered,
    required this.validityDurationDays,
    required this.nextDueDate,
    this.clinicOrProvider,
    this.batchOrLotNumber,
    this.notes,
    this.createdAt,
    this.createdBy,
  });

  VaccineStatus get status => vaccineStatusFor(nextDueDate);

  factory VaccinationRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String animalId) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime ts(String key, DateTime fallback) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : fallback;
    }

    final createdAt = data['createdAt'];
    return VaccinationRecord(
      id: doc.id,
      animalId: animalId,
      vaccineName: data['vaccineName'] as String? ?? '-',
      species: data['species'] as String? ?? '',
      dateAdministered: ts('dateAdministered', DateTime.now()),
      validityDurationDays: (data['validityDurationDays'] as num?)?.toInt() ?? 365,
      nextDueDate: ts('nextDueDate', DateTime.now()),
      clinicOrProvider: data['clinicOrProvider'] as String?,
      batchOrLotNumber: data['batchOrLotNumber'] as String?,
      notes: data['notes'] as String?,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      createdBy: data['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'vaccineName': vaccineName,
        'species': species,
        'dateAdministered': Timestamp.fromDate(dateAdministered),
        'validityDurationDays': validityDurationDays,
        'nextDueDate': Timestamp.fromDate(nextDueDate),
        if (clinicOrProvider != null && clinicOrProvider!.isNotEmpty) 'clinicOrProvider': clinicOrProvider,
        if (batchOrLotNumber != null && batchOrLotNumber!.isNotEmpty) 'batchOrLotNumber': batchOrLotNumber,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        if (createdBy != null) 'createdBy': createdBy,
      };
}
