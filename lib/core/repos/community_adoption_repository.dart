import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/adoption/community_adoption.dart';

/// Writes for the lightweight Community Adoption path — see
/// community_adoption.dart's doc comment for how this differs from the
/// formal org-run adoption pipeline. Handles a case with more than one
/// animal (see rescue_page.dart's `animals[]` array) by letting each animal
/// be claimed independently — different people can adopt different animals
/// from the same case, and the case itself only closes once every animal in
/// it has been claimed.
class CommunityAdoptionRepository {
  final _adoptions = FirebaseFirestore.instance.collection('communityAdoptions');
  final _cases = FirebaseFirestore.instance.collection('cases');
  final _db = FirebaseFirestore.instance;

  /// How many animals a case actually covers — the `animals[]` array
  /// length, or 1 for a legacy single-animal case with no such array.
  /// Mirrors species_summary.dart's animalCountOf, duplicated here to avoid
  /// pulling in a rescue-feature util from a core repo.
  int totalAnimalCount(Map<String, dynamic> caseData) {
    final animals = caseData['animals'] as List?;
    return (animals != null && animals.isNotEmpty) ? animals.length : 1;
  }

  /// Which animal indexes in this case already have a Community Adoption
  /// claimed against them — so the listing screen can grey out/hide
  /// animals someone else already adopted. Prefers the case doc's own
  /// `claimedAnimalIndexes` field (kept in sync by [adopt] in the same
  /// transaction that creates each claim — the authoritative, race-free
  /// source), falling back to a `communityAdoptions` query for a case
  /// created before that field existed.
  Future<Set<int>> claimedAnimalIndexes(String caseId) async {
    final caseSnap = await _cases.doc(caseId).get();
    final fromCase = (caseSnap.data()?['claimedAnimalIndexes'] as List?)
        ?.map((e) => (e as num).toInt())
        .toSet();
    if (fromCase != null) return fromCase;

    final snap = await _adoptions.where('sourceCaseId', isEqualTo: caseId).get();
    return snap.docs.map((d) => (d.data()['animalIndex'] as num?)?.toInt() ?? 0).toSet();
  }

  /// Creates one `communityAdoptions` doc per animal being adopted in this
  /// submission (usually one, but a single adopter can claim more than one
  /// animal from the same multi-animal case in one go — e.g. taking home a
  /// pair of littermates).
  ///
  /// Race safety: the whole read-check-write sequence runs inside a single
  /// Firestore transaction against the case doc's own `claimedAnimalIndexes`
  /// field — that field (not a separate `communityAdoptions` query, which
  /// Firestore transactions can't read consistently) is the one thing both
  /// this call and a concurrent one are guaranteed to read-then-write
  /// atomically, so if two adopters submit for the same animal at nearly
  /// the same moment, Firestore's automatic transaction retry ensures only
  /// one of them actually creates a claim for that index; the other sees it
  /// already taken on retry and silently skips it. Returns the ids actually
  /// created — if that's fewer than requested, the caller should tell the
  /// adopter which animal(s) were no longer available rather than silently
  /// declaring full success.
  ///
  /// The source case only closes once every one of its animals has a claim
  /// — with animals still unclaimed, it stays open (and visible) so someone
  /// else can come adopt the rest.
  Future<List<String>> adopt({
    required List<CommunityAdoption> adoptions,
  }) async {
    if (adoptions.isEmpty) return const [];
    final caseId = adoptions.first.sourceCaseId;

    if (caseId == null) {
      final ids = <String>[];
      for (final adoption in adoptions) {
        final ref = await _adoptions.add(adoption.toCreateMap());
        ids.add(ref.id);
      }
      return ids;
    }

    final caseRef = _cases.doc(caseId);
    final createdIds = <String>[];

    await _db.runTransaction((tx) async {
      createdIds.clear();
      final caseSnap = await tx.get(caseRef);
      final caseData = caseSnap.data() ?? <String, dynamic>{};
      final total = totalAnimalCount(caseData);

      final claimedAlready = Set<int>.from(
        (caseData['claimedAnimalIndexes'] as List?)?.map((e) => (e as num).toInt()) ?? const <int>[],
      );

      final toCreate = adoptions.where((a) => !claimedAlready.contains(a.animalIndex)).toList();
      if (toCreate.isEmpty) return;

      // Adoptions of a case's animals belong to the organization that
      // accepted the case, when one has.
      final caseOrgId = caseData['organizationId'] as String?;
      final newIds = <String>[];
      for (final adoption in toCreate) {
        final ref = _adoptions.doc();
        tx.set(ref, {
          ...adoption.toCreateMap(),
          if (caseOrgId != null && caseOrgId.isNotEmpty) 'organizationId': caseOrgId,
        });
        newIds.add(ref.id);
      }
      createdIds.addAll(newIds);

      final claimedNow = {...claimedAlready, ...toCreate.map((a) => a.animalIndex)};
      final allClaimed = claimedNow.length >= total;

      final names = toCreate.map((a) => a.name).join(', ');
      final adopterName = toCreate.first.adopterName ?? 'A community member';
      final message = total > 1
          ? '$adopterName adopted $names through Community Adoption (${claimedNow.length} of $total animals now placed).'
          : '$adopterName adopted $names through Community Adoption.';

      tx.update(caseRef, {
        'communityAdoptionIds': FieldValue.arrayUnion(newIds),
        'claimedAnimalIndexes': claimedNow.toList(),
        if (allClaimed) 'status': 'closed',
        'statusHistory': FieldValue.arrayUnion([
          {'status': message, 'timestamp': Timestamp.now()}
        ]),
      });
    });

    return createdIds;
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
