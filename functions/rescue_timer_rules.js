// Pure decisions for the rescue timers that used to run only when staff
// opened a case (completeDueQuarantines / completeDueIntakes in
// functions/index.js). They mirror the client checks they back up:
// CaseIntakeRepository.checkAndCompleteQuarantineIfDue and
// checkAndCompleteIntakeIfDue (lib/core/repos/rescue_case/
// case_intake_repository.dart). No Firebase here, so `node --test` can check
// them directly.

/// A quarantine started with a duration ends once its scheduled end has
/// passed. [status] is cases/{id}.quarantineStatus.
function quarantineDue({status, scheduledEndMs, nowMs}) {
  if (status !== 'active') return false;
  if (typeof scheduledEndMs !== 'number' || !Number.isFinite(scheduledEndMs)) return false;
  return nowMs >= scheduledEndMs;
}

/// Animals on a case: the animals[] list, or one for a legacy single-animal
/// case (species_summary.dart animalCountOf).
function animalCountOf(animals) {
  return Array.isArray(animals) && animals.length > 0 ? animals.length : 1;
}

/// Whole-case intake completion: the animal was received at the shelter and
/// every animal on the case has its animal record (records created from the
/// case carry linkedCaseId + sourceAnimalIndex; a case admitted from an
/// existing record, sourceAnimalRecordId, already has one for each).
/// Cases whose animals follow separate post-treatment paths (any animal with
/// postTreatmentAction) are completed per animal instead
/// (animalsDueForIntakeCompletion below).
///   c: the case data; recordIndexes: the sourceAnimalIndex values of the
///   animal records linked to the case.
function intakeCompletionDue(c, recordIndexes) {
  if (!c || c.status !== 'intake' || !c.intakeReceivedAt) return false;
  const animals = Array.isArray(c.animals) ? c.animals : [];
  if (animals.some((a) => a && a.postTreatmentAction)) return false;
  if (c.sourceAnimalRecordId) return true;
  const expected = animalCountOf(animals);
  const done = new Set((recordIndexes || []).filter((i) => Number.isInteger(i) && i >= 0 && i < expected));
  return done.size >= expected;
}

/// Per-animal intake completion, for cases whose animals follow separate
/// post-treatment paths: the indexes of animals sent to Intake
/// (postTreatmentAction 'intake'), not completed yet, received at the
/// shelter (receivedAt), and with their animal record (or admitted from an
/// existing record). Mirrors CaseIntakeRepository.completeIntakeForAnimals
/// and IntakeDetailPage's per-animal check. Each animal is completed on its
/// own; none waits on another animal on the case.
function animalsDueForIntakeCompletion(c, recordIndexes) {
  const animals = c && Array.isArray(c.animals) ? c.animals : [];
  if (!animals.length) return [];
  const hasRecord = new Set((recordIndexes || []).filter((i) => Number.isInteger(i)));
  const due = [];
  animals.forEach((a, i) => {
    if (!a || a.postTreatmentAction !== 'intake' || a.intakeCompletedAt || !a.receivedAt) return;
    if (!c.sourceAnimalRecordId && !hasRecord.has(i)) return;
    due.push(i);
  });
  return due;
}

/// Waiting for the confirmed adopter to collect it (RescueCaseStore.
/// isAwaitingAdopterPickup): still counts as in Treatment.
function awaitingAdopterPickup(a) {
  return a.postTreatmentAction === 'release' && !a.releaseCompletedAt;
}

/// RescueCaseStore.stageSummaryUpdate: the Treatment/Intake tab counts a
/// multi-animal case carries.
function stageSummary(animals) {
  if (!Array.isArray(animals) || !animals.length) return {};
  const counts = {};
  for (const a of animals) {
    if (!a || a.outcome === 'deceased') continue;
    let stage = null;
    if (a.postTreatmentAction == null || awaitingAdopterPickup(a)) stage = 'in_treatment';
    else if (a.postTreatmentAction === 'intake' && !a.intakeCompletedAt) stage = 'intake';
    if (stage) counts[stage] = (counts[stage] || 0) + 1;
  }
  return {activeAnimalStages: Object.keys(counts).sort(), animalStageCounts: counts};
}

/// RescueCaseStore.deriveCaseStatusOverride: the case status its animals
/// imply. Null for a case with no animals[].
function derivedCaseStatus(animals) {
  if (!Array.isArray(animals) || !animals.length) return null;
  const live = animals.filter((a) => a && a.outcome !== 'deceased');
  if (live.some((a) => a.postTreatmentAction == null || awaitingAdopterPickup(a))) return 'in_treatment';
  // Like the Dart original, a pending Intake counts even for a deceased animal.
  if (animals.some((a) => a && a.postTreatmentAction === 'intake' && !a.intakeCompletedAt)) return 'intake';
  return 'completed';
}

module.exports = {
  quarantineDue,
  animalCountOf,
  intakeCompletionDue,
  animalsDueForIntakeCompletion,
  stageSummary,
  derivedCaseStatus,
};
