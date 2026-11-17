// Pure decisions for rescue adoptions (Rescue gaps 6 and 10): the
// interested adopter's request, the pickup window and what happens when the
// animal isn't collected in time. Used by syncRescueAdoptionRequest,
// onRescueAdoptionCaseUpdate and followUpAdopterPickups in
// functions/index.js. No Firebase here, so `node --test` checks them.

/// Keep equal to kAdopterPickupWindow / kAdopterPickupReminder in
/// lib/core/models/rescue/rescue_adoption.dart. Pending the organization's
/// confirmation.
const PICKUP_WINDOW_HOURS = 72;
const PICKUP_REMINDER_HOURS = 24;
const HOUR_MS = 60 * 60 * 1000;

/// adoptions/{id}.source of these requests.
const RESCUE_ADOPTION_SOURCE = 'rescue_case';

/// What the pickup job does with a case's `adopterPickup` now:
/// 'none' | 'remind' (once, PICKUP_REMINDER_HOURS before the deadline) |
/// 'missed' (deadline passed, not collected).
function pickupStep(pickup, nowMs) {
  if (!pickup || pickup.collectedAt || pickup.missedAt) return 'none';
  const deadlineMs = typeof pickup.deadlineMs === 'number' ? pickup.deadlineMs : null;
  if (deadlineMs === null) return 'none';
  if (nowMs >= deadlineMs) return 'missed';
  if (!pickup.reminderSentAt && nowMs >= deadlineMs - PICKUP_REMINDER_HOURS * HOUR_MS) return 'remind';
  return 'none';
}

/// Missed pickup: straight to the shelter when it has space (or no
/// capacity is set, so nothing says it is full), otherwise refer the
/// animal to another organization. [incoming] is how many animals the
/// missed pickup would add.
function missedPickupOutcome({capacity, housed, incoming = 1}) {
  if (typeof capacity !== 'number' || !Number.isFinite(capacity) || capacity <= 0) return 'shelter';
  return housed + incoming <= capacity ? 'shelter' : 'refer';
}

/// Same classifier as isCurrentlyHoused in lib/core/utils/shelter_occupancy.dart.
function isCurrentlyHoused(a) {
  return !!a && a.archived !== true && a.status !== 'deceased' &&
    a.adoptionStatus !== 'adopted' && a.adoptionStatus !== 'deceased';
}

function isAwaitingAdopterPickup(a) {
  return !!a && a.postTreatmentAction === 'release' && !a.releaseCompletedAt;
}

/// The animals[] list after a missed pickup. Only the animals still waiting
/// for the adopter (in [indexes], or every one when null) change:
///   shelter: postTreatmentAction 'intake' (Intake Details takes over);
///   refer:   back to no action, eligible for Refer/Intake/Transfer again.
function animalsAfterMissedPickup(animals, indexes, outcome, now) {
  const list = Array.isArray(animals) ? animals.map((a) => ({...a})) : [];
  const targets = Array.isArray(indexes) ? indexes : list.map((_, i) => i);
  for (const i of targets) {
    if (i < 0 || i >= list.length || !isAwaitingAdopterPickup(list[i])) continue;
    const a = list[i];
    delete a.releaseAdopterId;
    a.pickupMissedAt = now;
    if (outcome === 'shelter') {
      a.postTreatmentAction = 'intake';
      a.postTreatmentStartedAt = now;
    } else {
      a.postTreatmentAction = null;
      a.postTreatmentStartedAt = null;
    }
  }
  return list;
}

/// Port of RescueCaseStore.stageSummaryUpdate.
function stageSummary(animals) {
  if (!Array.isArray(animals) || animals.length === 0) return {};
  const counts = {};
  for (const a of animals) {
    if (a.outcome === 'deceased') continue;
    let stage = null;
    if (!a.postTreatmentAction || isAwaitingAdopterPickup(a)) stage = 'in_treatment';
    else if (a.postTreatmentAction === 'intake' && !a.intakeCompletedAt) stage = 'intake';
    if (stage) counts[stage] = (counts[stage] || 0) + 1;
  }
  return {activeAnimalStages: Object.keys(counts).sort(), animalStageCounts: counts};
}

/// Port of RescueCaseStore.deriveCaseStatusOverride.
function deriveCaseStatus(animals) {
  if (!Array.isArray(animals) || animals.length === 0) return null;
  if (animals.some((a) => a.outcome !== 'deceased' && (!a.postTreatmentAction || isAwaitingAdopterPickup(a)))) {
    return 'in_treatment';
  }
  if (animals.some((a) => a.postTreatmentAction === 'intake' && !a.intakeCompletedAt)) return 'intake';
  return 'completed';
}

/// Case status after a missed pickup. A legacy case with no animals[]
/// follows the outcome directly.
function caseStatusAfterMissedPickup(animals, outcome) {
  return deriveCaseStatus(animals) || (outcome === 'shelter' ? 'intake' : 'in_treatment');
}

/// cases/{id}.adoptionRequest, mirrored from the request document.
function caseAdoptionRequestOf(applicationId, app) {
  const personal = app.personal || {};
  const closedReason = app.status === 'rejected' ?
    (app.rejectionNotes || 'Not approved by the organization.') :
    app.status === 'withdrawn' ? (app.withdrawalReason || 'The request was closed.') : null;
  return {
    applicationId,
    adopterId: personal.adopterId || null,
    adopterName: personal.adopterName || 'Adopter',
    status: app.status || 'pending',
    closedReason,
  };
}

/// Whether a request document may update the case's mirror: the case has
/// none yet, it is the same request, or the case's current one is closed
/// and this one is open (a new request after a decline).
function shouldMirrorRequest(current, applicationId, status) {
  if (!current || !current.applicationId) return true;
  if (current.applicationId === applicationId) return true;
  const open = (s) => s === 'pending' || s === 'approved';
  return !open(current.status) && open(status);
}

module.exports = {
  PICKUP_WINDOW_HOURS,
  PICKUP_REMINDER_HOURS,
  RESCUE_ADOPTION_SOURCE,
  pickupStep,
  missedPickupOutcome,
  isCurrentlyHoused,
  isAwaitingAdopterPickup,
  animalsAfterMissedPickup,
  stageSummary,
  deriveCaseStatus,
  caseStatusAfterMissedPickup,
  caseAdoptionRequestOf,
  shouldMirrorRequest,
};
