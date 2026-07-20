import 'package:cloud_firestore/cloud_firestore.dart';

/// A single submission under `cases/{caseId}/reports/{reportId}`.
///
/// A case can end up with more than one report once duplicates are merged
/// into it — the primary report (the one that created the case) plus any
/// later reports the organization decided were the same incident. Each
/// report keeps its own reporter identity, media, location and description
/// so none of that is lost on merge; only the case-level `status` is
/// centralized on the parent `cases/{caseId}` document.
class RescueReport {
  final String id;
  final String caseId;
  final String? reporterId;
  final String? reporterName;
  final String? reporterPhone;
  final String? description;
  final List<String> photoUrls;
  final String? address;
  final double? lat;
  final double? lng;
  final String? species;
  final String? urgency;
  final DateTime? submittedAt;
  final bool isPrimary;

  /// Set once this report has been merged into another case (i.e. it was
  /// judged a duplicate of an already-existing case, not the other way
  /// around). Null for the primary report of a case.
  final String? mergedIntoCaseId;

  const RescueReport({
    required this.id,
    required this.caseId,
    this.reporterId,
    this.reporterName,
    this.reporterPhone,
    this.description,
    this.photoUrls = const [],
    this.address,
    this.lat,
    this.lng,
    this.species,
    this.urgency,
    this.submittedAt,
    this.isPrimary = false,
    this.mergedIntoCaseId,
  });

  factory RescueReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String caseId,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['submittedAt'];
    return RescueReport(
      id: doc.id,
      caseId: caseId,
      reporterId: data['reporterId'] as String?,
      reporterName: data['reporterName'] as String?,
      reporterPhone: data['reporterPhone'] as String?,
      description: data['description'] as String?,
      photoUrls: List<String>.from(data['photoUrls'] ?? const []),
      address: data['address'] as String?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      species: data['species'] as String?,
      urgency: data['urgency'] as String?,
      submittedAt: ts is Timestamp ? ts.toDate() : null,
      isPrimary: data['isPrimary'] as bool? ?? false,
      mergedIntoCaseId: data['mergedIntoCaseId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'reporterId': reporterId,
        'reporterName': reporterName,
        'reporterPhone': reporterPhone,
        'description': description,
        'photoUrls': photoUrls,
        'address': address,
        'lat': lat,
        'lng': lng,
        'species': species,
        'urgency': urgency,
        'submittedAt': submittedAt != null ? Timestamp.fromDate(submittedAt!) : FieldValue.serverTimestamp(),
        'isPrimary': isPrimary,
        if (mergedIntoCaseId != null) 'mergedIntoCaseId': mergedIntoCaseId,
      };
}
