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
  final String docId;
  final String alertKind;
  final String? photoUrl;

  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.animalType,
    required this.urgency,
    required this.createdAt,
    required this.docId,
    this.alertKind = '',
    this.photoUrl,
  });

}