import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart'
as community_adoption_util;

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
  final double? lat;
  final double? lng;
  final String? rawStatus;
  final String? rejectionReason;
  final String? rescueType;

  const PublicRescueItem({
    required this.caseId,
    required this.photoUrls,
    required this.address,
    required this.latestStatusLabel,
    required this.reporterTag,
    required this.createdAt,
    required this.animalType,
    required this.urgency,
    this.lat,
    this.lng,
    this.rawStatus,
    this.rejectionReason,
    this.rescueType,
  });

  /// True for a healthy/low-urgency report that was rejected (and isn't a
  /// Lost Pet report) — see community_adoption_eligibility.dart. Feed/card
  /// UI uses this to keep the item visible and offer the Community
  /// Adoption listing action instead of hiding it like any other
  /// rejection.
  bool get isCommunityAdoptionEligible =>
      community_adoption_util.isCommunityAdoptionEligible(
        status: rawStatus,
        rejectionReason: rejectionReason,
        rescueType: rescueType,
      );

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
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      rawStatus: data['status'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      rescueType: data['rescueType'] as String?,
    );
  }
}