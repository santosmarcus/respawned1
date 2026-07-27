import 'package:cloud_firestore/cloud_firestore.dart';

/// A sponsorship's lifecycle state. 'active' is the only state shown on
/// the user Home screen's Sponsored Animals section — cancelled/expired
/// sponsorships belong in a separate history view, never mixed into the
/// active list (spec: "Do not include cancelled or expired sponsorships as
/// active").
enum SponsorshipStatus {
  active,
  cancelled,
  expired;

  static SponsorshipStatus fromName(String? value) =>
      SponsorshipStatus.values.firstWhere((v) => v.name == value, orElse: () => SponsorshipStatus.active);

  String get label => switch (this) {
        SponsorshipStatus.active => 'Active',
        SponsorshipStatus.cancelled => 'Cancelled',
        SponsorshipStatus.expired => 'Expired',
      };
}

/// One `sponsors/{id}` document — the SAME collection `_SponsorsRow`
/// (lib/features/adoption/animal_page.dart) already reads for a bare
/// sponsor count, not a second sponsorship collection. No writer for this
/// collection exists anywhere in the codebase yet (confirmed by
/// inspection) — this is the first typed model/schema for it, designed to
/// be joined against the real `animals/{id}` AnimalRecord doc for its
/// profile image rather than storing/trusting a separate photo field.
class Sponsorship {
  final String id;
  final String userId;
  final String organizationId;
  // Denormalized display fallback only — the profile image and current
  // name are always read live from the joined AnimalRecord, never from
  // here (spec: "Use the Animal Record profile image", never a stale
  // snapshot).
  final String organizationName;
  final String animalRecordId;
  final String animalName;
  final SponsorshipStatus status;
  final DateTime? startDate;
  final DateTime? nextContributionDate;
  final String? cycle; // e.g. 'monthly', 'quarterly' — optional/unset when not tracked.
  final DateTime? createdAt;

  const Sponsorship({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.organizationName,
    required this.animalRecordId,
    required this.animalName,
    required this.status,
    this.startDate,
    this.nextContributionDate,
    this.cycle,
    this.createdAt,
  });

  factory Sponsorship.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return Sponsorship(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      organizationId: data['organizationId'] as String? ?? '',
      organizationName: data['organizationName'] as String? ?? '',
      animalRecordId: data['animalRecordId'] as String? ?? '',
      animalName: data['animalName'] as String? ?? '',
      status: SponsorshipStatus.fromName(data['status'] as String?),
      startDate: ts(data['startDate']),
      nextContributionDate: ts(data['nextContributionDate']),
      cycle: data['cycle'] as String?,
      createdAt: ts(data['createdAt']),
    );
  }
}
