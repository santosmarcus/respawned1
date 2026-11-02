// Split out of rescue_case_repository.dart (behavior-preserving refactor).
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/species_summary.dart'
    as species_summary_util;

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Duplicate detection and merging of rescue cases.
class CaseDuplicateRepository {
  CaseDuplicateRepository(this._store);

  final RescueCaseStore _store;

  /// Naive possible-duplicate lookup: other active cases (pending/awaiting
  /// assignment/ongoing) of the same species, ranked by distance from
  /// [source]. There's no geohashing index on this collection, so this
  /// pulls a bounded window of same-species active cases and computes
  /// distance client-side rather than doing a true geo query.
  Future<List<RescueCase>> findPossibleDuplicates(
    RescueCase source, {
    double radiusKm = 1.0,
    int limit = 20,
  }) async {
    final sourceSpecies = source.allSpecies.toSet();
    if (sourceSpecies.isEmpty || source.lat == null || source.lng == null) {
      return const [];
    }
    final activeStatuses = [
      RescueStatus.pendingReview,
      RescueStatus.accepted,
      RescueStatus.awaitingAssignment,
      RescueStatus.ongoing,
    ].expand((s) => s.queryValues).toSet().toList();

    // A case's animals live in an `animals[]` array — Firestore can't do
    // an "any of these species" match against a sub-field of an array of
    // maps, so this runs one query per distinct species the source report
    // covers (never just its first/legacy animalType) and merges the
    // results, so a duplicate that only shares the source's second animal
    // still gets found. Each query still only matches a *candidate* case's
    // own top-level `animalType` (that candidate's first/legacy species) —
    // a true match against every one of a candidate's own animals would
    // need a denormalized queryable field this collection doesn't have yet.
    final seenIds = <String>{};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final species in sourceSpecies) {
      final snap = await _store.cases
          .where('animalType', isEqualTo: species)
          .where('status', whereIn: activeStatuses)
          .limit(50)
          .get();
      for (final doc in snap.docs) {
        if (seenIds.add(doc.id)) docs.add(doc);
      }
    }

    // Pairs the admin already explicitly reviewed and dismissed via "Keep
    // Separate" (see keepSeparate) are never re-suggested — unless the
    // source case's own location/species changed since (a coarse "did
    // meaningful data change" signal: this whole method already re-derives
    // candidates from the CURRENT source animals/lat/lng every call, so
    // a source that moved or was re-typed naturally produces a different
    // candidate set anyway; the dismissed-id list itself is never
    // invalidated automatically beyond that).
    final dismissed =
        (source.raw['dismissedDuplicateCaseIds'] as List?)
            ?.cast<String>()
            .toSet() ??
        const {};

    final candidates = docs
        .map(RescueCase.fromFirestore)
        .where(
          (c) =>
              c.id != source.id &&
              c.lat != null &&
              c.lng != null &&
              !dismissed.contains(c.id),
        )
        .toList();

    candidates.sort((a, b) {
      final da = _distanceKm(source.lat!, source.lng!, a.lat!, a.lng!);
      final db = _distanceKm(source.lat!, source.lng!, b.lat!, b.lng!);
      return da.compareTo(db);
    });

    return candidates
        .where(
          (c) =>
              _distanceKm(source.lat!, source.lng!, c.lat!, c.lng!) <= radiusKm,
        )
        .take(limit)
        .toList();
  }

  double distanceKmBetween(RescueCase a, RescueCase b) {
    if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) {
      return double.infinity;
    }
    return _distanceKm(a.lat!, a.lng!, b.lat!, b.lng!);
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    double deg2rad(double deg) => deg * (math.pi / 180.0);
    final dLat = deg2rad(lat2 - lat1);
    final dLng = deg2rad(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(deg2rad(lat1)) *
            math.cos(deg2rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  Future<void> flagPossibleDuplicate({
    required String caseId,
    required String duplicateOfCaseId,
    required String actorUid,
    required String actorName,
  }) async {
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.possibleDuplicate.firestoreValue,
      'possibleDuplicateOfCaseId': duplicateOfCaseId,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Flagged as a possible duplicate report.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'flagged_possible_duplicate',
      actorUid: actorUid,
      actorName: actorName,
      details: {'duplicateOfCaseId': duplicateOfCaseId},
    );
  }

  /// Reverts a possibleDuplicate case back to normal triage after the org
  /// decides the two reports are NOT the same incident.
  ///
  /// [dismissedCandidateIds] — the candidate case id(s) actually shown and
  /// dismissed (from possible_duplicate_sheet.dart) — recorded onto
  /// `dismissedDuplicateCaseIds` so findPossibleDuplicates never
  /// re-suggests this exact pair to this case again.
  Future<void> keepSeparate({
    required String caseId,
    required String actorUid,
    required String actorName,
    List<String> dismissedCandidateIds = const [],
  }) async {
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.pendingReview.firestoreValue,
      'possibleDuplicateOfCaseId': FieldValue.delete(),
      if (dismissedCandidateIds.isNotEmpty)
        'dismissedDuplicateCaseIds': FieldValue.arrayUnion(
          dismissedCandidateIds,
        ),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Confirmed as a separate, unrelated report.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'kept_separate',
      actorUid: actorUid,
      actorName: actorName,
    );
  }

  /// Merges [duplicateCaseId] into [primaryCaseId]. The duplicate case is
  /// never deleted: it's marked `merged` with `mergedIntoCaseId` set, its
  /// own reporter/media/location/description are copied into a new report
  /// under the primary case's `reports` subcollection, and both case docs
  /// get a matching statusHistory entry so each reporter's own tracker
  /// (which reads its own case doc) sees the update. Each case's private
  /// `messages` subcollection is untouched, so per-reporter chats stay
  /// private while both see the same shared status update.
  Future<void> mergeDuplicate({
    required String primaryCaseId,
    required String duplicateCaseId,
    required String actorUid,
    required String actorName,
  }) async {
    final primaryRef = _store.caseDoc(primaryCaseId);
    final duplicateRef = _store.caseDoc(duplicateCaseId);
    final newReportRef = _store.reportsOf(primaryCaseId).doc(duplicateCaseId);

    await _store.db.runTransaction((tx) async {
      final primarySnap = await tx.get(primaryRef);
      final duplicateSnap = await tx.get(duplicateRef);
      if (!primarySnap.exists || !duplicateSnap.exists) {
        throw StateError('Both cases must exist to merge.');
      }
      final duplicateData = duplicateSnap.data()!;

      tx.set(newReportRef, {
        'reporterId': duplicateData['reporterId'],
        'reporterName': duplicateData['reporterName'],
        'reporterPhone': duplicateData['reporterPhone'],
        'description': duplicateData['condition'],
        'photoUrls': duplicateData['photoUrls'] ?? const [],
        'address': duplicateData['address'],
        'lat': duplicateData['lat'],
        'lng': duplicateData['lng'],
        // Full species summary (e.g. "Dog ×2, Cat"), not just the
        // duplicate's first/legacy animalType — a merged multi-animal
        // report should still show every species it covered.
        'species': species_summary_util.summarizeSpecies(
          animals: duplicateData['animals'] as List?,
          legacyAnimalType: duplicateData['animalType'] as String?,
        ),
        'urgency': duplicateData['urgency'],
        'submittedAt':
            duplicateData['createdAt'] ?? FieldValue.serverTimestamp(),
        'isPrimary': false,
        'sourceCaseId': duplicateCaseId,
      });

      final sharedUpdateText =
          'This report was merged with another matching report for the same rescue.';

      tx.update(duplicateRef, {
        'status': RescueStatus.merged.firestoreValue,
        'mergedIntoCaseId': primaryCaseId,
        'statusHistory': FieldValue.arrayUnion([
          {'status': sharedUpdateText, 'timestamp': Timestamp.now()},
        ]),
      });

      tx.update(primaryRef, {
        'mergedCaseIds': FieldValue.arrayUnion([duplicateCaseId]),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'A duplicate report for this case was merged in.',
            'timestamp': Timestamp.now(),
          },
        ]),
      });

      final logBase = ActivityLogEntry(
        id: '',
        caseId: '',
        action: 'merged',
        actorUid: actorUid,
        actorName: actorName,
      );
      tx.set(_store.activityLogsOf(primaryCaseId).doc(), {
        ...logBase.toFirestore(),
        'details': {'duplicateCaseId': duplicateCaseId, 'role': 'primary'},
      });
      tx.set(_store.activityLogsOf(duplicateCaseId).doc(), {
        ...logBase.toFirestore(),
        'details': {'mergedIntoCaseId': primaryCaseId, 'role': 'duplicate'},
      });
    });
  }
}
