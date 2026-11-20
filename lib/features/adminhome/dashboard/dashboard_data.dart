import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/utils/org_list_scope.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/illness_entry.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/transporter_application_repository.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/events/state/event_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/core/models/rescue/medication.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';

/// Shared, derived dashboard data. Everything here is computed from the
/// SAME providers the module screens already stream, plus three
/// collection-group listeners (vaccinations, expenses, and the existing
/// transport-assignment one) — no writes, no invented values.

// ─── Rescue snapshot ─────────────────────────────────────────────────────

class RescueSnapshot {
  final Map<RescueStage, List<RescueCase>> byStage;
  const RescueSnapshot(this.byStage);

  /// Every active case once, even if it appears under two stages.
  List<RescueCase> get all {
    final seen = <String, RescueCase>{};
    for (final list in byStage.values) {
      for (final c in list) {
        seen.putIfAbsent(c.id, () => c);
      }
    }
    return seen.values.toList();
  }

  int count(RescueStage s) => byStage[s]?.length ?? 0;
  List<RescueCase> of(RescueStage s) => byStage[s] ?? const [];

  /// Critical cases still waiting on staff: not yet reviewed, without a
  /// clinic or rider, or stalled in the field. Cases already in transit, at
  /// the vet or in intake are moving and are not counted.
  List<RescueCase> get urgentWaiting => [
    for (final s in kWaitingStages) ...of(s),
  ].where((c) => UrgencyLevel.fromFirestoreValue(c.urgency) == UrgencyLevel.critical).toList();
}

const List<RescueStage> kWaitingStages = [
  RescueStage.review,
  RescueStage.clinic,
  RescueStage.transporter,
  RescueStage.fieldIssue,
];

/// Where a tap on the urgent count should land: the Review tab while any
/// urgent case still needs review or a clinic, otherwise Assign.
RescuePipelineTab urgentTabFor(List<RescueCase> urgent) =>
    urgent.isNotEmpty && urgent.every((c) => c.status == RescueStatus.awaitingAssignment)
        ? RescuePipelineTab.assign
        : RescuePipelineTab.review;

final dashboardRescueSnapshotProvider = Provider.autoDispose<AsyncValue<RescueSnapshot>>((ref) {
  final review = ref.watch(casesForTabProvider(RescuePipelineTab.review));
  final assign = ref.watch(casesForTabProvider(RescuePipelineTab.assign));
  final ongoing = ref.watch(casesForTabProvider(RescuePipelineTab.ongoing));
  final treatment = ref.watch(casesForTabProvider(RescuePipelineTab.treatment));
  final intake = ref.watch(casesForTabProvider(RescuePipelineTab.intake));
  final field = ref.watch(casesByStatusesProvider(kFieldIssueStatuses));
  final parts = [review, assign, ongoing, treatment, intake, field];
  for (final p in parts) {
    if (p.hasError) return AsyncValue.error(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncValue.loading();
  final reviewCases = review.requireValue;
  return AsyncValue.data(
    RescueSnapshot({
      RescueStage.review: reviewCases.where((c) => c.status == RescueStatus.pendingReview).toList(),
      RescueStage.clinic: reviewCases.where((c) => c.status == RescueStatus.accepted).toList(),
      RescueStage.transporter: assign.requireValue,
      RescueStage.transit: ongoing.requireValue,
      RescueStage.treatment: treatment.requireValue,
      RescueStage.intake: intake.requireValue,
      RescueStage.fieldIssue: field.requireValue,
    }),
  );
});

// ─── Transport supply ────────────────────────────────────────────────────

class TransportSupply {
  final int registered;
  final int verified;
  final int free;
  final int onAssignment;
  const TransportSupply({
    required this.registered,
    required this.verified,
    required this.free,
    required this.onAssignment,
  });
}

/// "Free" = online now (fresh presence) with no pending/accepted offer —
/// the same rule Assign Transporter uses.
final transportSupplyProvider = Provider.autoDispose<AsyncValue<TransportSupply>>((ref) {
  final transporters = ref.watch(petTransportersProvider);
  final active = ref.watch(activeAssignmentsByRiderProvider);
  if (transporters.hasError) return AsyncValue.error(transporters.error!, StackTrace.current);
  if (active.hasError) return AsyncValue.error(active.error!, StackTrace.current);
  if (!transporters.hasValue || !active.hasValue) return const AsyncValue.loading();
  final busy = active.requireValue;
  bool isBusy(String uid) {
    final s = busy[uid];
    return s == TransportAssignmentStatus.pending || s == TransportAssignmentStatus.accepted;
  }

  final list = transporters.requireValue;
  return AsyncValue.data(
    TransportSupply(
      registered: list.length,
      verified: list.where((t) => t.isVerified).length,
      free: list.where((t) => t.isOnline && !isBusy(t.uid)).length,
      onAssignment: list.where((t) => isBusy(t.uid)).length,
    ),
  );
});

// ─── Shelter occupancy ───────────────────────────────────────────────────

/// Where shelter space is going right now. Animals at the vet keep a
/// reserved space (they return to the shelter after discharge); animals in
/// an active quarantine count against isolation; intake-stage animals and
/// approved adoption returns are "arriving".
class ShelterOccupancy {
  final int inShelter;
  final int atVet;
  final int isolation;
  final int arriving;
  final int? capacity;
  final int? isolationCapacity;

  const ShelterOccupancy({
    required this.inShelter,
    required this.atVet,
    required this.isolation,
    required this.arriving,
    this.capacity,
    this.isolationCapacity,
  });

  int get used => inShelter + atVet + isolation;

  /// Null when capacity hasn't been set — never assumed.
  int? get free => capacity == null ? null : capacity! - used - arriving;

  bool get isolationFull => isolationCapacity != null && isolation >= isolationCapacity!;
}

final shelterOccupancyProvider = Provider.autoDispose<AsyncValue<ShelterOccupancy>>((ref) {
  final snapAsync = ref.watch(dashboardRescueSnapshotProvider);
  final recordsAsync = ref.watch(allAnimalRecordsProvider);
  final adopted = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted)));
  final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
  if (snapAsync.hasError) return AsyncValue.error(snapAsync.error!, StackTrace.current);
  if (recordsAsync.hasError) return AsyncValue.error(recordsAsync.error!, StackTrace.current);
  if (!snapAsync.hasValue || !recordsAsync.hasValue) return const AsyncValue.loading();

  final snap = snapAsync.requireValue;
  final inCare = recordsAsync.requireValue.where(isInCare).toList();
  final treatment = snap.of(RescueStage.treatment);
  final treatmentIds = treatment.map((c) => c.id).toSet();
  final atVetFromCases = treatment.fold<int>(0, (s, c) => s + animalsInTreatment(c));
  // An animal record whose open medical case isn't (yet) in the treatment
  // stage — e.g. still in transit to the clinic — is also away at the vet.
  final atVetRecordsOutsideCases = inCare
      .where((a) => hasOpenMedicalCase(a) && !treatmentIds.contains(a.currentCaseId))
      .length;
  // Animals an admin put in isolation use an isolation space, not a general one.
  bool isolated(AnimalRecord a) => a.careStatus == CareStatus.isolation;
  final inShelter = inCare.where((a) => !hasOpenMedicalCase(a) && !isolated(a)).length;
  final isolatedRecords = inCare.where((a) => !hasOpenMedicalCase(a) && isolated(a)).length;

  final quarantined = [...snap.of(RescueStage.intake), ...treatment].where((c) => c.isQuarantineActive);
  final quarantineIds = quarantined.map((c) => c.id).toSet();
  final isolation = quarantined.fold<int>(0, (s, c) => s + c.animalCount) + isolatedRecords;
  final intakeArriving = snap
      .of(RescueStage.intake)
      .where((c) => !quarantineIds.contains(c.id))
      .fold<int>(0, (s, c) => s + (c.animalStageCounts['intake'] ?? c.animalCount));
  final returnsArriving = adopted.asData?.value == null
      ? 0
      : activeReturnsIn(adopted.asData!.value).where((a) => returnExpectedBack(a.returnRequest!)).length;

  return AsyncValue.data(
    ShelterOccupancy(
      inShelter: inShelter,
      atVet: atVetFromCases + atVetRecordsOutsideCases,
      isolation: isolation,
      arriving: intakeArriving + returnsArriving,
      capacity: settings.capacity,
      isolationCapacity: settings.isolationCapacity,
    ),
  );
});

// ─── Medication orders ───────────────────────────────────────────────────

/// Every active medication order, grouped by animal id (own organization;
/// platform staff: all). One collection-group listener, shared by Rescue
/// readiness, Shelter care and Adoption. An animal with no entry has no
/// medication running, so its course counts as complete.
final activeMedicationPlansByAnimalProvider = StreamProvider.autoDispose<Map<String, List<MedicationPlan>>>((ref) {
  return ref.watch(animalMedicationRepositoryProvider).watchActivePlansByAnimal();
});

// ─── Health records (vaccinations) ───────────────────────────────────────

/// Every vaccination record, grouped by animal id. One collection-group
/// listener instead of one listener per animal.
/// Every preventive-care record (deworming, flea & tick, vet checkup),
/// grouped by animal id — feeds the dashboard's overdue-care alert.
final careRecordsByAnimalProvider = StreamProvider.autoDispose<Map<String, List<CareRecord>>>((ref) {
  // Own organization only (platform staff: all); see OrgListScope.
  return OrgListScope.watch(FirebaseFirestore.instance.collectionGroup('careRecords'), empty: const {}, (snap) {
    final out = <String, List<CareRecord>>{};
    for (final d in snap.docs) {
      final animalId = d.reference.parent.parent?.id;
      if (animalId == null) continue;
      try {
        out.putIfAbsent(animalId, () => []).add(CareRecord.fromFirestore(d, animalId));
      } catch (e) {
        debugPrint('[Dashboard] skipping unparseable care record ${d.id}: $e');
      }
    }
    return out;
  });
});

/// Analytics gap 5: every illness entry of the organization's animals.
final allIllnessesProvider = StreamProvider.autoDispose<List<IllnessEntry>>((ref) {
  return OrgListScope.watch(FirebaseFirestore.instance.collectionGroup('illnesses'), empty: const <IllnessEntry>[],
          (snap) {
        return [
        for (final d in snap.docs)
          if (d.reference.parent.parent case final animal?) ?IllnessEntry.fromFirestore(d, animal.id),
        ];
      });
});

final vaccinationsByAnimalProvider = StreamProvider.autoDispose<Map<String, List<VaccinationRecord>>>((ref) {
  return OrgListScope.watch(FirebaseFirestore.instance.collectionGroup('vaccinations'), empty: const {}, (snap) {
    final out = <String, List<VaccinationRecord>>{};
    for (final d in snap.docs) {
      final animalId = d.reference.parent.parent?.id;
      if (animalId == null) continue;
      try {
        out.putIfAbsent(animalId, () => []).add(VaccinationRecord.fromFirestore(d, animalId));
      } catch (e) {
        debugPrint('[Dashboard] skipping unparseable vaccination ${d.id}: $e');
      }
    }
    return out;
  });
});

/// "Not recorded" means no vaccination record exists — it never means the
/// animal wasn't vaccinated. Due-soon uses an explicit 14-day window that
/// the UI labels as such.
enum HealthRecordStatus { completed, dueSoon, overdue, notRecorded }

const int kDueSoonDays = 14;

HealthRecordStatus healthStatusOf(List<VaccinationRecord>? records, {DateTime? now}) {
  if (records == null || records.isEmpty) return HealthRecordStatus.notRecorded;
  final today = now ?? DateTime.now();
  // Latest dose per vaccine decides whether that vaccine is current.
  final latest = <String, VaccinationRecord>{};
  for (final r in records) {
    final key = r.vaccineName.toLowerCase();
    if (!latest.containsKey(key) || r.dateAdministered.isAfter(latest[key]!.dateAdministered)) latest[key] = r;
  }
  if (latest.values.any((r) => r.nextDueDate.isBefore(today))) return HealthRecordStatus.overdue;
  if (latest.values.any((r) => r.nextDueDate.difference(today).inDays <= kDueSoonDays)) {
    return HealthRecordStatus.dueSoon;
  }
  return HealthRecordStatus.completed;
}

DateTime? nextVaccineDue(List<VaccinationRecord>? records) {
  if (records == null || records.isEmpty) return null;
  return records.map((r) => r.nextDueDate).reduce((a, b) => a.isBefore(b) ? a : b);
}

// ─── Expenses (authorized viewers only) ──────────────────────────────────

/// All case expenses via one collection-group listener. Only watched by
/// widgets that are already behind canManageFinancesProvider.
final allCaseExpensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  return OrgListScope.watch(FirebaseFirestore.instance.collectionGroup('expenses'), empty: const [], (snap) {
    final out = <Expense>[];
    for (final d in snap.docs) {
      final caseId = d.reference.parent.parent?.id;
      if (caseId == null || d.reference.parent.parent?.parent.id != 'cases') continue;
      try {
        out.add(Expense.fromFirestore(d, caseId));
      } catch (e) {
        debugPrint('[Dashboard] skipping unparseable expense ${d.id}: $e');
      }
    }
    return out;
  });
});

// ─── Closed cases (outcomes / diversion) ─────────────────────────────────

/// Terminal statuses — `const` for a stable family key.
const List<RescueStatus> kClosedCaseStatuses = [
  RescueStatus.completed,
  RescueStatus.cancelled,
  RescueStatus.rejected,
  RescueStatus.referred,
];

final closedCasesProvider = Provider.autoDispose<AsyncValue<List<RescueCase>>>((ref) {
  return ref.watch(casesByStatusesProvider(kClosedCaseStatuses));
});

// ─── People: volunteer and transporter applications ─────────────────────

/// Rescue volunteer sign-ups (kind 'independent') waiting for review, for
/// the people who can decide them: staff with the Volunteers permission
/// (never a rescue volunteer's own team) and platform staff.
final pendingVolunteerApplicationsProvider = StreamProvider.autoDispose<List<OrganizationReviewItem>>((ref) {
  final canReview = (ref.watch(currentOrganizationCapabilitiesProvider).asData?.value.canManageVolunteers ?? false) ||
      (ref.watch(isPlatformStaffProvider).asData?.value ?? false);
  if (!canReview) return Stream.value(const <OrganizationReviewItem>[]);
  return OrganizationRepository().streamForReview(OrgVerificationStatus.pending, kind: OrgKind.independent);
});

final pendingTransporterApplicationsProvider = StreamProvider.autoDispose<List<TransporterApplication>>((ref) {
  return TransporterApplicationRepository().watchByStatus(TransporterApplicationStatus.pending);
});

// ─── Events ──────────────────────────────────────────────────────────────

/// The organization's events that haven't ended and aren't cancelled,
/// soonest first.
final upcomingEventsProvider = Provider.autoDispose<AsyncValue<List<VolunteerEvent>>>((ref) {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId.hasError) return AsyncValue.error(orgId.error!, orgId.stackTrace ?? StackTrace.current);
  if (!orgId.hasValue) return const AsyncValue.loading();
  final id = orgId.requireValue;
  if (id == null) return const AsyncValue.data([]);
  return ref.watch(organizationEventsProvider(id)).whenData(
        (list) => list.where((e) => !e.isCancelled && !e.isPast).toList()..sort((a, b) => a.startAt.compareTo(b.startAt)),
  );
});

// ─── Post-adoption follow-ups (this organization only) ───────────────────

typedef OpenFollowUp = ({AdoptionApplication app, FollowUpRecord record});

/// Every still-open follow-up whose adoption belongs to this organization.
/// The follow-up stream itself spans all organizations, so it is matched
/// against the organization's own adopted applications.
final orgOpenFollowUpsProvider = Provider.autoDispose<AsyncValue<List<OpenFollowUp>>>((ref) {
  final open = ref.watch(_openFollowUpsProvider);
  final adopted = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted)));
  if (open.hasError) return AsyncValue.error(open.error!, open.stackTrace ?? StackTrace.current);
  if (adopted.hasError) return AsyncValue.error(adopted.error!, adopted.stackTrace ?? StackTrace.current);
  if (!open.hasValue || !adopted.hasValue) return const AsyncValue.loading();
  final byId = {for (final a in adopted.requireValue) a.id: a};
  return AsyncValue.data([
    for (final f in open.requireValue)
      if (byId[f.applicationId] != null) (app: byId[f.applicationId]!, record: f.record),
  ]);
});

final _openFollowUpsProvider = StreamProvider.autoDispose<List<({String applicationId, FollowUpRecord record})>>((ref) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamOpenFollowUps();
});

// ─── Small helpers ───────────────────────────────────────────────────────

DateTime? tsOf(Object? v) => v is Timestamp ? v.toDate() : null;

/// Analytics gap 3: when an animal record was confirmed ready for adoption.
/// `readyForAdoptionAt` is stamped from now on; older records fall back to
/// the readiness checklist's own `confirmedAt` (an ISO string). Null when
/// the animal was never confirmed ready in the app.
DateTime? readyForAdoptionAtOf(Map<String, dynamic> raw) {
  final stamped = tsOf(raw['readyForAdoptionAt']);
  if (stamped != null) return stamped;
  final r = raw['adoptionReadiness'];
  final at = r is Map ? r['confirmedAt'] : null;
  if (at is Timestamp) return at.toDate();
  return at is String ? DateTime.tryParse(at) : null;
}

bool inPeriod(DateTime? t, DateTime from, DateTime to) => t != null && !t.isBefore(from) && t.isBefore(to);

double? median(List<num> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}

/// Very small groups are flagged, not hidden — the UI greys them out.
const int kMinGroupSize = 10;

/// The age strings animal records store look like "2 Years" / "6 Months"
/// (create_animal_record_page.dart). Returns null when unparseable so it
/// lands in "age not recorded" instead of a guessed bucket.
double? ageInYears(String age) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*([a-zA-Z]+)').firstMatch(age);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null) return null;
  final unit = m.group(2)!.toLowerCase();
  if (unit.startsWith('y')) return n;
  if (unit.startsWith('m')) return n / 12;
  if (unit.startsWith('w')) return n / 52;
  if (unit.startsWith('d')) return n / 365;
  return null;
}

/// Same buckets the adoption listing already uses (adoption_page.dart).
String? ageGroupOf(AnimalRecord a) {
  final y = ageInYears(a.age);
  if (y == null) return null;
  if (y < 0.5) return 'Baby (0–6 mo)';
  if (y < 2) return 'Young (6 mo–2 y)';
  if (y < 7) return 'Adult (2–7 y)';
  return 'Senior (7+ y)';
}

bool isLargeAdultDog(AnimalRecord a) =>
    a.species.toLowerCase() == 'dog' && a.size.toLowerCase().contains('large') && (ageInYears(a.age) ?? 0) >= 2;

// ─── Continuing care ─────────────────────────────────────────────────────

/// One reason an animal in care needs looking after beyond the daily
/// rounds. Every reason comes from a recorded field or order.
class CareNeed {
  final String label;
  final DashSeverity severity;
  final IconData icon;
  const CareNeed(this.label, this.severity, this.icon);
}

/// Why [a] needs continuing care, most urgent first. Empty when nothing is
/// recorded. [plans] are the animal's active medication orders, [missedDoses]
/// its missed doses over the past week, [vaccines] its vaccination status.
List<CareNeed> continuingCareNeedsOf(
    AnimalRecord a, {
      List<MedicationPlan>? plans,
      int missedDoses = 0,
      HealthRecordStatus? vaccines,
    }) {
  String text(String? v) => (v ?? '').trim();
  final meds = plans ?? const <MedicationPlan>[];
  final needs = <CareNeed>[
    if (hasOpenMedicalCase(a)) const CareNeed('In treatment', DashSeverity.critical, Icons.local_hospital),
    if (missedDoses > 0)
      CareNeed('${plural(missedDoses, 'missed dose')} this week', DashSeverity.critical, Icons.error_outline),
    if (vaccines == HealthRecordStatus.overdue) const CareNeed('Vaccine overdue', DashSeverity.critical, Icons.vaccines),
    if (meds.isNotEmpty)
      CareNeed(
        'Medication: ${meds.take(2).map((p) => p.drug).join(', ')}${meds.length > 2 ? ' +${meds.length - 2}' : ''}',
        DashSeverity.warning,
        Icons.medication,
      )
    else if (text(a.health.currentMedications).isNotEmpty)
      CareNeed('Medication: ${text(a.health.currentMedications)}', DashSeverity.warning, Icons.medication),
    if (a.careStatus == CareStatus.isolation) const CareNeed('Isolation', DashSeverity.warning, Icons.do_not_touch),
    if (a.careStatus == CareStatus.recovering) const CareNeed('Recovering', DashSeverity.info, Icons.healing),
    if (a.hasSpecialNeeds)
      CareNeed(
        a.specialNeedsTypes.isEmpty ? 'Special needs' : 'Special needs: ${a.specialNeedsTypes.take(2).join(', ')}',
        DashSeverity.info,
        Icons.accessible,
      ),
    if (text(a.health.chronicConditions).isNotEmpty)
      CareNeed('Chronic: ${text(a.health.chronicConditions)}', DashSeverity.info, Icons.monitor_heart),
  ];
  return needs;
}

/// Every animal in care that needs continuing care, with its needs, most
/// urgent first. Shared by Rescue readiness and Shelter care so both list
/// the same animals.
List<(AnimalRecord, List<CareNeed>)> animalsNeedingCare(
    List<AnimalRecord> records, {
      Map<String, List<MedicationPlan>>? plans,
      Map<String, int>? missedDoses,
      Map<String, List<VaccinationRecord>>? vaccinations,
    }) {
  return [
    for (final a in records.where(isInCare))
      (
      a,
      continuingCareNeedsOf(
        a,
        plans: plans?[a.id],
        missedDoses: missedDoses?[a.id] ?? 0,
        vaccines: vaccinations == null ? null : healthStatusOf(vaccinations[a.id]),
      ),
      ),
  ].where((e) => e.$2.isNotEmpty).toList()
    ..sort((x, y) => careNeedRank(x.$2).compareTo(careNeedRank(y.$2)));
}

/// Lower is more urgent: the worst need first, then the number of needs.
int careNeedRank(List<CareNeed> needs) {
  if (needs.isEmpty) return 1 << 20;
  final worst = needs.map((n) => n.severity.index).reduce((a, b) => a < b ? a : b);
  return worst * 100 - needs.length;
}

// ─── Adoption readiness (dashboard) ──────────────────────────────────────

/// One of the four things that must be done before an animal is turned
/// over for adoption. [done] null = not recorded (a gap, never a pass).
class TurnoverCheck {
  final String label;
  final bool? done;
  final String detail;
  const TurnoverCheck(this.label, this.done, this.detail);
}

/// Vaccinations complete, spayed/neutered, medication course finished and
/// behavior assessed. Behavior counts as assessed only when staff confirmed
/// it on the adoption readiness checklist; recorded temperament alone is
/// shown as not yet assessed.
List<TurnoverCheck> turnoverChecksFor(
    AnimalRecord a, {
      required HealthRecordStatus? vaccines,
      List<MedicationPlan>? plans,
    }) {
  final TurnoverCheck vax = switch (vaccines) {
    HealthRecordStatus.completed || HealthRecordStatus.dueSoon =>
    const TurnoverCheck('Vaccinations', true, 'Up to date'),
    HealthRecordStatus.overdue => const TurnoverCheck('Vaccinations', false, 'A vaccine is overdue'),
    _ => a.raw['vaccinated'] == true
        ? const TurnoverCheck('Vaccinations', true, 'Marked vaccinated')
        : const TurnoverCheck('Vaccinations', null, 'No vaccine records'),
  };
  final sterilized = a.health.sterilized;
  final spay = TurnoverCheck(
    'Spay/neuter',
    sterilized,
    sterilized == null ? 'Not recorded' : (sterilized ? 'Done' : 'Not done yet'),
  );
  final active = plans ?? const <MedicationPlan>[];
  final medsText = (a.health.currentMedications ?? '').trim();
  final meds = active.isNotEmpty
      ? TurnoverCheck('Medication', false, 'Still on ${active.first.drug}')
      : medsText.isNotEmpty
      ? TurnoverCheck('Medication', false, 'Record says: $medsText')
      : const TurnoverCheck('Medication', true, 'No course running');
  final r = a.raw['adoptionReadiness'];
  final checks = r is Map ? r['checks'] : null;
  final behaviorEntry = checks is Map ? checks['behavior'] : null;
  final behaviorOk = behaviorEntry is Map && behaviorEntry['confirmed'] == true;
  final behavior = behaviorOk
      ? const TurnoverCheck('Behavior', true, 'Assessed by staff')
      : (a.keyCharacteristics.isNotEmpty
      ? TurnoverCheck('Behavior', null, 'Temperament noted, not assessed: ${a.keyCharacteristics.take(2).join(', ')}')
      : const TurnoverCheck('Behavior', null, 'Not assessed'));
  return [vax, spay, meds, behavior];
}
