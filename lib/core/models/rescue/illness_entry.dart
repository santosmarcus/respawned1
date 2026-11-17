import 'package:cloud_firestore/cloud_firestore.dart';

/// Analytics gap 5: one illness an animal had in the organization's care,
/// at `animals/{animalId}/illnesses/{id}`. Recorded on the animal's Medical
/// tab; Analytics ("Are animals protected from illness?") counts new and
/// contagious cases per period. organizationId is stamped by
/// stampAnimalsIllnessesOrganization (functions/audit_logs.js).
class IllnessEntry {
  final String id;
  final String animalId;
  final String condition;
  final DateTime onset;
  final bool contagious;
  final bool isolated;
  final String? notes;
  final DateTime? resolvedAt;
  final String? recordedByName;

  const IllnessEntry({
    required this.id,
    required this.animalId,
    required this.condition,
    required this.onset,
    required this.contagious,
    required this.isolated,
    this.notes,
    this.resolvedAt,
    this.recordedByName,
  });

  bool get active => resolvedAt == null;

  static IllnessEntry? fromFirestore(DocumentSnapshot<Map<String, dynamic>> d, String animalId) {
    final m = d.data();
    if (m == null) return null;
    final onset = m['onsetDate'];
    final condition = m['condition'];
    if (onset is! Timestamp || condition is! String) return null;
    final resolved = m['resolvedAt'];
    return IllnessEntry(
      id: d.id,
      animalId: animalId,
      condition: condition,
      onset: onset.toDate(),
      contagious: m['contagious'] == true,
      isolated: m['isolated'] == true,
      notes: m['notes'] as String?,
      resolvedAt: resolved is Timestamp ? resolved.toDate() : null,
      recordedByName: m['recordedByName'] as String?,
    );
  }
}
