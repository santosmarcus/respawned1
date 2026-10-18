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
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

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

  static const _tabIcons = {
    RescuePipelineTab.review: Icons.rate_review_outlined,
    RescuePipelineTab.assign: Icons.assignment_ind_outlined,
    RescuePipelineTab.ongoing: Icons.local_shipping_outlined,
    RescuePipelineTab.treatment: Icons.medical_services_outlined,
    RescuePipelineTab.intake: Icons.pets_outlined,
    RescuePipelineTab.rejected: Icons.block_outlined,
    RescuePipelineTab.closed: Icons.folder_off_outlined,
  };

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

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.rescue),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        // Page title restored to the top header (spec) — same typography/
        // placement as Volunteers/Collar Tags (GoogleFonts.tiltWarp,
        // fontSize 18, background color). The body previously carried its
        // own smaller title here instead; that's removed below so the
        // title is never shown twice.
        title: Text('Rescue Reports', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),

          // Filter tabs
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              // Extra top padding so the badge's negative top offset below
              // has room to render instead of being sliced off by the
              // ListView's own viewport edge.
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              itemCount: RescuePipelineTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final tab = RescuePipelineTab.values[index];
                final isSelected = selectedTab == tab && filters.statusOverride == null;
                final badgeAsync = ref.watch(casesForTabProvider(tab));
                final badgeCount = badgeAsync.asData?.value.length ?? 0;

                return GestureDetector(
                  onTap: () {
                    ref.read(rescuePipelineTabProvider.notifier).select(tab);
                    ref.read(rescueFilterProvider.notifier).setStatusOverride(null);
                  },
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.textPrimary : AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _tabIcons[tab],
                              color: isSelected ? AppColors.background : AppColors.textSecondary,
                              size: 22,
                            ),
                          ),
                          if (badgeCount > 0)
                            Positioned(
                              top: -6,
                              right: -6,
                              // Grows horizontally for 2-/3-digit counts
                              // instead of a fixed 18x18 box that would
                              // squeeze "100" unreadable.
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$badgeCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tab.label,
                        style: GoogleFonts.zain(
                          fontSize: 11,
                          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Search + filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) =>
                                ref.read(rescueFilterProvider.notifier).setSearchText(v),
                            decoration: InputDecoration(
                              hintText: 'Search species, reporter, case ID…',
                              hintStyle: GoogleFonts.zain(
                                  fontSize: 13, color: AppColors.textSecondary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => showRescueFilterSheet(
                    context,
                    current: filters,
                    onApply: (next) {
                      ref.read(rescueFilterProvider.notifier).replaceAll(next);
                      _searchController.text = next.searchText;
                    },
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: filters.isEmpty ? Colors.white : AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    child: const Icon(Icons.tune, size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ],
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
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
        ],
      ),
    );
  }
}
