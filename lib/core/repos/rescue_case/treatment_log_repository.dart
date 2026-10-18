// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Treatment log entries (append-only) and their validation.
class TreatmentLogRepository {
  TreatmentLogRepository(this._store);

  final RescueCaseStore _store;

  /// Chronological (oldest first) treatment history for a case — merges the
  /// new append-only `treatmentLogs` subcollection with any entries still
  /// sitting only in the legacy `treatmentLog` array field on the case doc
  /// itself (written by the old treatment_detail_page.dart before this
  /// subcollection existed). Legacy entries are read-only here — every new
  /// write goes to the subcollection exclusively, so the array field never
  /// grows again; it just isn't discarded for cases that already have it.
  Stream<List<TreatmentLogEntry>> streamTreatmentLogs(String caseId) {
    return _store
        .treatmentLogsOf(caseId)
        .orderBy('timestamp')
        .snapshots()
        .asyncMap((snap) async {
          final subcollectionLogs = snap.docs
              .map((d) => TreatmentLogEntry.fromFirestore(d, caseId))
              .toList();
          if (subcollectionLogs.isNotEmpty) return subcollectionLogs;

          // Only fall back to the legacy array if the subcollection is
          // genuinely empty — once a case has any real log entries, those are
          // the source of truth and legacy data (if any) has already been
          // migrated forward by the first new write's own read, avoiding a
          // second Firestore read on every snapshot for cases with real data.
          final caseSnap = await _store.caseDoc(caseId).get();
          final legacy = List<Map<String, dynamic>>.from(
            caseSnap.data()?['treatmentLog'] ?? const [],
          );
          return [
            for (var i = 0; i < legacy.length; i++)
              TreatmentLogEntry.fromLegacyMap(legacy[i], caseId, i),
          ];
        });
  }

  /// Pre-allocates an id for a new treatment log entry, without writing
  /// anything — lets the caller upload media to
  /// `cases/{caseId}/treatmentUpdates/{logId}/...` under a Storage path that
  /// matches the eventual log document's id, before that document exists.
  String newTreatmentLogId(String caseId) =>
      _store.treatmentLogsOf(caseId).doc().id;

  /// Appends one treatment log entry (never edits/overwrites a prior one)
  /// and updates the case-level "latest state" fields that drive the
  /// Treatment Details header and the Rescue Reports card: currentCondition,
  /// latestTreatmentUpdateType, treatmentUpdatedAt, statusHistory. A
  /// Discharge entry additionally sets readyForDischarge/dischargedAt; a
  /// Death Report entry sets deceasedAt/causeOfDeath (and the legacy
  /// animalStatus:'Deceased' flag some older screens still read).
  ///
  /// [logId] should come from [newTreatmentLogId] when the caller already
  /// uploaded media under that id; omitted, a fresh id is allocated here.
  ///
  /// Enforced here (not just in the UI): once a case has
  /// `readyForDischarge == true`, no further treatment update of any kind
  /// can be added — a disabled button alone wouldn't stop a direct
  /// repository call, so this is the actual source of truth for the rule.
  /// Required fields depend on [entry.type] — matches
  /// treatment_detail_page.dart's own _canSubmit() exactly, so a malformed
  /// direct call (or a future second UI) can't skip validation the admin
  /// form otherwise enforces.
  void _validateTreatmentLogEntry(TreatmentLogEntry entry) {
    final type = TreatmentUpdateType.fromLabel(entry.type);
    switch (type) {
      case TreatmentUpdateType.vaccination:
        if ((entry.vaccineName ?? '').trim().isEmpty)
          throw ArgumentError('Vaccine is required.');
        if ((entry.vaccineDose ?? '').trim().isEmpty)
          throw ArgumentError('Vaccine dose is required.');
        break;
      case TreatmentUpdateType.procedure:
        if ((entry.procedurePerformed ?? '').trim().isEmpty) {
          throw ArgumentError('Procedure performed is required.');
        }
        break;
      case TreatmentUpdateType.medication:
        if ((entry.medicationName ?? '').trim().isEmpty)
          throw ArgumentError('Medication name is required.');
        if ((entry.medicationDose ?? '').trim().isEmpty)
          throw ArgumentError('Medication dose is required.');
        break;
      case TreatmentUpdateType.discharge:
        if ((entry.finalCondition ?? '').trim().isEmpty)
          throw ArgumentError('Final condition is required.');
        break;
      case TreatmentUpdateType.deathReport:
        if ((entry.causeOfDeath ?? '').trim().isEmpty)
          throw ArgumentError('Cause of death is required.');
        break;
      case TreatmentUpdateType.assessment:
      case TreatmentUpdateType.followUpCheck:
      case null:
        if ((entry.condition ?? '').trim().isEmpty)
          throw ArgumentError('Overall condition is required.');
        if (entry.notes.trim().isEmpty)
          throw ArgumentError('Notes are required for this update type.');
        break;
    }
  }

  Future<void> addTreatmentLog({
    required String caseId,
    required TreatmentLogEntry entry,
    String? logId,
  }) async {
    _validateTreatmentLogEntry(entry);
    final caseSnap = await _store.caseDoc(caseId).get();
    final data = caseSnap.data();
    final animals = List<Map<String, dynamic>>.from(
      (data?['animals'] as List? ?? const []).map(
        (a) => Map<String, dynamic>.from(a as Map),
      ),
    );

    // ROOT CAUSE FIX (spec §6): this used to be a single case-wide
    // `readyForDischarge == true` gate that blocked every further
    // treatment update for the whole case the moment ANY one animal was
    // discharged — so discharging Animal 1 also silently locked Animal 2
    // out of further logging. The gate now only fires once EVERY animal on
    // the case has actually resolved (discharged+actioned, or deceased) —
    // for a legacy single-animal case (no `animals[]`) that's still just
    // the old scalar `readyForDischarge` flag, unchanged.
    final allResolved = animals.isNotEmpty
        ? animals.every(
            (a) => a['outcome'] == 'deceased' || a['dischargedAt'] != null,
          )
        : (data?['readyForDischarge'] == true);
    if (allResolved) {
      throw StateError(
        'No further treatment updates can be added after discharge.',
      );
    }

    final logRef = logId != null
        ? _store.treatmentLogsOf(caseId).doc(logId)
        : _store.treatmentLogsOf(caseId).doc();
    await logRef.set(entry.toFirestore());

    final now = Timestamp.now();
    final isDischarge = entry.type == TreatmentUpdateType.discharge.label;
    final isDeath = entry.type == TreatmentUpdateType.deathReport.label;
    // Falls back to a per-type summary when Notes is empty (now legitimate
    // for Vaccination/Procedure/Medication/Discharge/Death Report) instead
    // of ever writing a trailing-blank "Type: " history line.
    final summary = entry.notes.trim().isNotEmpty
        ? entry.notes
        : entry.vaccineName ??
              entry.procedurePerformed ??
              entry.medicationName ??
              entry.finalCondition ??
              entry.causeOfDeath ??
              entry.type;

    // Which animals THIS entry targets — every animal for a null/empty
    // animalIndexes ("All Animals", spec §5), otherwise only the selected
    // ones. Only meaningful (and only ever applied) when the case actually
    // has an `animals[]` array to stamp.
    final targetIndexes = animals.isEmpty
        ? const <int>[]
        : (entry.animalIndexes != null && entry.animalIndexes!.isNotEmpty
              ? entry.animalIndexes!
              : List<int>.generate(animals.length, (i) => i));

    if (isDischarge) {
      for (final i in targetIndexes) {
        if (i < 0 || i >= animals.length) continue;
        animals[i] = {
          ...animals[i],
          'dischargedAt': now,
          'dischargeLogId': logRef.id,
        };
      }
    } else if (isDeath) {
      for (final i in targetIndexes) {
        if (i < 0 || i >= animals.length) continue;
        animals[i] = {
          ...animals[i],
          'outcome': 'deceased',
          'deceasedAt': now,
          'deceasedReason': entry.causeOfDeath ?? 'Unknown',
          'deceasedConfirmedBy': entry.createdBy,
        };
      }
    }

    await _store.caseDoc(caseId).update({
      if (entry.condition != null) 'currentCondition': entry.condition,
      'latestTreatmentUpdateType': entry.type,
      'treatmentUpdatedAt': now,
      'statusHistory': FieldValue.arrayUnion([
        {'status': '${entry.type}: $summary', 'timestamp': now},
      ]),
      if (animals.isNotEmpty && (isDischarge || isDeath)) 'animals': animals,
      if (animals.isNotEmpty && (isDischarge || isDeath))
        ...RescueCaseStore.stageSummaryUpdate(animals),
      // Legacy case-wide fields — kept exactly as before for a case with no
      // `animals[]` array, and also kept (informationally) alongside the
      // new per-animal fields above so any older reader that only looks at
      // these flat fields (e.g. IntakeDetailPage's discharge-date display)
      // keeps working: they reflect the FIRST discharge/death recorded,
      // never re-gate anything by themselves anymore.
      if (isDischarge) 'readyForDischarge': true,
      if (isDischarge) 'dischargedAt': now,
      if (isDeath) 'deceasedAt': now,
      if (isDeath) 'animalStatus': 'Deceased',
      if (isDeath && entry.causeOfDeath != null)
        'causeOfDeath': entry.causeOfDeath,
    });
  }
}
