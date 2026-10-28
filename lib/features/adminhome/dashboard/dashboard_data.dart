import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

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
}

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
  final inShelter = inCare.where((a) => !hasOpenMedicalCase(a)).length;

  final quarantined = [...snap.of(RescueStage.intake), ...treatment].where((c) => c.isQuarantineActive);
  final quarantineIds = quarantined.map((c) => c.id).toSet();
  final isolation = quarantined.fold<int>(0, (s, c) => s + c.animalCount);
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

// ─── Health records (vaccinations) ───────────────────────────────────────

/// Every vaccination record, grouped by animal id. One collection-group
/// listener instead of one listener per animal.
final vaccinationsByAnimalProvider = StreamProvider.autoDispose<Map<String, List<VaccinationRecord>>>((ref) {
  return FirebaseFirestore.instance.collectionGroup('vaccinations').snapshots().map((snap) {
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
  return FirebaseFirestore.instance.collectionGroup('expenses').snapshots().map((snap) {
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

// ─── Small helpers ───────────────────────────────────────────────────────

DateTime? tsOf(Object? v) => v is Timestamp ? v.toDate() : null;

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
