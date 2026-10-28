import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/adoption_lifecycle.dart';

/// Pure, UI-free derivations the operational dashboard is built on. Every
/// function here reads only fields that already exist on the shared
/// models (RescueCase / AnimalRecord / AdoptionApplication) — nothing is
/// invented, and nothing here writes back to Firestore. Thresholds that
/// the data model doesn't define (e.g. "overdue after N hours") are
/// deliberately NOT introduced; durations are shown as plain elapsed time
/// so the admin judges them, not the dashboard.

// ─── Severity ────────────────────────────────────────────────────────────

/// Restrained status vocabulary — always rendered with an icon AND a text
/// label (never color alone).
enum DashSeverity {
  critical,
  warning,
  info,
  ok;

  String get label => switch (this) {
    DashSeverity.critical => 'Urgent',
    DashSeverity.warning => 'Needs attention',
    DashSeverity.info => 'For review',
    DashSeverity.ok => 'On track',
  };

  IconData get icon => switch (this) {
    DashSeverity.critical => Icons.error,
    DashSeverity.warning => Icons.warning_amber_rounded,
    DashSeverity.info => Icons.info_outline,
    DashSeverity.ok => Icons.check_circle_outline,
  };

  Color get color => switch (this) {
    DashSeverity.critical => const Color(0xFFC94040),
    DashSeverity.warning => const Color(0xFFB7791F),
    DashSeverity.info => const Color(0xFF5A6478),
    DashSeverity.ok => const Color(0xFF3F8F5A),
  };

  /// Lower sorts first.
  int get rank => index;
}

// ─── Rescue workflow ─────────────────────────────────────────────────────

/// Field-outcome statuses written by the transporter app's End Reason flow
/// (see RescueStatus' own doc comment). None of the six Rescue Reports
/// pipeline tabs include them, so without this the dashboard would never
/// surface a case whose location could not be confirmed on site.
///
/// `const` so casesByStatusesProvider resolves it to one stable family
/// instance (see RescuePipelineTab.statuses' doc comment for why).
const List<RescueStatus> kFieldIssueStatuses = [
  RescueStatus.unableToLocate,
  RescueStatus.awaitingReporterResponse,
  RescueStatus.pickupUnsuccessful,
  RescueStatus.needsSpecializedAssistance,
];

/// The stages of the app's actual rescue workflow, in order, each mapped
/// onto the existing RescueStatus values — a visualization of the real
/// statuses, not a replacement for them.
enum RescueStage {
  review,
  clinic,
  transporter,
  transit,
  treatment,
  intake,
  fieldIssue;

  String get label => switch (this) {
    RescueStage.review => 'Awaiting review',
    RescueStage.clinic => 'Needs vet clinic',
    RescueStage.transporter => 'Needs transporter',
    RescueStage.transit => 'In transit',
    RescueStage.treatment => 'Vet treatment',
    RescueStage.intake => 'Shelter intake',
    RescueStage.fieldIssue => 'Field issue',
  };

  String get description => switch (this) {
    RescueStage.review => 'Reported; not yet assessed or verified by staff',
    RescueStage.clinic => 'Accepted; no vet clinic selected yet',
    RescueStage.transporter => 'Clinic selected; no transporter assigned',
    RescueStage.transit => 'Transporter assigned or en route',
    RescueStage.treatment => 'Receiving veterinary care',
    RescueStage.intake => 'Discharged to shelter intake',
    RescueStage.fieldIssue => 'Could not locate / pickup failed / needs specialist',
  };

  IconData get icon => switch (this) {
    RescueStage.review => Icons.fact_check_outlined,
    RescueStage.clinic => Icons.local_hospital_outlined,
    RescueStage.transporter => Icons.local_shipping_outlined,
    RescueStage.transit => Icons.route_outlined,
    RescueStage.treatment => Icons.healing_outlined,
    RescueStage.intake => Icons.house_outlined,
    RescueStage.fieldIssue => Icons.location_off_outlined,
  };
}

RescueStage stageOf(RescueCase c) {
  switch (c.status) {
    case RescueStatus.pendingReview:
      return RescueStage.review;
    case RescueStatus.accepted:
      return RescueStage.clinic;
    case RescueStatus.awaitingAssignment:
      return RescueStage.transporter;
    case RescueStatus.ongoing:
      return RescueStage.transit;
    case RescueStatus.treatment:
      return RescueStage.treatment;
    case RescueStatus.intake:
      return RescueStage.intake;
    default:
      return RescueStage.fieldIssue;
  }
}

/// The next unresolved step for a case, phrased as an instruction. Derived
/// purely from the case's own status + fields.
String nextStepFor(RescueCase c) {
  switch (c.status) {
    case RescueStatus.pendingReview:
      return 'Review the report and confirm the animal’s condition and location';
    case RescueStatus.accepted:
      return 'Select a veterinary clinic';
    case RescueStatus.awaitingAssignment:
      return 'Assign a transporter';
    case RescueStatus.ongoing:
      return 'Monitor transport to ${c.vetClinicName ?? 'the clinic'}';
    case RescueStatus.treatment:
      return c.readyForDischarge ? 'Decide discharge / post-treatment action' : 'Record treatment updates';
    case RescueStatus.intake:
      return 'Confirm shelter intake and create animal record';
    case RescueStatus.unableToLocate:
      return 'Animal not found at location — follow up with reporter';
    case RescueStatus.awaitingReporterResponse:
      return 'Waiting on reporter response';
    case RescueStatus.pickupUnsuccessful:
      return 'Pickup failed — decide whether to re-attempt';
    case RescueStatus.needsSpecializedAssistance:
      return 'Arrange specialized handler or referral';
    default:
      return 'Open case';
  }
}

int urgencyRank(String? urgency) => switch (UrgencyLevel.fromFirestoreValue(urgency)) {
  UrgencyLevel.critical => 0,
  UrgencyLevel.medium => 1,
  UrgencyLevel.low => 2,
  null => 3,
};

/// Report urgency as a dashboard severity (unrated reads as neutral).
DashSeverity urgencySeverity(String? urgency) => switch (UrgencyLevel.fromFirestoreValue(urgency)) {
  UrgencyLevel.critical => DashSeverity.critical,
  UrgencyLevel.medium => DashSeverity.warning,
  UrgencyLevel.low || null => DashSeverity.info,
};

/// Triage order: urgency first, then recorded danger (bite/escape risk or
/// safety indicators), then how early in the workflow it is stuck — and
/// only then age. The oldest report is NOT assumed to be the most urgent.
int compareTriage(RescueCase a, RescueCase b) {
  final u = urgencyRank(a.urgency).compareTo(urgencyRank(b.urgency));
  if (u != 0) return u;
  final dangerA = (a.hasHighRisk || a.safetyIndicators.isNotEmpty) ? 0 : 1;
  final dangerB = (b.hasHighRisk || b.safetyIndicators.isNotEmpty) ? 0 : 1;
  if (dangerA != dangerB) return dangerA.compareTo(dangerB);
  final s = stageOf(a).index.compareTo(stageOf(b).index);
  if (s != 0) return s;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch);
}

/// Most recent timestamp on the case's own status history, falling back
/// to createdAt.
DateTime? lastUpdateOf(RescueCase c) {
  DateTime? latest = c.createdAt;
  for (final h in c.statusHistory) {
    if (h.timestamp != null && (latest == null || h.timestamp!.isAfter(latest))) latest = h.timestamp;
  }
  if (c.treatmentUpdatedAt != null && (latest == null || c.treatmentUpdatedAt!.isAfter(latest))) {
    latest = c.treatmentUpdatedAt;
  }
  return latest;
}

/// Animals currently at clinic for a treatment-stage case — prefers the
/// denormalized per-animal stage counts, falls back to animalCount.
int animalsInTreatment(RescueCase c) => c.animalStageCounts['in_treatment'] ?? c.animalCount;

// ─── Animals under care ──────────────────────────────────────────────────

/// Animals the organization is currently responsible for: not archived,
/// not deceased, and not placed with an adopter (unless returned).
bool isInCare(AnimalRecord a) => !a.archived && !a.isDeceased && !a.isMalformed && (!a.isAdopted || a.isReturned);

/// Same rule Animal Records already uses for its "In Treatment" label
/// (animal_record_detail_page.dart): a set currentCaseId.
bool hasOpenMedicalCase(AnimalRecord a) => a.currentCaseId != null && a.currentCaseId!.isNotEmpty;

class MonitoringReason {
  final String label;
  final DashSeverity severity;
  const MonitoringReason(this.label, this.severity);
}

/// Why an animal record warrants closer attention — every reason maps to
/// a real recorded field. `recentDays` is a display window, not a
/// welfare threshold.
List<MonitoringReason> monitoringReasonsFor(AnimalRecord a, {DateTime? now, int recentDays = 14}) {
  final today = now ?? DateTime.now();
  final reasons = <MonitoringReason>[];
  if (hasOpenMedicalCase(a)) {
    reasons.add(const MonitoringReason('In treatment', DashSeverity.critical));
  }
  if ((a.health.currentMedications ?? '').trim().isNotEmpty) {
    reasons.add(const MonitoringReason('On medication', DashSeverity.warning));
  }
  if (a.isReturned) {
    reasons.add(const MonitoringReason('Returned from adoption', DashSeverity.warning));
  }
  if ((a.health.chronicConditions ?? '').trim().isNotEmpty) {
    reasons.add(const MonitoringReason('Chronic condition', DashSeverity.info));
  }
  if (a.specialNeeds) {
    reasons.add(const MonitoringReason('Special needs', DashSeverity.info));
  }
  if (a.createdAt != null && today.difference(a.createdAt!).inDays < recentDays) {
    reasons.add(const MonitoringReason('Recent intake', DashSeverity.info));
  }
  return reasons;
}

String nextCareActionFor(AnimalRecord a) {
  if (hasOpenMedicalCase(a)) {
    return 'Check the open treatment case';
  }
  if ((a.health.currentMedications ?? '').trim().isNotEmpty) {
    return 'Confirm medication is being given and documented';
  }
  if (a.isReturned) return 'Reassess health and behavior after return';
  if (a.health.lastVetCheckup == null) return 'Record a vet checkup';
  return 'Review record';
}

// ─── Adoption readiness ──────────────────────────────────────────────────

/// One readiness item — `null` means "not recorded", which is shown as a
/// gap, never as a pass or a fail.
class ReadinessItem {
  final String label;
  final bool? done;
  const ReadinessItem(this.label, this.done);
}

/// Readiness information the admin needs to review — deliberately NOT a
/// verdict. Vaccination is one item among several, never decisive alone.
List<ReadinessItem> readinessItemsFor(AnimalRecord a) => [
  ReadinessItem('Vaccinated', a.raw.containsKey('vaccinated') ? a.vaccinated : null),
  ReadinessItem('Dewormed', a.health.dewormed),
  ReadinessItem('Spay/neuter', a.health.sterilized),
  ReadinessItem('Vet checkup on file', a.health.lastVetCheckup != null),
  ReadinessItem('Temperament noted', a.keyCharacteristics.isNotEmpty ? true : null),
  ReadinessItem('Photo', a.photoUrls.isNotEmpty),
];

/// Gaps = items that are missing/unrecorded or not yet done.
int readinessGaps(AnimalRecord a) => readinessItemsFor(a).where((i) => i.done != true).length;

// ─── Adoption returns ────────────────────────────────────────────────────

String nextReturnStep(ReturnRequest r) {
  switch (r.status) {
    case ReturnRequestStatus.pendingReview:
      return 'Review the return request';
    case ReturnRequestStatus.approved:
    case ReturnRequestStatus.retrievalUnscheduled:
      return 'Schedule retrieval and reserve shelter space';
    case ReturnRequestStatus.retrievalScheduled:
      return 'Retrieve the animal on the scheduled date';
    case ReturnRequestStatus.retrieved:
      return 'Process shelter intake and reassess';
    default:
      return 'Open return';
  }
}

/// Active returns expected to come back into shelter care (approved but
/// not yet processed to intake) — feeds capacity planning.
bool returnExpectedBack(ReturnRequest r) =>
    r.status == ReturnRequestStatus.approved ||
        r.status == ReturnRequestStatus.retrievalUnscheduled ||
        r.status == ReturnRequestStatus.retrievalScheduled ||
        r.status == ReturnRequestStatus.retrieved;

List<AdoptionApplication> activeReturnsIn(List<AdoptionApplication> adoptedBucket) =>
    adoptedBucket.where((a) => isReturnActive(a.returnRequest)).toList();

// ─── Formatting ──────────────────────────────────────────────────────────

/// "3d", "5h", "12m", "just now" — plain elapsed time, no thresholds.
String elapsedSince(DateTime? t, {DateTime? now}) {
  if (t == null) return 'time not recorded';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.isNegative) return 'scheduled';
  if (d.inDays >= 1) return '${d.inDays}d ago';
  if (d.inHours >= 1) return '${d.inHours}h ago';
  if (d.inMinutes >= 1) return '${d.inMinutes}m ago';
  return 'just now';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String longDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';

String plural(int n, String singular, [String? pluralForm]) =>
    '$n ${n == 1 ? singular : (pluralForm ?? '${singular}s')}';
