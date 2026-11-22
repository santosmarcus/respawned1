import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/adoption/community_adoption.dart';
import 'package:respawnd1/core/models/adoption/community_adoption_request.dart';
import 'package:respawnd1/core/repos/community_adoption_repository.dart';
import 'package:respawnd1/core/models/rescue/surrender_withdrawal.dart';

/// Reads and writes for the reporter-managed Community Adoption flow —
/// see [CommunityAdoptionRequest] for the whole sequence.
class CommunityAdoptionRequestRepository {
  CommunityAdoptionRequestRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('communityAdoptionRequests');

  // ---- Adoption profile ---------------------------------------------------

  /// The reporter's adoption profile for each animal, keyed by animal
  /// index (`communityListing.animals.<index>` on the case; see
  /// community_profile.dart).
  static Map<int, Map<String, dynamic>> listingDetailsOf(
      Map<String, dynamic> caseData,
      ) {
    final animals = (caseData['communityListing'] as Map?)?['animals'];
    if (animals is! Map) return {};
    return {
      for (final e in animals.entries)
        if (int.tryParse('${e.key}') != null && e.value is Map)
          int.parse('${e.key}'): Map<String, dynamic>.from(e.value as Map),
    };
  }

  /// Saves one animal's profile without touching the others.
  Future<void> saveAnimalProfile(
      String caseId,
      int index,
      Map<String, dynamic> profile,
      ) {
    return _db.collection('cases').doc(caseId).update({
      'communityListing.animals.$index': profile,
      'communityListing.updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// A label for each animal in the report: the reporter's name for it,
  /// otherwise "Dog 1", "Cat 1", …
  static List<String> animalLabelsOf(Map<String, dynamic> caseData) {
    final animals =
        (caseData['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final total = animals.isEmpty ? 1 : animals.length;
    final details = listingDetailsOf(caseData);
    final ordinal = <String, int>{};
    return [
      for (var i = 0; i < total; i++)
            () {
          final species =
          ((i < animals.length ? animals[i]['species'] : null) ??
              (i == 0 ? caseData['animalType'] : null) ??
              'Animal')
              .toString();
          final n = (ordinal[species] ?? 0) + 1;
          ordinal[species] = n;
          final named = (details[i]?['name'] as String?)?.trim() ?? '';
          return named.isNotEmpty ? named : '$species $n';
        }(),
    ];
  }

  // ---- Requests -------------------------------------------------------------

  Future<String> createRequest({
    required String caseId,
    required String listerId,
    required String listerName,
    required String adopterId,
    required String adopterName,
    required String adopterContact,
    required String introMessage,
    required List<int> animalIndexes,
    required List<String> animalLabels,
  }) async {
    final ref = await _requests.add({
      'caseId': caseId,
      'listerId': listerId,
      'listerName': listerName,
      'adopterId': adopterId,
      'adopterName': adopterName,
      'adopterContact': adopterContact,
      'introMessage': introMessage,
      'animalIndexes': animalIndexes,
      'animalLabels': animalLabels,
      'status': CommunityRequestStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (introMessage.trim().isNotEmpty) {
      await sendMessage(
        requestId: ref.id,
        senderId: adopterId,
        senderName: adopterName,
        text: introMessage.trim(),
      );
    }
    return ref.id;
  }

  Stream<CommunityAdoptionRequest?> watchRequest(String requestId) => _requests
      .doc(requestId)
      .snapshots()
      .map((d) => d.exists ? CommunityAdoptionRequest.fromFirestore(d) : null);

  /// Every request on [caseId], for its reporter.
  Stream<List<CommunityAdoptionRequest>> watchForLister({
    required String caseId,
    required String listerId,
  }) => _requests
      .where('caseId', isEqualTo: caseId)
      .where('listerId', isEqualTo: listerId)
      .snapshots()
      .map(_sorted);

  /// The current user's own requests on [caseId], newest first.
  Stream<List<CommunityAdoptionRequest>> watchForAdopter({
    required String caseId,
    required String adopterId,
  }) => _requests
      .where('caseId', isEqualTo: caseId)
      .where('adopterId', isEqualTo: adopterId)
      .snapshots()
      .map(_sorted);

  static List<CommunityAdoptionRequest> _sorted(
      QuerySnapshot<Map<String, dynamic>> snap,
      ) {
    final list = snap.docs.map(CommunityAdoptionRequest.fromFirestore).toList();
    list.sort(
          (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return list;
  }

  Future<void> _setStatus(
      String requestId,
      CommunityRequestStatus status, {
        Map<String, dynamic> extra = const {},
      }) => _requests.doc(requestId).update({
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
    ...extra,
  });

  /// The reporter chooses this adopter; both are then asked to sign.
  Future<void> choose(String requestId) => _setStatus(
    requestId,
    CommunityRequestStatus.selected,
    extra: {'selectedAt': FieldValue.serverTimestamp()},
  );

  Future<void> decline(String requestId) => _setStatus(
    requestId,
    CommunityRequestStatus.declined,
    extra: {'declinedAt': FieldValue.serverTimestamp()},
  );

  Future<void> withdraw(String requestId) => _setStatus(
    requestId,
    CommunityRequestStatus.withdrawn,
    extra: {'withdrawnAt': FieldValue.serverTimestamp()},
  );

  // ---- Pet Surrender withdrawal ----------------------------------------------

  /// The reporter withdraws their Pet Surrender: the case goes to
  /// 'withdrawn' (archived, never deleted) with the reason, which takes it
  /// off Community Adoption (the listing and new inquiries only accept
  /// active cases). Open inquiries are then declined, each with a note to
  /// the adopter. Adoptions already completed stay as they are.
  ///
  /// Throws [StateError] if the case is no longer active (already
  /// withdrawn, adopted or closed), so a second tap can't withdraw twice.
  /// Returns how many open inquiries were closed.
  Future<int> withdrawSurrender({
    required String caseId,
    required String reporterId,
    required String reporterName,
    required SurrenderWithdrawalReason reason,
    String? otherText,
    String? details,
  }) async {
    final caseRef = _db.collection('cases').doc(caseId);
    final reasonText = reason == SurrenderWithdrawalReason.other && (otherText ?? '').trim().isNotEmpty
        ? otherText!.trim()
        : reason.label;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) throw StateError('This report no longer exists.');
      if (data['reporterId'] != reporterId) {
        throw StateError('Only the person who filed this surrender can withdraw it.');
      }
      if (!canWithdrawSurrender(data)) {
        throw StateError('This surrender request is no longer active, so it can\'t be withdrawn.');
      }
      tx.update(caseRef, {
        'status': 'withdrawn',
        'surrenderWithdrawal': {
          'reason': reason.name,
          if ((otherText ?? '').trim().isNotEmpty) 'otherText': otherText!.trim(),
          if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
          'previousStatus': data['status'],
          'withdrawnAt': FieldValue.serverTimestamp(),
          'withdrawnBy': reporterId,
        },
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Surrender request withdrawn: $reasonText.', 'timestamp': Timestamp.now()},
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Inquiries still waiting on the reporter are closed, with a note, so
    // nobody is left waiting on an animal that is no longer offered.
    final open = await _requests
        .where('caseId', isEqualTo: caseId)
        .where('listerId', isEqualTo: reporterId)
        .get();
    var closed = 0;
    for (final doc in open.docs) {
      final status = doc.data()['status'];
      if (status != CommunityRequestStatus.pending.name && status != CommunityRequestStatus.selected.name) continue;
      await _setStatus(doc.id, CommunityRequestStatus.declined, extra: {
        'declinedAt': FieldValue.serverTimestamp(),
        'declinedBecause': 'surrender_withdrawn',
      });
      await sendMessage(
        requestId: doc.id,
        senderId: reporterId,
        senderName: reporterName,
        text: 'This surrender request has been withdrawn, so this adoption inquiry is now closed. '
            'Thank you for your interest in giving this pet a home.',
      );
      closed++;
    }
    return closed;
  }

  // ---- Messages -------------------------------------------------------------

  Stream<List<CommunityRequestMessage>> watchMessages(String requestId) =>
      _requests
          .doc(requestId)
          .collection('messages')
          .orderBy('sentAt')
          .snapshots()
          .map(
            (s) => s.docs.map(CommunityRequestMessage.fromFirestore).toList(),
      );

  Future<void> sendMessage({
    required String requestId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    await _requests.doc(requestId).collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
    });
    await _requests.doc(requestId).update({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': senderId,
    });
  }

  // ---- Agreement --------------------------------------------------------------

  /// Records the current user's signature. When both parties have signed,
  /// completes the adoption and returns true.
  Future<bool> sign({
    required CommunityAdoptionRequest request,
    required bool asLister,
    required String fullName,
  }) async {
    final ref = _requests.doc(request.id);
    final field = asLister ? 'listerSignature' : 'adopterSignature';
    final otherField = asLister ? 'adopterSignature' : 'listerSignature';
    final bothSigned = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? const <String, dynamic>{};
      if (data['status'] != CommunityRequestStatus.selected.name) {
        throw StateError('This request is no longer awaiting the agreement.');
      }
      tx.update(ref, {
        field: {'name': fullName, 'signedAt': FieldValue.serverTimestamp()},
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return data[otherField] is Map;
    });
    if (!bothSigned) return false;
    await _complete(request);
    return true;
  }

  /// Creates the `communityAdoptions` record(s) for the chosen adopter and
  /// marks the request completed. Safe to run twice: the adoption
  /// repository skips animals already claimed.
  Future<void> _complete(CommunityAdoptionRequest request) async {
    final caseSnap = await _db.collection('cases').doc(request.caseId).get();
    final caseData = caseSnap.data() ?? const <String, dynamic>{};
    final details = listingDetailsOf(caseData);
    final animals =
        (caseData['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final casePhotos = List<String>.from(caseData['photoUrls'] ?? const []);

    final adoptions = <CommunityAdoption>[
      for (var k = 0; k < request.animalIndexes.length; k++)
        _adoptionFor(
          request: request,
          index: request.animalIndexes[k],
          label: k < request.animalLabels.length
              ? request.animalLabels[k]
              : 'Animal ${request.animalIndexes[k] + 1}',
          raw: request.animalIndexes[k] < animals.length
              ? Map<String, dynamic>.from(animals[request.animalIndexes[k]])
              : const {},
          caseData: caseData,
          details: details[request.animalIndexes[k]] ?? const {},
          casePhotos: animals.length <= 1 ? casePhotos : const [],
        ),
    ];

    final ids = await CommunityAdoptionRepository().adopt(adoptions: adoptions);
    await _setStatus(
      request.id,
      CommunityRequestStatus.completed,
      extra: {
        'completedAt': FieldValue.serverTimestamp(),
        if (ids.isNotEmpty) 'communityAdoptionIds': ids,
      },
    );
  }

  CommunityAdoption _adoptionFor({
    required CommunityAdoptionRequest request,
    required int index,
    required String label,
    required Map<String, dynamic> raw,
    required Map<String, dynamic> caseData,
    required Map<String, dynamic> details,
    required List<String> casePhotos,
  }) {
    String? pick(String key, [String? caseKey]) =>
        (raw[key] as String?) ??
            (index == 0 ? caseData[caseKey ?? key] as String? : null);
    // The reporter's adoption profile wins where filled in.
    String? profile(String key) {
      final v = (details[key] as String?)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return CommunityAdoption(
      id: '',
      sourceCaseId: request.caseId,
      animalIndex: index,
      photoUrls: casePhotos,
      name: profile('name') ?? label,
      species: pick('species', 'animalType') ?? '',
      breed: pick('breed'),
      size: profile('size') ?? pick('size'),
      sex: profile('sex') ?? pick('sex'),
      description:
      (details['about'] as String?) ?? (caseData['condition'] as String?),
      rescuedBy: request.listerName,
      address: caseData['address'] as String?,
      lat: (caseData['lat'] as num?)?.toDouble(),
      lng: (caseData['lng'] as num?)?.toDouble(),
      adopterId: request.adopterId,
      adopterName: request.adopterName,
      adopterContact: request.adopterContact,
      agreementAccepted: true,
      listingDetails: details,
      requestId: request.id,
      rehomedById: request.listerId,
    );
  }
}
