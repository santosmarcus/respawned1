import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/clinic_search_repository.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
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
/// any organization yet.
final currentOrgMembershipProvider = StreamProvider<OrgMembership?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(orgMembershipServiceProvider).streamMembership(uid);
});

// ---- Case list / detail streams ---------------------------------------

final casesByStatusesProvider =
    StreamProvider.family<List<RescueCase>, List<RescueStatus>>((ref, statuses) {
  return ref.watch(rescueCaseRepositoryProvider).streamCasesByStatuses(statuses);
});

final caseDetailProvider = StreamProvider.family<RescueCase?, String>((ref, caseId) {
  return ref.watch(rescueCaseRepositoryProvider).streamCase(caseId);
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

// ---- List filter state --------------------------------------------------

/// The five primary pipeline tabs already used by rescue_reports_page.dart,
/// each mapped onto the RescueStatus values that belong in that tab.
enum RescuePipelineTab {
  review,
  assign,
  ongoing,
  treatment,
  intake;

  String get label => switch (this) {
        RescuePipelineTab.review => 'Review',
        RescuePipelineTab.assign => 'Assign',
        RescuePipelineTab.ongoing => 'Ongoing',
        RescuePipelineTab.treatment => 'In Treatment',
        RescuePipelineTab.intake => 'Intake',
      };

  List<RescueStatus> get statuses => switch (this) {
        RescuePipelineTab.review => [RescueStatus.pendingReview],
        RescuePipelineTab.assign => [RescueStatus.awaitingAssignment],
        RescuePipelineTab.ongoing => [RescueStatus.ongoing],
        RescuePipelineTab.treatment => [RescueStatus.treatment],
        RescuePipelineTab.intake => [RescueStatus.intake],
      };
}

/// Extra statuses reachable only through the status filter (not one of the
/// five pipeline tabs above) — referral/duplicate/terminal states.
const List<RescueStatus> kSecondaryStatuses = [
  RescueStatus.referred,
  RescueStatus.possibleDuplicate,
  RescueStatus.merged,
  RescueStatus.rejected,
  RescueStatus.completed,
  RescueStatus.cancelled,
];

class RescueFilters {
  final String searchText;
  final UrgencyLevel? urgency;
  final String? species;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? locationQuery;

  /// When set, overrides the active pipeline tab's status list — lets the
  /// filter bar reach referred/possibleDuplicate/merged/rejected/completed/
  /// cancelled cases that the five quick tabs don't cover.
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
    if (species != null &&
        species!.isNotEmpty &&
        (c.animalType == null || c.animalType!.toLowerCase() != species!.toLowerCase())) {
      return false;
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
        c.animalType,
        c.condition,
        c.address,
        c.reporterName,
        c.id,
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
final filteredCasesProvider = Provider<AsyncValue<List<RescueCase>>>((ref) {
  final statuses = ref.watch(effectiveStatusesProvider);
  final casesAsync = ref.watch(casesByStatusesProvider(statuses));
  final filters = ref.watch(rescueFilterProvider);
  return casesAsync.whenData((cases) => cases.where(filters.matches).toList());
});
