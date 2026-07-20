import 'package:cloud_firestore/cloud_firestore.dart';

String _animalSummary(List animals) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final a in animals) {
    final species = (a is Map ? a['species'] : null) as String?;
    if (species == null || species.isEmpty) continue;
    if (!counts.containsKey(species)) order.add(species);
    counts[species] = (counts[species] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  return order.map((s) {
    final c = counts[s]!;
    return '$c ${c == 1 ? s : '${s}s'}';
  }).join(', ');
}

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

    final animals = data['animals'] as List?;
    final animalSummary = (animals != null && animals.isNotEmpty)
        ? _animalSummary(animals)
        : (data['animalType'] as String? ?? '');

    return PublicRescueItem(
      caseId: doc.id,
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      address: (data['address'] as String? ?? '').trim().isEmpty
          ? '-'
          : data['address'] as String,
      latestStatusLabel: latestStatus,
      reporterTag: reporterTag,
      createdAt: ts?.toDate(),
      animalType: animalSummary,
      urgency: data['urgency'] as String? ?? '',
    );
  }
}