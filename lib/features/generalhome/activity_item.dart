enum ActivityType { rescue, adoption, lostFoundPet }

class ActivityItem{
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final String status;
  final String animalType;
  final String urgency;
  final DateTime? createdAt;
  // Timestamp of the most recent status update (falls back to createdAt
  // when there's no history yet) — Activity sorts by this, not createdAt
  // alone, so an older report that just received a new update resurfaces
  // to the top instead of staying buried at its original creation slot.
  final DateTime? lastUpdatedAt;
  final String docId;
  final String alertKind;
  final String? photoUrl;

  /// Rejected Rescue Reports spec §2 — a rejected report is no longer
  /// dropped from this feed; these fields carry the extra rejection
  /// details/actions the card renders instead of the normal status row.
  /// Always false/null for non-rescue items and non-rejected rescue items.
  final bool isRejected;
  final String? rejectionReasonLabel;
  final DateTime? rejectedAt;
  final bool communityAdoptionEligible;

  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.animalType,
    required this.urgency,
    required this.createdAt,
    DateTime? lastUpdatedAt,
    required this.docId,
    this.alertKind = '',
    this.photoUrl,
    this.isRejected = false,
    this.rejectionReasonLabel,
    this.rejectedAt,
    this.communityAdoptionEligible = false,
  }) : lastUpdatedAt = lastUpdatedAt ?? createdAt;

}