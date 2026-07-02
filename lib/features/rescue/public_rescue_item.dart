import 'package:cloud_firestore/cloud_firestore.dart';

class PublicRescueItem {
  final String caseId;
  final String address;
  final String animalType;
  final String condition;
  final String urgency;
  final String status;
  final String latestStatusLabel;
  final String reporterTag;
  final List<String> photoUrls;
  final DateTime? createdAt;

  const PublicRescueItem({
    required this.caseId,
    required this.address,
    required this.animalType,
    required this.condition,
    required this.urgency,
    required this.status,
    required this.latestStatusLabel,
    required this.reporterTag,
    required this.photoUrls,
    required this.createdAt,
  });

  factory PublicRescueItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final ts = data['createdAt'];
    final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];
    final latestStatusLabel =
    history.isNotEmpty ? history.last['status'] as String? ?? 'Pending' : 'Pending';
    final reporterId = data['reporterId'] as String? ?? '';
    final reporterTag =
        'user${reporterId.length >= 8 ? reporterId.substring(0, 8) : reporterId}';

    return PublicRescueItem(
      caseId: doc.id,
      address: (data['address'] as String?)?.trim().isNotEmpty == true
          ? data['address'] as String
          : 'Location unspecified',
      animalType: data['animalType'] as String? ?? 'Animal',
      condition: data['condition'] as String? ?? '',
      urgency: data['urgency'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      latestStatusLabel: latestStatusLabel,
      reporterTag: reporterTag,
      photoUrls: List<String>.from(data['photoUrls'] ?? const []),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}