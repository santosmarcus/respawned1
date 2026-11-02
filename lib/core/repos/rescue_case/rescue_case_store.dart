// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

/// Shared Firestore access for every rescue-case repository: the `cases`
/// collection, its subcollection references, the activity log writer, and
/// the raw-map helpers several write paths share. Holds no state beyond the
/// [FirebaseFirestore] instance, so each domain repository built on the same
/// store reads and writes exactly the same documents.
class RescueCaseStore {
  RescueCaseStore(this.db);

  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get cases => db.collection('cases');

  DocumentReference<Map<String, dynamic>> caseDoc(String caseId) =>
      cases.doc(caseId);

  CollectionReference<Map<String, dynamic>> reportsOf(String caseId) =>
      caseDoc(caseId).collection('reports');

  CollectionReference<Map<String, dynamic>> referralsOf(String caseId) =>
      caseDoc(caseId).collection('referrals');

  CollectionReference<Map<String, dynamic>> activityLogsOf(String caseId) =>
      caseDoc(caseId).collection('activityLogs');

  // Same subcollection the user-side track_case_page.dart's
  // _CommunityReportSection already reads/writes — reused here read-only,
  // not a second storage structure.
  CollectionReference<Map<String, dynamic>> communityReportsOf(String caseId) =>
      caseDoc(caseId).collection('communityReports');

  CollectionReference<Map<String, dynamic>> transportAssignmentsOf(
    String caseId,
  ) => caseDoc(caseId).collection('transportAssignments');

  CollectionReference<Map<String, dynamic>> get users => db.collection('users');

  CollectionReference<Map<String, dynamic>> treatmentLogsOf(String caseId) =>
      caseDoc(caseId).collection('treatmentLogs');

  CollectionReference<Map<String, dynamic>> expensesOf(String caseId) =>
      caseDoc(caseId).collection('expenses');

  // Top-level collection — see create_animal_record_page.dart /
  // animal_record_detail_page.dart, both already established. Reused as-is
  // (linkedCaseId is the existing case-reference field); only
  // sourceAnimalIndex is genuinely new, for multi-animal duplicate
  // prevention.
  CollectionReference<Map<String, dynamic>> get animals =>
      db.collection('animals');

  Future<void> addActivityLog({
    required String caseId,
    required String action,
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) async {
    await activityLogsOf(caseId).add(
      ActivityLogEntry(
        id: '',
        caseId: caseId,
        action: action,
        actorUid: actorUid,
        actorName: actorName,
        actorRole: actorRole,
        details: details,
      ).toFirestore(),
    );
  }

  /// Recomputes `activeAnimalStages`/`animalStageCounts` (spec §7) from a
  /// fresh `animals` array — raw-map twin of core/utils/
  /// animal_treatment_state.dart's `activeStagesOf`, used here because
  /// every write site below already has a freshly-read/mutated `animals`
  /// list mid-update rather than a constructed RescueCase. Returns an empty
  /// map for a legacy case with no `animals[]` entries at all — that case's
  /// single scalar `status` field alone still drives its one tab, exactly
  /// as before this round.
  static Map<String, dynamic> stageSummaryUpdate(
    List<Map<String, dynamic>> animals,
  ) {
    if (animals.isEmpty) return const {};
    final counts = <String, int>{};
    for (final a in animals) {
      if (a['outcome'] == 'deceased') continue;
      final action = a['postTreatmentAction'] as String?;
      String? stage;
      if (action == null) {
        stage = 'in_treatment';
      } else if (action == 'intake' && a['intakeCompletedAt'] == null) {
        stage = 'intake';
      }
      if (stage != null) counts[stage] = (counts[stage] ?? 0) + 1;
    }
    return {
      'activeAnimalStages': counts.keys.toList()..sort(),
      'animalStageCounts': counts,
    };
  }

  /// The case-level `status` a multi-animal case's `animals[]` state
  /// implies (spec §12) — 'in_treatment' while any animal is still
  /// un-actioned (never removed from Treatment until no active animal
  /// remains there, per spec §7), else 'intake' while any animal's
  /// assigned action is Intake and not yet complete, else 'completed' once
  /// every animal has resolved (transferred/released/intake-completed/
  /// deceased). Returns null for a legacy case with no `animals[]` — the
  /// caller keeps whatever explicit status write it already had.
  static String? deriveCaseStatusOverride(List<Map<String, dynamic>> animals) {
    if (animals.isEmpty) return null;
    final anyUnactioned = animals.any(
      (a) => a['outcome'] != 'deceased' && a['postTreatmentAction'] == null,
    );
    if (anyUnactioned) return RescueStatus.treatment.firestoreValue;
    final anyIntakePending = animals.any(
      (a) =>
          a['postTreatmentAction'] == 'intake' &&
          a['intakeCompletedAt'] == null,
    );
    if (anyIntakePending) return RescueStatus.intake.firestoreValue;
    return RescueStatus.completed.firestoreValue;
  }
}
