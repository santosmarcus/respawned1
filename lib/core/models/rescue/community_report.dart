import 'package:cloud_firestore/cloud_firestore.dart';

/// A single entry under `cases/{caseId}/communityReports/{reportId}` — the
/// same subcollection the user-side track_case_page.dart's
/// `_CommunityReportSection` writes to when a community member (including
/// the original reporter) submits a sighting update. This is a read-only
/// model for the admin side; nothing here writes to this subcollection.
class CommunityReport {
  final String id;
  final String? reporterId;
  final String? reporterName;
  final String type; // still_here | moved | rescued | no_animal
  final String? comment;
  final String? newAddress; // only set when type == 'moved'
  // Only set for reports submitted after Community Location Validation
  // (spec §4) started requiring a confirmed map pin — legacy 'moved'
  // reports may have newAddress with no coordinates; tolerate both.
  final double? newLat;
  final double? newLng;
  final String? photoUrl;
  final DateTime? timestamp;

  const CommunityReport({
    required this.id,
    this.reporterId,
    this.reporterName,
    required this.type,
    this.comment,
    this.newAddress,
    this.newLat,
    this.newLng,
    this.photoUrl,
    this.timestamp,
  });

  factory CommunityReport.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['timestamp'];
    return CommunityReport(
      id: doc.id,
      reporterId: data['reporterId'] as String?,
      reporterName: data['reporterName'] as String?,
      type: data['type'] as String? ?? '',
      comment: data['comment'] as String?,
      newAddress: data['newAddress'] as String?,
      newLat: (data['newLat'] as num?)?.toDouble(),
      newLng: (data['newLng'] as num?)?.toDouble(),
      photoUrl: data['photoUrl'] as String?,
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Matches the wording already used on the user-side
  /// track_case_page.dart's `_CommunityReportSection._typeLabel`, so admin
  /// and reporter see the same label for the same report.
  String get typeLabel => switch (type) {
        'still_here' => 'Animal still here',
        'moved' => 'Animal moved',
        'rescued' => 'Animal rescued',
        'no_animal' => 'No animal present',
        _ => 'Update',
      };
}
