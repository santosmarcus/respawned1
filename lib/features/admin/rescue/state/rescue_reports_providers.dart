import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';
import 'package:respawnd1/core/repos/clinic_search_repository.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/models/organization/facebook_integration.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/repos/saved_clinics_repository.dart';

// ---- Repositories -----------------------------------------------------

final rescueCaseRepositoryProvider = Provider<RescueCaseRepository>((ref) {
  return RescueCaseRepository();
});

final organizationDirectoryRepositoryProvider = Provider<OrganizationDirectoryRepository>((ref) {
  return OrganizationDirectoryRepository();
});

final orgMembershipServiceProvider = Provider<OrgMembershipService>((ref) {
  return OrgMembershipService();
});

final clinicSearchRepositoryProvider = Provider<ClinicSearchRepository>((ref) {
  return ClinicSearchRepository();
});

final directionsRepositoryProvider = Provider<DirectionsRepository>((ref) {
  return DirectionsRepository();
});

final savedClinicsRepositoryProvider = Provider<SavedClinicsRepository>((ref) {
  return SavedClinicsRepository();
});

/// The signed-in staff/admin user's membership in their organization.
/// Null while unresolved, while signed out, or if they aren't a member of
/// any organization yet. autoDispose so a stale uid's listener doesn't keep
/// running after logout — it's also explicitly invalidated by AdminDrawer's
/// sign-out flow as a belt-and-suspenders measure.
final currentOrgMembershipProvider = StreamProvider.autoDispose<OrgMembership?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(orgMembershipServiceProvider).streamMembership(uid);
});

/// Temporary Organization Admin/Member Access Model spec — the centralized
/// capability resolver every org-scoped screen should watch instead of
/// comparing `membership.role` directly. Same autoDispose lifecycle as
/// [currentOrgMembershipProvider] and invalidated alongside it on sign-out
/// (see admin_drawer.dart).
final currentOrganizationCapabilitiesProvider = StreamProvider.autoDispose<OrganizationCapabilities>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(OrganizationCapabilities.none);
  return ref.watch(orgMembershipServiceProvider).streamCapabilities(uid);
});

/// Which organization the signed-in account is linked to — reuses
/// [OrgMembershipService.resolveOrganizationId] (the same "just which org"
/// lookup admin_dashboard_home_widgets.dart already calls directly) so
/// call sites that only need the id (e.g. gating Facebook publishing on
/// Animal Records) don't each re-derive it separately.
final currentOrganizationIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return ref.watch(orgMembershipServiceProvider).resolveOrganizationId(uid);
});

/// Facebook Page Sharing spec — safe connection metadata for one
/// organization's connected Page, or null if never connected. A failed
/// read surfaces as this provider's error state (never silently treated as
/// "not connected"), so Organization Profile's Facebook section and Animal
/// Records' publish gating can each tell "not connected" apart from
/// "couldn't check."
final facebookIntegrationRepositoryProvider = Provider<FacebookIntegrationRepository>((ref) {
  return FacebookIntegrationRepository();
});

final organizationFacebookIntegrationProvider =
    StreamProvider.family.autoDispose<FacebookIntegration?, String>((ref, organizationId) {
  return ref.watch(facebookIntegrationRepositoryProvider).streamIntegration(organizationId);
});

// ---- Case list / detail streams ---------------------------------------

// autoDispose so a listener is torn down once nothing is watching it anymore
// (e.g. leaving Rescue Reports) instead of staying subscribed to Firestore
// for the rest of the app session.
final casesByStatusesProvider =
    StreamProvider.family.autoDispose<List<RescueCase>, List<RescueStatus>>((ref, statuses) {
  return ref.watch(rescueCaseRepositoryProvider).streamCasesByStatuses(statuses);
});

final caseDetailProvider = StreamProvider.family<RescueCase?, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamCase(caseId);
});

/// Cases with at least one animal currently in [stage] per the
/// denormalized `activeAnimalStages` field (spec §7) — see
/// RescueCaseRepository.streamCasesByActiveStage's own doc comment for why
/// this is needed alongside [casesByStatusesProvider].
final casesByActiveStageProvider = StreamProvider.family.autoDispose<List<RescueCase>, String>((ref, stage) {
  return ref.watch(rescueCaseRepositoryProvider).streamCasesByActiveStage(stage);
});

final caseReportsProvider = StreamProvider.family<List<RescueReport>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamReports(caseId);
});

final caseReferralsProvider = StreamProvider.family<List<Referral>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamReferrals(caseId);
});

final caseActivityLogsProvider = StreamProvider.family<List<ActivityLogEntry>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamActivityLogs(caseId);
});

final caseCommunityReportsProvider = StreamProvider.family<List<CommunityReport>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamCommunityReports(caseId);
});

/// The most recent transporter offer for a case (any status) — drives the
/// Assign Transporter modal's pending/accepted/declined states, gates
/// AdminTrackCasePage's inline pending/declined content (in place of the
/// map) for the reopened-while-pending edge case, and tells
/// RescueDetailPage whether "Assign Transporter" should be blocked because
/// an offer is already active.
final currentAssignmentProvider = StreamProvider.family<TransportAssignment?, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamLatestAssignment(caseId);
});

/// Each transporter's most-recent assignment status across all cases,
/// keyed by riderId — the single source of truth for each transporter
/// card's Available/Pending/Busy chip in Assign Transporter (covers both
/// demo transporters and real ones). A `rejected` latest status is
/// bucketed as Busy by the caller, not Available.
final activeAssignmentsByRiderProvider =
    StreamProvider<Map<String, TransportAssignmentStatus>>((ref) {
  return ref.watch(rescueCaseRepositoryProvider).streamActiveAssignmentsByRider();
});

/// Real accounts with role == 'pet_transporter'.
final petTransportersProvider = StreamProvider<List<PetTransporter>>((ref) {
  return ref.watch(rescueCaseRepositoryProvider).streamPetTransporters();
});

/// Real accounts with role == 'rescue_volunteer' — backs the Volunteers
/// directory page.
final rescueVolunteersProvider = StreamProvider<List<PetTransporter>>((ref) {
  return ref.watch(rescueCaseRepositoryProvider).streamRescueVolunteers();
});

/// Chronological treatment history for a case (subcollection, with legacy
/// array-field fallback — see streamTreatmentLogs's own doc comment).
final treatmentLogsProvider = StreamProvider.family<List<TreatmentLogEntry>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamTreatmentLogs(caseId);
});

/// A case's expense ledger — Cost Tracking's totals are always computed
/// from this list, never stored/edited as a standalone number.
final expensesProvider = StreamProvider.family<List<Expense>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamExpenses(caseId);
});

/// Which animal-array indexes already have a created animal record —
/// drives the Intake Details "N of M records created" progress and the
/// multi-animal creation flow's duplicate prevention.
final completedAnimalRecordIndexesProvider = StreamProvider.family<Set<int>, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamCompletedAnimalRecordIndexes(caseId);
});

/// Display-ready transporter details (vehicle/plate/photo/phone) for a
/// given accepted assignment — used by Intake Details' default-transporter
/// display and the shared TransporterDetailsCard on Track Case.
typedef TransporterProfileQuery = ({String uid, String fallbackName, String type, bool isDemo});

final transporterProfileProvider =
    FutureProvider.family<TransporterProfile, TransporterProfileQuery>((ref, query) {
  return ref.read(rescueCaseRepositoryProvider).resolveTransporterProfile(
        uid: query.uid,
        fallbackName: query.fallbackName,
        type: query.type,
        isDemo: query.isDemo,
      );
});

// ---- List filter state --------------------------------------------------

/// The six primary pipeline tabs already used by rescue_reports_page.dart,
/// each mapped onto the RescueStatus values that belong in that tab.
enum RescuePipelineTab {
  review,
  assign,
  ongoing,
  treatment,
  intake,
  rejected,
  // Cases closed through the controlled Close Case flow (closeCase ->
  // RescueStatus.cancelled) — same reasoning as [rejected] getting its own
  // tab: previously only reachable through the filter-sheet override
  // (kSecondaryStatuses), which meant a closed case looked like it had
  // vanished unless an admin knew to check there.
  closed;

  String get label => switch (this) {
        RescuePipelineTab.review => 'Review',
        RescuePipelineTab.assign => 'Assign',
        RescuePipelineTab.ongoing => 'Ongoing',
        RescuePipelineTab.treatment => 'In Treatment',
        RescuePipelineTab.intake => 'Intake',
        RescuePipelineTab.rejected => 'Rejected',
        RescuePipelineTab.closed => 'Closed',
      };

  // Deliberately `const` — casesByStatusesProvider is a StreamProvider.family
  // keyed by this List, and Dart's List uses identity equality (no built-in
  // structural ==). A non-const list literal here would return a distinct
  // object on every call, so every rebuild of a widget calling `.statuses`
  // (e.g. the pipeline-tab badges, one per tab, rebuilt on every frame) would
  // register as a brand-new family key: a brand-new Firestore listener that
  // never gets torn down, endlessly duplicating (and re-erroring) the same
  // query. `const` literals with equal contents are canonicalized by Dart —
  // every call for the same tab returns the exact same object — so the
  // family provider correctly resolves to one stable, reused instance.
  List<RescueStatus> get statuses => switch (this) {
        RescuePipelineTab.review => const [RescueStatus.pendingReview, RescueStatus.accepted],
        RescuePipelineTab.assign => const [RescueStatus.awaitingAssignment],
        RescuePipelineTab.ongoing => const [RescueStatus.ongoing],
        RescuePipelineTab.treatment => const [RescueStatus.treatment],
        RescuePipelineTab.intake => const [RescueStatus.intake],
        // RescueStatus.rejected's own queryValues/_legacyAliases are just
        // ['rejected'] — no 'dismissed'/'cancelled'/'withdrawn' writer for
        // rescue cases exists anywhere in this codebase today (traced every
        // writer of RescueCaseRepository before adding this tab), so this
        // tab intentionally shows only true rejections, not those other
        // terminal buckets.
        RescuePipelineTab.rejected => const [RescueStatus.rejected],
        RescuePipelineTab.closed => const [RescueStatus.cancelled],
      };
}

/// Cases belonging under [tab] — merges the existing status-based query
/// with a denormalized `activeAnimalStages` match (spec §7) for tabs that
/// can be affected by a mixed-stage case whose scalar `status` no longer
/// reflects every animal (currently just Intake: a case with one animal
/// moved to Intake while another is still in_treatment keeps
/// `status: 'in_treatment'` — see RescueCaseRepository's
/// `_deriveCaseStatusOverride` — so the plain status query alone would
/// miss it under Intake). Every other tab is untouched, degrading to
/// exactly [casesByStatusesProvider]'s own result. De-duplicates by case
/// id so a case matching both queries (e.g. status already flipped to
/// 'intake' AND still carrying the stage tag) is never listed twice.
final casesForTabProvider =
    Provider.autoDispose.family<AsyncValue<List<RescueCase>>, RescuePipelineTab>((ref, tab) {
  final byStatus = ref.watch(casesByStatusesProvider(tab.statuses));
  if (tab != RescuePipelineTab.intake) return byStatus;

  final byStage = ref.watch(casesByActiveStageProvider('intake'));
  if (byStatus.isLoading || byStage.isLoading) return const AsyncValue.loading();
  if (byStatus.hasError) return byStatus;
  if (byStage.hasError) return byStage;

  final merged = <String, RescueCase>{};
  for (final c in byStatus.asData?.value ?? const <RescueCase>[]) {
    merged[c.id] = c;
  }
  for (final c in byStage.asData?.value ?? const <RescueCase>[]) {
    merged[c.id] = c;
  }
  return AsyncValue.data(merged.values.toList());
});

/// Extra statuses reachable only through the status filter (not one of the
/// pipeline tabs above) — referral/duplicate/terminal states. Rejected and
/// Cancelled are deliberately NOT listed here anymore now that each has
/// its own pipeline tab (RescuePipelineTab.rejected / .closed) — keeping
/// them in both places would just make the filter-sheet override
/// redundant with the tab.
const List<RescueStatus> kSecondaryStatuses = [
  RescueStatus.referred,
  RescueStatus.possibleDuplicate,
  RescueStatus.merged,
  RescueStatus.completed,
];

class RescueFilters {
  final String searchText;
  final UrgencyLevel? urgency;
  final String? species;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? locationQuery;

  /// When set, overrides the active pipeline tab's status list — lets the
  /// filter bar reach referred/possibleDuplicate/merged/completed/cancelled
  /// cases that the six quick tabs don't cover (rejected has its own tab).
  final RescueStatus? statusOverride;

  const RescueFilters({
    this.searchText = '',
    this.urgency,
    this.species,
    this.fromDate,
    this.toDate,
    this.locationQuery,
    this.statusOverride,
  });

  bool get isEmpty =>
      searchText.isEmpty &&
      urgency == null &&
      species == null &&
      fromDate == null &&
      toDate == null &&
      (locationQuery == null || locationQuery!.isEmpty) &&
      statusOverride == null;

  RescueFilters copyWith({
    String? searchText,
    UrgencyLevel? urgency,
    bool clearUrgency = false,
    String? species,
    bool clearSpecies = false,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearDateRange = false,
    String? locationQuery,
    bool clearLocationQuery = false,
    RescueStatus? statusOverride,
    bool clearStatusOverride = false,
  }) {
    return RescueFilters(
      searchText: searchText ?? this.searchText,
      urgency: clearUrgency ? null : (urgency ?? this.urgency),
      species: clearSpecies ? null : (species ?? this.species),
      fromDate: clearDateRange ? null : (fromDate ?? this.fromDate),
      toDate: clearDateRange ? null : (toDate ?? this.toDate),
      locationQuery: clearLocationQuery ? null : (locationQuery ?? this.locationQuery),
      statusOverride: clearStatusOverride ? null : (statusOverride ?? this.statusOverride),
    );
  }

  /// Applies every client-side filter (everything except status, which is
  /// already handled server-side by the query the list screen issues).
  bool matches(RescueCase c) {
    if (urgency != null && UrgencyLevel.fromFirestoreValue(c.urgency) != urgency) return false;
    if (species != null && species!.isNotEmpty) {
      // Matches if ANY of the case's animals are that species — not just
      // the first/legacy one — so a "Dog ×2, Cat" case is found by both a
      // Dog filter and a Cat filter, without needing separate cards.
      final wanted = species!.toLowerCase();
      final matchesAnySpecies = c.allSpecies.any((s) => s.toLowerCase() == wanted);
      if (!matchesAnySpecies) return false;
    }
    if (fromDate != null && (c.createdAt == null || c.createdAt!.isBefore(fromDate!))) {
      return false;
    }
    if (toDate != null && (c.createdAt == null || c.createdAt!.isAfter(toDate!))) {
      return false;
    }
    if (locationQuery != null && locationQuery!.trim().isNotEmpty) {
      final q = locationQuery!.trim().toLowerCase();
      if (c.address == null || !c.address!.toLowerCase().contains(q)) return false;
    }
    if (searchText.trim().isNotEmpty) {
      final q = searchText.trim().toLowerCase();
      final haystack = [
        c.condition,
        c.address,
        c.reporterName,
        c.id,
        ...c.allSpecies, // every animal's species, not just the legacy first one
      ].whereType<String>().join(' ').toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    return true;
  }
}

class RescueFilterNotifier extends Notifier<RescueFilters> {
  @override
  RescueFilters build() => const RescueFilters();

  void setSearchText(String value) => state = state.copyWith(searchText: value);
  void setUrgency(UrgencyLevel? value) =>
      state = value == null ? state.copyWith(clearUrgency: true) : state.copyWith(urgency: value);
  void setSpecies(String? value) =>
      state = (value == null || value.isEmpty)
          ? state.copyWith(clearSpecies: true)
          : state.copyWith(species: value);
  void setDateRange(DateTime? from, DateTime? to) => state = state.copyWith(
        fromDate: from,
        toDate: to,
        clearDateRange: from == null && to == null,
      );
  void setLocationQuery(String? value) => state = (value == null || value.isEmpty)
      ? state.copyWith(clearLocationQuery: true)
      : state.copyWith(locationQuery: value);
  void setStatusOverride(RescueStatus? value) => state = value == null
      ? state.copyWith(clearStatusOverride: true)
      : state.copyWith(statusOverride: value);

  void replaceAll(RescueFilters filters) => state = filters;

  void clear() => state = const RescueFilters();
}

final rescueFilterProvider = NotifierProvider<RescueFilterNotifier, RescueFilters>(
  RescueFilterNotifier.new,
);

class RescuePipelineTabNotifier extends Notifier<RescuePipelineTab> {
  @override
  RescuePipelineTab build() => RescuePipelineTab.review;

  void select(RescuePipelineTab tab) => state = tab;
}

final rescuePipelineTabProvider = NotifierProvider<RescuePipelineTabNotifier, RescuePipelineTab>(
  RescuePipelineTabNotifier.new,
);

/// The effective status list the list screen should query: the filter
/// bar's explicit override if set, otherwise the active pipeline tab.
final effectiveStatusesProvider = Provider<List<RescueStatus>>((ref) {
  final override = ref.watch(rescueFilterProvider).statusOverride;
  if (override != null) return [override];
  return ref.watch(rescuePipelineTabProvider).statuses;
});

/// Cases for the effective status selection, with all client-side filters
/// from [rescueFilterProvider] applied.
///
/// The filter bar's explicit status override (referred/possibleDuplicate/
/// merged/completed/cancelled — [kSecondaryStatuses], none of
/// which are affected by per-animal stage splitting) still queries
/// directly by status. Otherwise this follows the active pipeline tab via
/// [casesForTabProvider], which is stage-aware for Intake (spec §7).
///
/// autoDispose to match [casesByStatusesProvider] — otherwise, as a
/// permanently-alive Provider watching an autoDispose family member, it
/// would itself hold that family instance's listen count above zero
/// forever, defeating the point of the family being autoDispose.
final filteredCasesProvider = Provider.autoDispose<AsyncValue<List<RescueCase>>>((ref) {
  final override = ref.watch(rescueFilterProvider).statusOverride;
  final casesAsync = override != null
      ? ref.watch(casesByStatusesProvider([override]))
      : ref.watch(casesForTabProvider(ref.watch(rescuePipelineTabProvider)));
  final filters = ref.watch(rescueFilterProvider);
  return casesAsync.whenData((cases) => cases.where(filters.matches).toList());
});
