import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a [CommunityAdoptionRequest] is in the rehoming flow.
enum CommunityRequestStatus {
  /// The adopter expressed interest; the reporter hasn't decided yet.
  pending,

  /// The reporter chose this adopter; both now sign the agreement.
  selected,

  /// Both signed and the animal(s) are adopted.
  completed,

  /// The reporter turned this adopter down.
  declined,

  /// The adopter withdrew their interest.
  withdrawn;

  static CommunityRequestStatus fromName(String? name) =>
      CommunityRequestStatus.values.firstWhere(
            (s) => s.name == name,
        orElse: () => CommunityRequestStatus.pending,
      );

  String get label => switch (this) {
    pending => 'Interested',
    selected => 'Chosen — awaiting agreement',
    completed => 'Adopted',
    declined => 'Declined',
    withdrawn => 'Withdrawn',
  };

  bool get isOpen => this == pending || this == selected;
}

/// One signature on the community adoption agreement: the full name the
/// person typed and when they signed.
class AgreementSignature {
  final String name;
  final DateTime? signedAt;
  const AgreementSignature({required this.name, this.signedAt});

  static AgreementSignature? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['signedAt'];
    return AgreementSignature(
      name: raw['name'] as String? ?? '',
      signedAt: at is Timestamp ? at.toDate() : null,
    );
  }
}

/// `communityAdoptionRequests/{id}` — someone's interest in adopting one or
/// more animals from a Community-Adoption-eligible report.
///
/// The report's reporter (the "lister") never adopts their own report's
/// animals. Instead they manage the listing: interested adopters create a
/// request, the two talk in the request's `messages` subcollection, the
/// lister chooses one adopter, and both sign the community adoption
/// agreement. The second signature completes the adoption, creating the
/// `communityAdoptions` record(s) the existing check-in flow builds on.
class CommunityAdoptionRequest {
  final String id;
  final String caseId;
  final String listerId;
  final String listerName;
  final String adopterId;
  final String adopterName;
  final String adopterContact;
  final String introMessage;
  final List<int> animalIndexes;
  final List<String> animalLabels;
  final CommunityRequestStatus status;
  final AgreementSignature? listerSignature;
  final AgreementSignature? adopterSignature;
  final List<String> communityAdoptionIds;
  final DateTime? createdAt;
  final DateTime? selectedAt;
  final DateTime? declinedAt;
  final DateTime? completedAt;

  const CommunityAdoptionRequest({
    required this.id,
    required this.caseId,
    required this.listerId,
    required this.listerName,
    required this.adopterId,
    required this.adopterName,
    required this.adopterContact,
    required this.introMessage,
    required this.animalIndexes,
    required this.animalLabels,
    required this.status,
    this.listerSignature,
    this.adopterSignature,
    this.communityAdoptionIds = const [],
    this.createdAt,
    this.selectedAt,
    this.declinedAt,
    this.completedAt,
  });

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  factory CommunityAdoptionRequest.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CommunityAdoptionRequest(
      id: doc.id,
      caseId: d['caseId'] as String? ?? '',
      listerId: d['listerId'] as String? ?? '',
      listerName: d['listerName'] as String? ?? 'The reporter',
      adopterId: d['adopterId'] as String? ?? '',
      adopterName: d['adopterName'] as String? ?? 'A community member',
      adopterContact: d['adopterContact'] as String? ?? '',
      introMessage: d['introMessage'] as String? ?? '',
      animalIndexes: [
        for (final i in d['animalIndexes'] as List? ?? const [])
          (i as num).toInt(),
      ],
      animalLabels: List<String>.from(d['animalLabels'] ?? const []),
      status: CommunityRequestStatus.fromName(d['status'] as String?),
      listerSignature: AgreementSignature.fromMap(d['listerSignature']),
      adopterSignature: AgreementSignature.fromMap(d['adopterSignature']),
      communityAdoptionIds: List<String>.from(
        d['communityAdoptionIds'] ?? const [],
      ),
      createdAt: _date(d['createdAt']),
      selectedAt: _date(d['selectedAt']),
      declinedAt: _date(d['declinedAt']),
      completedAt: _date(d['completedAt']),
    );
  }

  String get animalsLabel => animalLabels.isEmpty
      ? 'this animal'
      : animalLabels.length == 1
      ? animalLabels.first
      : '${animalLabels.sublist(0, animalLabels.length - 1).join(', ')} and '
      '${animalLabels.last}';

  bool isLister(String? uid) => uid != null && uid == listerId;
  bool isAdopter(String? uid) => uid != null && uid == adopterId;
}

/// A chat message under `communityAdoptionRequests/{id}/messages`.
class CommunityRequestMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime? sentAt;
  const CommunityRequestMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.sentAt,
  });

  factory CommunityRequestMessage.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final at = d['sentAt'];
    return CommunityRequestMessage(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      senderName: d['senderName'] as String? ?? '',
      text: d['text'] as String? ?? '',
      sentAt: at is Timestamp ? at.toDate() : null,
    );
  }
}
