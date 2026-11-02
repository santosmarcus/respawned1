// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Case-level reads: the Rescue Reports tab streams, a single case, and its
/// reports / activity log / community reports subcollections.
class RescueCaseQueryRepository {
  RescueCaseQueryRepository(this._store);

  final RescueCaseStore _store;

  /// Streams every case whose status resolves to one of [statuses]. Client
  /// filters (urgency/species/date/location/search) are applied on top by
  /// the caller — Firestore can't combine an array-membership status query
  /// with several other equality/range filters efficiently on this schema.
  Stream<List<RescueCase>> streamCasesByStatuses(List<RescueStatus> statuses) {
    final values = statuses.expand((s) => s.queryValues).toSet().toList();
    if (values.isEmpty) return Stream.value(const []);
    // Diagnostic for the PERMISSION_DENIED investigation — deployed rules
    // are wide open (allow any authenticated user), so a denial here means
    // either this app isn't actually pointed at the project the rules were
    // deployed to, or the request isn't reaching Firestore as authenticated
    // at all (e.g. server-side App Check enforcement rejecting requests
    // before rules ever evaluate). Confirm both values below against the
    // Firebase console project you deployed rules to.
    debugPrint(
      '[RescueCaseRepository] projectId=${Firebase.app().options.projectId} '
      'uid=${FirebaseAuth.instance.currentUser?.uid} statuses=$values',
    );
    // Animal-record admissions (see createAdmissionCase) skip the Rescue
    // Review stage by construction — they're never written with status
    // pendingReview/awaitingAssignment's own review intent in mind, just
    // its "needs a clinic/transporter" mechanics reused. Excluding them
    // specifically from a query that's ONLY for those review-queue statuses
    // keeps Rescue Reports focused on community-submitted reports, while
    // any other status list (ongoing/treatment/intake/completed) still
    // includes them — those views are meant to show every case in motion,
    // regardless of source.
    final isReviewQueueQuery = statuses.every(
      (s) =>
          s == RescueStatus.pendingReview ||
          s == RescueStatus.accepted ||
          s == RescueStatus.awaitingAssignment,
    );
    // Firestore whereIn supports up to 30 values; our alias lists are well
    // under that even for the broadest status (ongoing).
    //
    // Deliberately NO `.orderBy('createdAt', ...)` on the query itself —
    // Firestore silently EXCLUDES any document missing the ordered field
    // from the result set entirely (not an error, just a permanent
    // disappearance). A legacy/hand-migrated/Cloud-Function-written case
    // doc with no `createdAt` would vanish from every tab with zero
    // signal. Sorting is done client-side below instead, after parsing,
    // so a missing/null createdAt only affects where a case SORTS
    // (falls last), never whether it appears at all.
    return _store.cases.where('status', whereIn: values).snapshots().map((
      snap,
    ) {
      debugPrint(
        '[RescueCaseRepository] streamCasesByStatuses(${statuses.map((s) => s.name).join(",")}): '
        '${snap.docs.length} doc(s) returned, ids=${snap.docs.map((d) => d.id).toList()}',
      );
      final cases = <RescueCase>[];
      for (final doc in snap.docs) {
        try {
          cases.add(RescueCase.fromFirestore(doc));
        } catch (e, st) {
          // One malformed document must never take down the whole tab —
          // it's skipped and logged, every other case still loads.
          debugPrint(
            '[RescueCaseRepository] Skipping unparseable case ${doc.id}: $e\n$st\nraw=${doc.data()}',
          );
        }
      }
      final filtered = <RescueCase>[];
      for (final c in cases) {
        if (!_isPrimaryGroupMember(c)) {
          debugPrint(
            '[RescueCaseRepository] Dropping case ${c.id} — not the primary member of '
            'groupId=${c.raw['groupId']} (legacy grouped-submission collapsing).',
          );
          continue;
        }
        if (isReviewQueueQuery &&
            c.raw['sourceType'] == 'animalRecordAdmission') {
          continue;
        }
        filtered.add(c);
      }
      filtered.sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
      return filtered;
    });
  }

  /// Backward compatibility for reports submitted before multi-animal
  /// reports were consolidated into a single doc with an `animals` array:
  /// older multi-animal reports wrote one case doc per animal, linked by a
  /// shared `groupId` (see rescue_page.dart's prior submission logic).
  /// Without this filter, Rescue Reports would still show one card per
  /// sibling doc for any of that older data. Keeps only the "primary" doc
  /// of a group (the one whose own id equals the shared groupId) — mirrors
  /// the same collapsing already done in public_rescue_feed.dart and
  /// activity_feed.dart. New submissions never set `groupId`, so they pass
  /// through untouched.
  bool _isPrimaryGroupMember(RescueCase c) {
    final groupId = c.raw['groupId'] as String?;
    return groupId == null || groupId.isEmpty || groupId == c.id;
  }

  Stream<RescueCase?> streamCase(String caseId) {
    return _store
        .caseDoc(caseId)
        .snapshots()
        .map((doc) => doc.exists ? RescueCase.fromFirestore(doc) : null);
  }

  /// Which animal-array indexes already have a created record for this
  /// case — drives both the "N of M records created" progress and
  /// duplicate-prevention in the multi-animal creation flow (checked
  /// client-side against this single query rather than a second
  /// composite-indexed query per animal).
  Stream<Set<int>> streamCompletedAnimalRecordIndexes(String caseId) {
    return _store.animals
        .where('linkedCaseId', isEqualTo: caseId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => (d.data()['sourceAnimalIndex'] as num?)?.toInt())
              .whereType<int>()
              .toSet(),
        );
  }

  Stream<List<RescueReport>> streamReports(String caseId) {
    return _store
        .reportsOf(caseId)
        .orderBy('submittedAt')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => RescueReport.fromFirestore(d, caseId))
              .toList(),
        );
  }

  Stream<List<ActivityLogEntry>> streamActivityLogs(String caseId) {
    return _store
        .activityLogsOf(caseId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ActivityLogEntry.fromFirestore(d, caseId))
              .toList(),
        );
  }

  Stream<List<CommunityReport>> streamCommunityReports(String caseId) {
    return _store
        .communityReportsOf(caseId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(CommunityReport.fromFirestore).toList());
  }

  /// Cases with at least one animal currently in [stage] according to the
  /// denormalized `activeAnimalStages` field (spec §7) — catches a
  /// mixed-stage case whose scalar `status` no longer reflects every
  /// animal's own state (e.g. one animal already moved to Intake while
  /// another is still in_treatment, so `status` stays 'in_treatment' — see
  /// [_deriveCaseStatusOverride]). Callers merge this with the existing
  /// [streamCasesByStatuses] result and de-duplicate by id, so a legacy
  /// case with no `activeAnimalStages` written yet (every case predating
  /// this round) still appears via its scalar `status` exactly as before.
  Stream<List<RescueCase>> streamCasesByActiveStage(String stage) {
    return _store.cases
        .where('activeAnimalStages', arrayContains: stage)
        .snapshots()
        .map((snap) {
          final cases = <RescueCase>[];
          for (final doc in snap.docs) {
            try {
              cases.add(RescueCase.fromFirestore(doc));
            } catch (e, st) {
              debugPrint(
                '[RescueCaseRepository] Skipping unparseable case ${doc.id} (stage=$stage): $e\n$st',
              );
            }
          }
          return cases.where(_isPrimaryGroupMember).toList();
        });
  }
}
