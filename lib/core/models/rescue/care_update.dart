import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/media_ref.dart';

/// What a carer (or staff) is reporting about an animal.
enum CareUpdateType {
  observation,
  vetFollowUp,
  feeding;

  String get label => switch (this) {
        CareUpdateType.observation => 'Observation',
        CareUpdateType.vetFollowUp => 'Vet follow-up',
        CareUpdateType.feeding => 'Feeding',
      };

  static CareUpdateType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => CareUpdateType.observation);
}

/// `animals/{animalId}/careUpdates/{id}`: a dated note from the person
/// looking after the animal, with optional photos or videos. Carers of the
/// owning organization add their own; nobody edits them afterwards
/// (firestore.rules).
class CareUpdate {
  final String id;
  final String animalId;
  final CareUpdateType type;
  final String note;
  final List<MediaRef> media;
  final String authorId;
  final String? authorName;
  final DateTime? createdAt;

  const CareUpdate({
    required this.id,
    required this.animalId,
    required this.type,
    required this.note,
    this.media = const [],
    required this.authorId,
    this.authorName,
    this.createdAt,
  });

  factory CareUpdate.fromDoc(String animalId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CareUpdate(
      id: doc.id,
      animalId: animalId,
      type: CareUpdateType.fromName(d['type'] as String?),
      note: d['note'] as String? ?? '',
      media: MediaRef.fromLists(
        List<String>.from(d['mediaUrls'] as List? ?? const []),
        List<String>.from(d['mediaTypes'] as List? ?? const []),
      ),
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  static Map<String, dynamic> newDoc({
    required CareUpdateType type,
    required String note,
    required List<MediaRef> media,
    required String authorId,
    String? authorName,
  }) =>
      {
        'type': type.name,
        'note': note.trim(),
        'mediaUrls': [for (final m in media) m.url],
        'mediaTypes': [for (final m in media) m.isVideo ? 'video' : 'image'],
        'authorId': authorId,
        'authorName': ?authorName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
