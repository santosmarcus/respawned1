import 'package:cloud_firestore/cloud_firestore.dart';

/// Reuses (renamed only where the old set was inconsistent — 'Initial
/// Assessment' -> 'Assessment', 'Discharge Ready' -> 'Discharge') the
/// update-type vocabulary the old treatment_detail_page.dart already wrote
/// as a free-text `type` string. Nothing outside this page ever switched on
/// that string, so this rename is safe — old logs with a type outside this
/// list (e.g. legacy 'Wound Care') still display fine as plain text.
enum TreatmentUpdateType {
  assessment,
  medication,
  procedure,
  vaccination,
  followUpCheck,
  discharge,
  deathReport;

  String get label => switch (this) {
        TreatmentUpdateType.assessment => 'Assessment',
        TreatmentUpdateType.medication => 'Medication',
        TreatmentUpdateType.procedure => 'Procedure',
        TreatmentUpdateType.vaccination => 'Vaccination',
        TreatmentUpdateType.followUpCheck => 'Follow-up Check',
        TreatmentUpdateType.discharge => 'Discharge',
        TreatmentUpdateType.deathReport => 'Death Report',
      };

  static TreatmentUpdateType? fromLabel(String? label) {
    for (final t in TreatmentUpdateType.values) {
      if (t.label == label) return t;
    }
    return null;
  }
}

/// A single entry under `cases/{caseId}/treatmentLogs/{logId}` — append-only,
/// never edited or overwritten once saved. Older cases may still have
/// entries living only in the case doc's legacy `treatmentLog` array field
/// (written before this subcollection existed); [isLegacy] marks those so
/// the UI can display them identically without pretending they have a real
/// subcollection doc id.
class TreatmentLogEntry {
  final String id;
  final String caseId;
  final String type; // free text — see TreatmentUpdateType.label for the canonical set
  final String notes;
  final String? condition; // overall condition at the time of this update
  final String? medicationName;
  final String? medicationDose;
  final String? procedurePerformed;
  final String? vaccineName;
  final String? vaccineDose;
  final DateTime? nextScheduleAt;
  final String? dischargeNotes;
  final String? finalCondition;
  final String? postTreatmentInstructions;
  final DateTime? dateOfDeath;
  final String? causeOfDeath;
  final List<String> mediaUrls;
  final String? createdBy;
  final DateTime? timestamp;
  final bool isLegacy;

  const TreatmentLogEntry({
    required this.id,
    required this.caseId,
    required this.type,
    required this.notes,
    this.condition,
    this.medicationName,
    this.medicationDose,
    this.procedurePerformed,
    this.vaccineName,
    this.vaccineDose,
    this.nextScheduleAt,
    this.dischargeNotes,
    this.finalCondition,
    this.postTreatmentInstructions,
    this.dateOfDeath,
    this.causeOfDeath,
    this.mediaUrls = const [],
    this.createdBy,
    this.timestamp,
    this.isLegacy = false,
  });

  factory TreatmentLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String caseId,
  ) {
    return TreatmentLogEntry._fromMap(doc.id, caseId, doc.data() ?? const {}, isLegacy: false);
  }

  /// Old cases wrote plain `{type, notes, condition, medicationGiven,
  /// timestamp, addedBy, causeOfDeath?}` maps into a `treatmentLog` array on
  /// the case doc itself. Adapted here into the same shape so the log list
  /// can merge both sources — never written to again, only ever displayed.
  factory TreatmentLogEntry.fromLegacyMap(Map<String, dynamic> map, String caseId, int index) {
    final medicationGiven = map['medicationGiven'] as String?;
    return TreatmentLogEntry._fromMap(
      'legacy-$index',
      caseId,
      {
        ...map,
        if (medicationGiven != null && medicationGiven.isNotEmpty) 'medicationName': medicationGiven,
        'createdBy': map['addedBy'],
      },
      isLegacy: true,
    );
  }

  static TreatmentLogEntry _fromMap(
    String id,
    String caseId,
    Map<String, dynamic> data, {
    required bool isLegacy,
  }) {
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    return TreatmentLogEntry(
      id: id,
      caseId: caseId,
      type: data['type'] as String? ?? '-',
      notes: data['notes'] as String? ?? '',
      condition: data['condition'] as String?,
      medicationName: data['medicationName'] as String?,
      medicationDose: data['medicationDose'] as String?,
      procedurePerformed: data['procedurePerformed'] as String?,
      vaccineName: data['vaccineName'] as String?,
      vaccineDose: data['vaccineDose'] as String?,
      nextScheduleAt: ts('nextScheduleAt'),
      dischargeNotes: data['dischargeNotes'] as String?,
      finalCondition: data['finalCondition'] as String?,
      postTreatmentInstructions: data['postTreatmentInstructions'] as String?,
      dateOfDeath: ts('dateOfDeath'),
      causeOfDeath: data['causeOfDeath'] as String?,
      mediaUrls: List<String>.from(data['mediaUrls'] ?? const []),
      createdBy: data['createdBy'] as String?,
      timestamp: ts('timestamp'),
      isLegacy: isLegacy,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'notes': notes,
        if (condition != null) 'condition': condition,
        if (medicationName != null && medicationName!.isNotEmpty) 'medicationName': medicationName,
        if (medicationDose != null && medicationDose!.isNotEmpty) 'medicationDose': medicationDose,
        if (procedurePerformed != null && procedurePerformed!.isNotEmpty)
          'procedurePerformed': procedurePerformed,
        if (vaccineName != null && vaccineName!.isNotEmpty) 'vaccineName': vaccineName,
        if (vaccineDose != null && vaccineDose!.isNotEmpty) 'vaccineDose': vaccineDose,
        if (nextScheduleAt != null) 'nextScheduleAt': Timestamp.fromDate(nextScheduleAt!),
        if (dischargeNotes != null && dischargeNotes!.isNotEmpty) 'dischargeNotes': dischargeNotes,
        if (finalCondition != null && finalCondition!.isNotEmpty) 'finalCondition': finalCondition,
        if (postTreatmentInstructions != null && postTreatmentInstructions!.isNotEmpty)
          'postTreatmentInstructions': postTreatmentInstructions,
        if (dateOfDeath != null) 'dateOfDeath': Timestamp.fromDate(dateOfDeath!),
        if (causeOfDeath != null && causeOfDeath!.isNotEmpty) 'causeOfDeath': causeOfDeath,
        'mediaUrls': mediaUrls,
        if (createdBy != null) 'createdBy': createdBy,
        'timestamp': Timestamp.now(),
      };
}
