import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/rescue_case_card.dart';
import 'package:respawnd1/features/admin/rescue/widgets/rescue_filter_sheet.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';

String _friendlyCasesError(Object err) {
  if (err is FirebaseException && err.code == 'permission-denied') {
    // Deployed rules allow any authenticated user — a denial here means
    // this request isn't reaching Firestore as an authenticated user of
    // the right project (wrong Firebase config/project, or a server-side
    // enforcement like App Check rejecting it before rules even run), not
    // a role/account setup problem. See the debug log this repository
    // prints (projectId/uid) right before this query runs.
    return "This request wasn't accepted by Firestore. Check that the app "
        'is connected to the right Firebase project, then retry.';
  }
  return 'Could not load reports.';
}

class RescueReportsPage extends ConsumerStatefulWidget {
  const RescueReportsPage({super.key});

  @override
  ConsumerState<RescueReportsPage> createState() => _RescueReportsPageState();
}

class _RescueReportsPageState extends ConsumerState<RescueReportsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToDetail(BuildContext context, RescueCase c, {String? stageFilter}) {
    // A case reached via the Intake tab (spec §7) may still carry
    // `status: 'in_treatment'` if another animal on it is still active
    // there (see RescueCaseRepository's `_deriveCaseStatusOverride`) — the
    // admin tapped it from Intake, so it must open Intake Details for
    // exactly the animals in that stage, not fall through to Treatment
    // Details via the plain status switch below.
    if (stageFilter == 'intake' && c.animals.isNotEmpty) {
      final indexes = animalIndexesInStage(c, 'intake');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IntakeDetailPage(caseId: c.id, data: c.raw, animalIndexes: indexes.isEmpty ? null : indexes),
        ),
      );
      return;
    }
    // The dedicated pipeline screens still take (caseId, Map<String,dynamic>
    // data) — `c.raw` is the full original document, so this stays a
    // drop-in for all of their existing logic.
    switch (c.status) {
      case RescueStatus.pendingReview:
      case RescueStatus.accepted:
        // accepted means "accepted, no clinic saved yet" — stays on Rescue
        // Details, which renders its own Select Clinic action for this
        // status (see rescue_detail_page.dart).
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => RescueDetailPage(caseId: c.id, data: c.raw)));
        break;
      case RescueStatus.awaitingAssignment:
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)));
        break;
      case RescueStatus.ongoing:
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminTrackCasePage(caseId: c.id, data: c.raw)));
        break;
      case RescueStatus.treatment:
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => TreatmentDetailPage(caseId: c.id, data: c.raw)));
        break;
      case RescueStatus.intake:
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => IntakeDetailPage(caseId: c.id, data: c.raw)));
        break;
      default:
        // Rejected / referred / possibleDuplicate / merged / completed /
        // cancelled all land on the read-oriented detail page, which shows
        // referral/merge history instead of the accept/assign actions.
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => RescueDetailPage(caseId: c.id, data: c.raw)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = ref.watch(rescuePipelineTabProvider);
    final filters = ref.watch(rescueFilterProvider);
    final casesAsync = ref.watch(filteredCasesProvider);

    // Picking a tab (or re-tapping the current one) also drops a status
    // override set from the filter sheet, so the tab shows its own cases.
    void selectTab(int index) {
      ref.read(rescuePipelineTabProvider.notifier).select(RescuePipelineTab.values[index]);
      ref.read(rescueFilterProvider.notifier).setStatusOverride(null);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.rescue),
      appBar: AdminAppBar(
        title: 'Rescue Reports',
        bottom: AdminTabBar(
          tabs: [
            for (final tab in RescuePipelineTab.values)
              AdminTab(tab.label, count: ref.watch(casesForTabProvider(tab)).asData?.value.length ?? 0),
          ],
          selectedIndex: selectedTab.index,
          onSelected: selectTab,
        ),
      ),
      body: Column(
        children: [
          AdminSearchBar(
            controller: _searchController,
            hintText: 'Search species, reporter, case ID…',
            onChanged: (v) => ref.read(rescueFilterProvider.notifier).setSearchText(v),
            filterActive: !filters.isEmpty,
            onFilter: () => showRescueFilterSheet(
              context,
              current: filters,
              onApply: (next) {
                ref.read(rescueFilterProvider.notifier).replaceAll(next);
                _searchController.text = next.searchText;
              },
            ),
          ),

          if (filters.statusOverride != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text('Showing: ${filters.statusOverride!.label}',
                      style: GoogleFonts.zain(fontSize: 12)),
                  backgroundColor: AppColors.yellowrspwn,
                  onDeleted: () =>
                      ref.read(rescueFilterProvider.notifier).setStatusOverride(null),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Cases list — Pull to Refresh spec §13. These providers are
          // already live Firestore streams (they update on their own), so
          // "refresh" here means re-subscribing the current tab's listener
          // (the same manual invalidation the existing "Retry" button
          // already does on error) — never a second/duplicate listener.
          Expanded(
            child: AdminTabSwipe(
              index: selectedTab.index,
              count: RescuePipelineTab.values.length,
              onSelected: selectTab,
              child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(casesByStatusesProvider(ref.read(effectiveStatusesProvider))),
              child: casesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 32, color: AppColors.textSecondary),
                      const SizedBox(height: 10),
                      Text(
                        _friendlyCasesError(err),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        // Invalidates only this one tab's family instance — a
                        // deliberate manual re-subscribe, never an automatic
                        // retry loop.
                        onPressed: () => ref.invalidate(
                            casesByStatusesProvider(ref.read(effectiveStatusesProvider))),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                ],
              ),
              data: (cases) {
                if (cases.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: Text(
                          filters.isEmpty
                              ? 'No cases in this stage.'
                              : 'No cases match your filters.',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    ],
                  );
                }
                return ListView.separated(
                  // Navigation State spec §11 — keyed per tab/status-filter
                  // so each pipeline tab keeps its own scroll offset instead
                  // of sharing one position across differently-scoped lists.
                  key: PageStorageKey('rescue_reports_list_${filters.statusOverride?.name ?? selectedTab.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cases.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final c = cases[index];
                    // accepted (no clinic saved yet) can never have a
                    // transporter offer — offers only start from
                    // AssignRiderPage, reached once status is
                    // awaitingAssignment.
                    final canHavePendingOffer = c.status == RescueStatus.awaitingAssignment;
                    // Stage-filtered card display (spec §7) — only for the
                    // two tabs a case can appear under via
                    // activeAnimalStages while its own animals sit in
                    // different phases.
                    final stageFilter = filters.statusOverride == null
                        ? switch (selectedTab) {
                            RescuePipelineTab.treatment => 'in_treatment',
                            RescuePipelineTab.intake => 'intake',
                            _ => null,
                          }
                        : null;
                    if (c.status == RescueStatus.rejected) {
                      // Rejected-tab only: rejected-by comes from the
                      // per-case activityLogs subcollection, so this is the
                      // one card variant with its own listener (same
                      // reasoning as the Assign-tab's pending-offer watch
                      // below) — every other tab avoids it entirely.
                      return Consumer(
                        builder: (context, ref, _) {
                          final logs =
                              ref.watch(caseActivityLogsProvider(c.id)).asData?.value ?? const <ActivityLogEntry>[];
                          ActivityLogEntry? rejectionLog;
                          for (final l in logs) {
                            if (l.action != 'rejected') continue;
                            final current = rejectionLog;
                            final lTimestamp = l.timestamp;
                            final currentTimestamp = current?.timestamp;
                            if (current == null ||
                                (lTimestamp != null &&
                                    (currentTimestamp == null || lTimestamp.isAfter(currentTimestamp)))) {
                              rejectionLog = l;
                            }
                          }
                          final reason = c.rejectionReason;
                          final reasonLabel = reason == RejectionReason.other
                              ? (c.rejectionReasonOther?.trim().isNotEmpty ?? false
                                  ? c.rejectionReasonOther!
                                  : 'Other')
                              : (reason?.label ?? 'Not specified');
                          DateTime? rejectedDate;
                          for (final h in c.statusHistory) {
                            if (h.status.startsWith('Case rejected') && h.timestamp != null) {
                              rejectedDate = h.timestamp;
                            }
                          }
                          final eligible = isCommunityAdoptionEligible(
                            status: c.status.firestoreValue,
                            rejectionReason: reason?.name,
                            rescueType: c.raw['rescueType'] as String?,
                          );
                          return RescueCaseCard(
                            rescueCase: c,
                            showStatusChip: filters.statusOverride != null,
                            rejectionInfo: RejectionCardInfo(
                              reporterName: c.reporterName,
                              reasonLabel: reasonLabel,
                              rejectedDate: rejectedDate,
                              rejectedBy: rejectionLog?.actorName,
                              communityAdoptionEligible: eligible,
                            ),
                            onTap: () => _navigateToDetail(context, c),
                          );
                        },
                      );
                    }
                    if (c.status == RescueStatus.cancelled) {
                      // Closed-tab only — closureReason/closedAt/
                      // closedByName are written directly onto the case doc
                      // by RescueCaseRepository.closeCase, no extra
                      // subcollection lookup needed (unlike Rejected's
                      // rejected-by, which lives in activityLogs).
                      final closedAtRaw = c.raw['closedAt'];
                      final closedAt = closedAtRaw is Timestamp ? closedAtRaw.toDate() : null;
                      final reason = ClosureReason.fromName(c.raw['closureReason'] as String?);
                      return RescueCaseCard(
                        rescueCase: c,
                        showStatusChip: filters.statusOverride != null,
                        closureInfo: ClosureCardInfo(
                          reasonLabel: reason.label,
                          closedDate: closedAt,
                          closedBy: c.raw['closedByName'] as String?,
                        ),
                        onTap: () => _navigateToDetail(context, c),
                      );
                    }
                    if (!canHavePendingOffer) {
                      return RescueCaseCard(
                        rescueCase: c,
                        showStatusChip: filters.statusOverride != null,
                        highlightBorder: c.status == RescueStatus.pendingReview,
                        stageFilter: stageFilter,
                        onTap: () => _navigateToDetail(context, c, stageFilter: stageFilter),
                      );
                    }
                    // Assign-tab cases only: watch the current offer so the
                    // card never reads as completely unassigned while one
                    // is outstanding (spec §5). Scoped to this branch so
                    // every other tab avoids the extra per-card listener.
                    return Consumer(
                      builder: (context, ref, _) {
                        final assignment = ref.watch(currentAssignmentProvider(c.id)).asData?.value;
                        final pendingNote =
                            assignment != null && assignment.status == TransportAssignmentStatus.pending
                                ? 'Awaiting transporter response · Offered to: ${assignment.riderName}'
                                : null;
                        return RescueCaseCard(
                          rescueCase: c,
                          showStatusChip: filters.statusOverride != null,
                          pendingOfferNote: pendingNote,
                          onTap: () => _navigateToDetail(context, c),
                        );
                      },
                    );
                  },
                );
              },
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
