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
/// postTreatmentAction) are completed per animal by
/// CaseIntakeRepository.completeIntakeForAnimals and are left to the app.
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

module.exports = {quarantineDue, animalCountOf, intakeCompletionDue};
