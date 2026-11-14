// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// Prefer [recordAction], which also writes the reporter's status line.
  /// This is for actions with nothing to tell the reporter.
  Future<void> addActivityLog({
    required String caseId,
    required String action,
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) async {
    await activityLogsOf(caseId).add(
      _logEntry(caseId, action, actorUid, actorName, actorRole, details),
    );
  }

  // ---- The case timeline ---------------------------------------------------
  //
  // Every case action is recorded in two places: the `statusHistory` line
  // the reporter sees on their tracking page, and the `activityLogs` entry
  // staff (and the Audit page) see, which keeps who did it. [recordAction]
  // and [recordActionIn] write both together, with the case update, so
  // neither can be left out.

  /// One `statusHistory` item.
  static Map<String, dynamic> statusLineEntry(String text, [Timestamp? at]) =>
      {'status': text, 'timestamp': at ?? Timestamp.now()};

  /// Applies [fields] to the case, adds [statusLine] (when given) to what the
  /// reporter sees, and logs [action] for staff, in one atomic write. With no
  /// [actorUid], the signed-in user is recorded.
  Future<void> recordAction({
    required String caseId,
    required String action,
    String? statusLine,
    Map<String, dynamic> fields = const {},
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) {
    final batch = db.batch();
    final update = _withStatusLine(fields, statusLine);
    if (update.isNotEmpty) batch.update(caseDoc(caseId), update);
    batch.set(activityLogsOf(caseId).doc(), _logEntry(caseId, action, actorUid, actorName, actorRole, details));
    return batch.commit();
  }

  /// [recordAction] inside a running transaction.
  void recordActionIn(
    Transaction tx, {
    required String caseId,
    required String action,
    String? statusLine,
    Map<String, dynamic> fields = const {},
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) {
    final update = _withStatusLine(fields, statusLine);
    if (update.isNotEmpty) tx.update(caseDoc(caseId), update);
    tx.set(activityLogsOf(caseId).doc(), _logEntry(caseId, action, actorUid, actorName, actorRole, details));
  }

  /// [recordAction] as part of a [WriteBatch] the caller commits.
  void recordActionInBatch(
    WriteBatch batch, {
    required String caseId,
    required String action,
    String? statusLine,
    Map<String, dynamic> fields = const {},
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) {
    final update = _withStatusLine(fields, statusLine);
    if (update.isNotEmpty) batch.update(caseDoc(caseId), update);
    batch.set(activityLogsOf(caseId).doc(), _logEntry(caseId, action, actorUid, actorName, actorRole, details));
  }

  static Map<String, dynamic> _withStatusLine(Map<String, dynamic> fields, String? statusLine) => {
        ...fields,
        if (statusLine != null) 'statusHistory': FieldValue.arrayUnion([statusLineEntry(statusLine)]),
      };

  static Map<String, dynamic> _logEntry(
    String caseId,
    String action,
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  ) {
    final user = actorUid == null ? FirebaseAuth.instance.currentUser : null;
    return ActivityLogEntry(
      id: '',
      caseId: caseId,
      action: action,
      actorUid: actorUid ?? user?.uid,
      actorName: actorName ?? user?.displayName ?? user?.email,
      actorRole: actorRole,
      details: details,
    ).toFirestore();
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
