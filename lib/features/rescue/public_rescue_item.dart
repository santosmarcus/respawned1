import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight view model for a single card in the public rescue feed
/// (Explore Reports / Home preview). Built straight from a `cases` doc —
/// this feed is public, so it is never filtered down to a single reporter.
class PublicRescueItem {
  final String caseId;
  final List<String> photoUrls;
  final String address;
  final String latestStatusLabel;
  final String reporterTag;
  final DateTime? createdAt;
  final String animalType;
  final String urgency;

  const PublicRescueItem({
    required this.caseId,
    required this.photoUrls,
    required this.address,
    required this.latestStatusLabel,
    required this.reporterTag,
    required this.createdAt,
    required this.animalType,
    required this.urgency,
  });

  factory PublicRescueItem.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];
    final latestStatus = history.isNotEmpty
        ? (history.last['status'] as String? ?? 'Pending')
        : 'Pending';

    final ts = data['createdAt'] as Timestamp?;

    final reporterName = (data['reporterName'] as String? ?? '').trim();
    final reporterTag =
    reporterName.isNotEmpty ? 'Reported by $reporterName' : 'Reported by a community member';

    return PublicRescueItem(
      caseId: doc.id,
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      address: (data['address'] as String? ?? '').trim().isEmpty
          ? '-'
          : data['address'] as String,
      latestStatusLabel: latestStatus,
      reporterTag: reporterTag,
      createdAt: ts?.toDate(),
      animalType: data['animalType'] as String? ?? '',
      urgency: data['urgency'] as String? ?? '',
    );
  }
}