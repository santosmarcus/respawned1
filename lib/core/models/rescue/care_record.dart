import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/models/media_ref.dart';

/// Routine, non-vaccine care given to an animal already in the shelter —
/// recorded straight on the animal record, without opening a treatment
/// episode (Admit Animal is for clinic visits that need transport).
enum CareType {
  deworming,
  fleaTick,
  vetCheckup;

  String get label => switch (this) {
        CareType.deworming => 'Deworming',
        CareType.fleaTick => 'Flea & Tick',
        CareType.vetCheckup => 'Vet Checkup',
      };

  /// Suggested gap until the next dose/visit; editable on every record.
  /// Confirm the actual schedule with the attending veterinarian.
  int get defaultIntervalDays => switch (this) {
        CareType.deworming => 90,
        CareType.fleaTick => 30,
        CareType.vetCheckup => 180,
      };

  static CareType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => CareType.vetCheckup);
}

/// A single doc under `animals/{animalId}/careRecords/{recordId}`. Like
/// VaccinationRecord, status is derived from [nextDueDate] at display time
/// (same due-soon window), never stored. For a vet checkup, [nextDueDate] is
/// the scheduled follow-up visit.
class CareRecord {
  final String id;
  final String animalId;
  final CareType type;
  final DateTime dateGiven;
  final DateTime? nextDueDate;
  final String? product;
  final String? provider;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;

  /// Photos of the vet's notes or prescription.
  final List<MediaRef> attachments;

  const CareRecord({
    required this.id,
    required this.animalId,
    required this.type,
    required this.dateGiven,
    this.nextDueDate,
    this.product,
    this.provider,
    this.notes,
    this.createdAt,
    this.createdBy,
    this.attachments = const [],
  });

  VaccineStatus get status => vaccineStatusFor(nextDueDate);

  factory CareRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String animalId) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    return CareRecord(
      id: doc.id,
      animalId: animalId,
      type: CareType.fromName(data['type'] as String?),
      dateGiven: ts('dateGiven') ?? DateTime.now(),
      nextDueDate: ts('nextDueDate'),
      product: data['product'] as String?,
      provider: data['provider'] as String?,
      notes: data['notes'] as String?,
      createdAt: ts('createdAt'),
      createdBy: data['createdBy'] as String?,
      attachments: attachmentsFrom(data),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type.name,
        'dateGiven': Timestamp.fromDate(dateGiven),
        if (nextDueDate != null) 'nextDueDate': Timestamp.fromDate(nextDueDate!),
        if (product != null && product!.isNotEmpty) 'product': product,
        if (provider != null && provider!.isNotEmpty) 'provider': provider,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        if (createdBy != null) 'createdBy': createdBy,
        ...attachmentFields(attachments),
      };

  /// The most recent record of each type, for the Medical tab summary.
  static Map<CareType, CareRecord> latestByType(Iterable<CareRecord> records) {
    final out = <CareType, CareRecord>{};
    for (final r in records) {
      final current = out[r.type];
      if (current == null || r.dateGiven.isAfter(current.dateGiven)) out[r.type] = r;
    }
    return out;
  }
}
