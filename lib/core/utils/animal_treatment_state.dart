import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';

/// Per-animal treatment/discharge/post-treatment state derived from a
/// case's `animals[]` array entries plus its treatment log stream.
///
/// Root cause fixed here: RescueCase.readyForDischarge/dischargedAt were
/// case-level fields treated as "every animal is discharged" the moment
/// ANY animal received a Discharge update — so discharging Animal 1 also
/// unlocked (and, worse, could be read as completing) Animal 2's own
/// post-treatment actions. Each `animals[i]` entry now optionally carries
/// its own `dischargedAt`/`dischargeLogId`/`outcome`/`postTreatmentAction`/
/// `postTreatmentStartedAt` keys (written by RescueCaseRepository — see
/// addTreatmentLog, transferAnimal, releaseToReporter, assignIntakeAction),
/// mirroring the same read-modify-write convention
/// RescueCaseRepository.reportAnimalDeath already established for
/// `outcome`/`deceasedAt`. Every existing reader of `animals[i]` that only
/// looks at `species`/`breed`/etc. is unaffected — these are additive keys
/// on the same loose `Map<String, dynamic>`, never a new collection or a
/// fixed-shape model.
///
/// Legacy single-animal cases (saved before the `animals` array existed,
/// so `RescueCase.animals` is empty) have no per-animal map to read at all
/// — [effectiveAnimalsOf] synthesizes one entry from the case's own
/// flat/legacy fields so every helper below can treat "one legacy animal"
/// and "one animals[] entry" uniformly, and every discharge/deceased check
/// below falls back to the case-level flags for that synthetic entry.
//library;

/// The animals this case covers, for per-animal UI purposes — [RescueCase.
/// animals] itself, or (for a legacy report saved before that array
/// existed) a single synthetic entry built from the case's own flat
/// fields, so index 0 always means "the case's one animal" either way.
List<Map<String, dynamic>> effectiveAnimalsOf(RescueCase c) {
  if (c.animals.isNotEmpty) return c.animals;
  return [
    {'species': c.animalType ?? 'Animal'},
  ];
}

/// True once this specific animal (by [effectiveAnimalsOf] index) has a
/// completed Discharge update — never true just because some OTHER animal
/// on the same case was discharged.
bool animalIsDischarged(RescueCase c, int index) {
  if (c.animals.isEmpty) return c.readyForDischarge;
  if (index < 0 || index >= c.animals.length) return false;
  return c.animals[index]['dischargedAt'] != null;
}

/// True once THIS animal has been physically confirmed received at the
/// shelter — checks the per-animal `receivedAt` key
/// RescueCaseRepository.confirmAnimalReceived now always writes (whether
/// called for a specific subset or the whole case — see that method's own
/// doc comment), falling back to the case-level `intakeReceivedAt` flag
/// only for a legacy single-animal report with no `animals[]` entry of its
/// own to carry that key. Deliberately NO case-level fallback when
/// `animals[]` is non-empty — that's what previously let confirming ONE
/// animal received in a multi-animal Intake silently unlock Animal Record
/// creation for every other (still-unreceived) animal too.
bool animalIsReceived(RescueCase c, int index) {
  if (c.animals.isEmpty) return c.intakeReceivedAt != null;
  if (index < 0 || index >= c.animals.length) return false;
  return c.animals[index]['receivedAt'] != null;
}

DateTime? animalDischargedAt(RescueCase c, int index) {
  if (c.animals.isEmpty) return c.dischargedAt;
  if (index < 0 || index >= c.animals.length) return null;
  final raw = c.animals[index]['dischargedAt'];
  return _asDateTime(raw);
}

/// True once THIS animal has a recorded death outcome — checks the
/// per-animal `outcome` key RescueCaseRepository.reportAnimalDeath and
/// addTreatmentLog's Death Report handling both write, falling back to the
/// case-wide flag only for a legacy single-animal report with no
/// `animals[]` entry of its own to carry that key.
bool animalIsDeceased(RescueCase c, int index) {
  if (c.animals.isEmpty) return c.isDeceased;
  if (index < 0 || index >= c.animals.length) return false;
  return c.animals[index]['outcome'] == 'deceased';
}

/// 'intake' | 'transfer' | 'release' | null — which post-treatment path
/// this animal has been assigned to (set at the moment the admin selects
/// it for that action, before the action necessarily finishes — see
/// RescueCaseRepository.assignIntakeAction/transferAnimal/
/// releaseToReporter). A non-null value here is what excludes the animal
/// from being selectable for a second, conflicting action.
String? animalPostTreatmentAction(RescueCase c, int index) {
  if (c.animals.isEmpty || index < 0 || index >= c.animals.length) return null;
  return c.animals[index]['postTreatmentAction'] as String?;
}

/// True once the assigned post-treatment action has actually finished for
/// this animal (not just been chosen) — 'intake' completes on
/// `intakeCompletedAt`; 'transfer'/'release' complete the moment they're
/// recorded (both are single-step confirmations, unlike the multi-step
/// Intake flow), i.e. as soon as [animalPostTreatmentAction] is set.
bool animalActionIsResolved(RescueCase c, int index) {
  if (animalIsDeceased(c, index)) return true;
  final action = animalPostTreatmentAction(c, index);
  if (action == null) return false;
  if (action == 'intake') {
    if (c.animals.isEmpty) return c.raw['intakeCompletedAt'] != null;
    return c.animals[index]['intakeCompletedAt'] != null;
  }
  // transfer / release: resolved as soon as the action is recorded.
  return true;
}

/// Selectable for a NEW post-treatment action: discharged, not deceased,
/// and not already committed to a different (or the same) action.
bool animalEligibleForNewAction(RescueCase c, int index) =>
    animalIsDischarged(c, index) &&
    !animalIsDeceased(c, index) &&
    animalPostTreatmentAction(c, index) == null;

/// True once at least one animal on the case has a Discharge update on
/// file and is free to be assigned a post-treatment action — this is what
/// the vertical Intake/Transfer/Release buttons on Treatment Details gate
/// on (spec: "Available once at least one animal has a Discharge update"),
/// never the old case-wide `readyForDischarge` flag alone.
bool caseHasAnyEligibleAnimal(RescueCase c) {
  final animals = effectiveAnimalsOf(c);
  for (var i = 0; i < animals.length; i++) {
    if (animalEligibleForNewAction(c, i)) return true;
  }
  return false;
}

/// True once EVERY animal on the case has either a completed Discharge
/// update or a recorded death — mirrors
/// RescueCaseRepository.addTreatmentLog's own "no further treatment
/// updates" gate exactly, so Treatment Details' Add-Update-vs-
/// "Treatment Discharged" toggle never drifts from what the repository
/// actually allows once one animal (but not all) is discharged.
bool caseAllAnimalsResolved(RescueCase c) {
  if (c.animals.isEmpty) return c.readyForDischarge;
  return c.animals.every(
    (a) => a['outcome'] == 'deceased' || a['dischargedAt'] != null,
  );
}

/// This animal's current pipeline stage, for tab-membership/denormalized
/// `activeAnimalStages` purposes — 'in_treatment' while un-actioned,
/// 'intake' while assigned to Intake and not yet completed, or null once
/// deceased/transferred/released/intake-completed (i.e. no longer an
/// "active" stage this case should be queried under).
String? animalActiveStage(RescueCase c, int index) {
  if (animalIsDeceased(c, index)) return null;
  final action = animalPostTreatmentAction(c, index);
  if (action == null) return 'in_treatment';
  if (action == 'intake' && !animalActionIsResolved(c, index)) return 'intake';
  return null; // transfer/release, or a completed intake — no longer active
}

/// Distinct active stages across every animal on the case — the value
/// written to the case doc's `activeAnimalStages` field (spec §7's
/// suggested denormalized summary), used by
/// RescueCaseRepository.streamCasesByActiveStage to find a case under a
/// stage its own scalar `status` field no longer reflects (e.g. one animal
/// already moved to Intake while another is still in_treatment, so
/// `status` stays 'in_treatment' per [deriveCaseStatus] below).
List<String> activeStagesOf(RescueCase c) {
  final animals = effectiveAnimalsOf(c);
  final stages = <String>{};
  for (var i = 0; i < animals.length; i++) {
    final s = animalActiveStage(c, i);
    if (s != null) stages.add(s);
  }
  return stages.toList()..sort();
}

/// Animal-array indexes (into [effectiveAnimalsOf]) whose current stage is
/// [stage] — used to filter a case card / Intake or Treatment list down to
/// only the animals relevant to the tab being viewed (spec §7: "each
/// card/page must show only the animals relevant to that stage").
List<int> animalIndexesInStage(RescueCase c, String stage) {
  final animals = effectiveAnimalsOf(c);
  return [
    for (var i = 0; i < animals.length; i++)
      if (animalActiveStage(c, i) == stage) i,
  ];
}

/// Case-level summary status, safely derived from per-animal state instead
/// of ever being the only source of truth (spec §12). Deliberately mirrors
/// (never replaces) the scalar `status` this module already writes/queries
/// via [RescueStatus] — this is a read-only display/reporting helper.
enum CaseStageSummary { review, mixed, completed }

CaseStageSummary deriveCaseStageSummary(RescueCase c) {
  final animals = effectiveAnimalsOf(c);
  final resolvedCount = [
    for (var i = 0; i < animals.length; i++)
      if (animalActionIsResolved(c, i)) i,
  ].length;
  if (resolvedCount == animals.length) return CaseStageSummary.completed;
  if (resolvedCount == 0) return CaseStageSummary.review;
  return CaseStageSummary.mixed;
}

/// This animal's latest condition, derived independently from the logs
/// that actually apply to it (spec §5) — never another animal's latest
/// log. [logs] may be in any order; the most recent applicable entry with
/// real condition information wins. A log with no `animalIndexes` (i.e.
/// [TreatmentLogEntry.appliesToAllAnimals]) counts as applicable to every
/// animal, per spec's "Logs marked All Animals may update every associated
/// animal."
String latestConditionFor(
  RescueCase c,
  int index,
  List<TreatmentLogEntry> logs,
) {
  if (animalIsDeceased(c, index)) return 'Deceased';

  final sorted = [...logs]
    ..sort(
      (a, b) =>
          (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)),
    );
  for (final log in sorted) {
    if (!log.appliesToAnimal(index)) continue;
    final type = TreatmentUpdateType.fromLabel(log.type);
    if (type == TreatmentUpdateType.deathReport) return 'Deceased';
    if (type == TreatmentUpdateType.discharge) {
      final fc = log.finalCondition;
      return (fc != null && fc.trim().isNotEmpty) ? fc : 'Discharged';
    }
    final cond = log.condition;
    if (cond != null && cond.trim().isNotEmpty) return cond;
  }
  return 'Not yet assessed';
}

DateTime? _asDateTime(Object? value) {
  if (value == null) return null;
  // Firestore Timestamp — imported lazily via duck typing to avoid a hard
  // cloud_firestore dependency in this pure-Dart util; RescueCase.animals
  // entries always carry real Timestamp objects once read back from
  // Firestore (Map<String, dynamic> straight off the snapshot).
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return value is DateTime ? value : null;
  }
}
