import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/adoption/community_adoption.dart';

/// Writes for the lightweight Community Adoption path — see
/// community_adoption.dart's doc comment for how this differs from the
/// formal org-run adoption pipeline. Handles a case with more than one
/// animal (see rescue_page.dart's `animals[]` array) by letting each
/// animal be claimed independently — different people can adopt different
/// animals from the same case, and the case itself only closes once every
/// animal in it has been claimed.
class CommunityAdoptionRepository {
  final _adoptions = FirebaseFirestore.instance.collection('communityAdoptions');
  final _cases = FirebaseFirestore.instance.collection('cases');

  /// How many animals a case actually covers — the `animals[]` array
  /// length, or 1 for a legacy single-animal case with no such array.
  /// Mirrors species_summary.dart's animalCountOf, duplicated here to
  /// avoid pulling in a rescue-feature util from a core repo.
  int totalAnimalCount(Map<String, dynamic> caseData) {
    final animals = caseData['animals'] as List?;
    return (animals != null && animals.isNotEmpty) ? animals.length : 1;
  }

  /// Which animal indexes in this case already have a Community Adoption
  /// claimed against them — so the listing screen can grey out/hide
  /// animals someone else already adopted, and so two adopters can never
  /// both submit for the same index.
  Future<Set<int>> claimedAnimalIndexes(String caseId) async {
    final snap = await _adoptions.where('sourceCaseId', isEqualTo: caseId).get();
    return snap.docs.map((d) => (d.data()['animalIndex'] as num?)?.toInt() ?? 0).toSet();
  }

  /// Creates one `communityAdoptions` doc per animal being adopted in this
  /// submission (usually one, but a single adopter can claim more than one
  /// animal from the same multi-animal case in one go — e.g. taking home a
  /// pair of littermates). Re-checks claimed indexes immediately before
  /// writing (not just whatever the screen loaded with) to guard against
  /// two people submitting for the same animal at nearly the same time;
  /// any requested index that's already claimed by then is silently
  /// skipped rather than double-booked. Returns the ids actually created.
  ///
  /// The source case only closes once every one of its animals has a
  /// claim — with animals still unclaimed, it stays open (and visible) so
  /// someone else can come adopt the rest.
  Future<List<String>> adopt({
    required List<CommunityAdoption> adoptions,
  }) async {
    if (adoptions.isEmpty) return const [];
    final caseId = adoptions.first.sourceCaseId;

    final alreadyClaimed = caseId != null ? await claimedAnimalIndexes(caseId) : <int>{};
    final toCreate = adoptions.where((a) => !alreadyClaimed.contains(a.animalIndex)).toList();
    if (toCreate.isEmpty) return const [];

    final ids = <String>[];
    for (final adoption in toCreate) {
      final ref = await _adoptions.add(adoption.toCreateMap());
      ids.add(ref.id);
    }

    if (caseId != null) {
      final caseSnap = await _cases.doc(caseId).get();
      final caseData = caseSnap.data() ?? {};
      final total = totalAnimalCount(caseData);
      final claimedNow = alreadyClaimed.length + toCreate.length;
      final allClaimed = claimedNow >= total;

      final names = toCreate.map((a) => a.name).join(', ');
      final adopterName = toCreate.first.adopterName ?? 'A community member';
      final message = total > 1
          ? '$adopterName adopted $names through Community Adoption ($claimedNow of $total animals now placed).'
          : '$adopterName adopted $names through Community Adoption.';

      await _cases.doc(caseId).update({
        'communityAdoptionIds': FieldValue.arrayUnion(ids),
        if (allClaimed) 'status': 'closed',
        'statusHistory': FieldValue.arrayUnion([
          {'status': message, 'timestamp': Timestamp.now()}
        ]),
      });
    }

    return ids;
  }

  Stream<List<CommunityAdoption>> watchAdoptionsForCase(String caseId) {
    return _adoptions
        .where('sourceCaseId', isEqualTo: caseId)
        .snapshots()
        .map((snap) => snap.docs.map(CommunityAdoption.fromFirestore).toList());
  }

  Stream<List<CommunityAdoption>> watchByAdopter(String adopterId) {
    return _adoptions
        .where('adopterId', isEqualTo: adopterId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(CommunityAdoption.fromFirestore).toList());
  }
}