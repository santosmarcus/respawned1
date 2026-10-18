import 'package:cloud_firestore/cloud_firestore.dart';

/// Why a non-rescue medical episode was opened — collected by AdmitAnimalPage
/// before clinic selection. Distinct from [TreatmentUpdateType] (which
/// describes a single update *within* an episode already underway).
enum AdmissionReason {
  illness,
  injury,
  vaccination,
  routineCheckup,
  procedure,
  emergency,
  other;

  String get label => switch (this) {
        AdmissionReason.illness => 'Illness',
        AdmissionReason.injury => 'Injury',
        AdmissionReason.vaccination => 'Vaccination',
        AdmissionReason.routineCheckup => 'Routine Checkup',
        AdmissionReason.procedure => 'Procedure',
        AdmissionReason.emergency => 'Emergency',
        AdmissionReason.other => 'Other',
      };

  /// Episode-card title for a non-rescue admission — "Illness Admission",
  /// "Routine Checkup" (no redundant "Admission" suffix), etc.
  String get episodeTitle => switch (this) {
        AdmissionReason.illness => 'Illness Admission',
        AdmissionReason.injury => 'Injury Treatment',
        AdmissionReason.vaccination => 'Vaccination',
        AdmissionReason.routineCheckup => 'Routine Checkup',
        AdmissionReason.procedure => 'Procedure',
        AdmissionReason.emergency => 'Emergency Admission',
        AdmissionReason.other => 'Medical Admission',
      };

  static AdmissionReason fromName(String? name) =>
      values.firstWhere((r) => r.name == name, orElse: () => AdmissionReason.other);
}

/// A single doc under `animalRecords/{animalId}/medicalEpisodes/{episodeId}`
/// — deliberately a thin *reference* to a `cases/{sourceCaseId}` doc, not a
/// duplicate of it. Everything that changes as the episode progresses
/// (status, clinic, admission/discharge dates, condition, treatment logs,
/// expenses) is read live from that case via the existing
/// RescueCaseRepository streams — this doc only records what's genuinely
/// specific to *why this episode was opened* and never changes afterward.
///
/// The animal's original rescue-origin treatment (if any) has no doc here
/// at all — it's referenced directly via AnimalRecord.linkedCaseId instead,
/// since it predates this subcollection and already has everywhere it needs
/// to point.
class MedicalEpisode {
  final String id;
  final String animalId;
  final String sourceCaseId;
  final AdmissionReason reason;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;

  const MedicalEpisode({
    required this.id,
    required this.animalId,
    required this.sourceCaseId,
    required this.reason,
    this.notes,
    this.createdAt,
    this.createdBy,
  });

  factory MedicalEpisode.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String animalId) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    return MedicalEpisode(
      id: doc.id,
      animalId: animalId,
      sourceCaseId: data['sourceCaseId'] as String? ?? '',
      reason: AdmissionReason.fromName(data['reason'] as String?),
      notes: data['notes'] as String?,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      createdBy: data['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'animalId': animalId,
        'sourceCaseId': sourceCaseId,
        'sourceType': 'animalRecordAdmission',
        'reason': reason.name,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        if (createdBy != null) 'createdBy': createdBy,
      };
}
