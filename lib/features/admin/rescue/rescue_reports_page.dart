import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
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
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToDetail(BuildContext context, RescueCase c) {
    // The dedicated pipeline screens still take (caseId, Map<String,dynamic>
    // data) — `c.raw` is the full original document, so this stays a
    // drop-in for all of their existing logic.
    switch (c.status) {
      case RescueStatus.pendingReview:
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => RescueDetailPage(caseId: c.id, data: c.raw)));
        break;
      case RescueStatus.accepted:
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
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      // Centered module heading in the content area, same as Adoptions/
      // Animal Records — never a second title in the AppBar too.
      body: Column(
        children: [
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Rescue Reports',
                textAlign: TextAlign.center,
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),

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
                final badgeAsync = ref.watch(casesByStatusesProvider(tab.statuses));
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

          // Cases list
          Expanded(
            child: casesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
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
              ),
              data: (cases) {
                if (cases.isEmpty) {
                  return Center(
                    child: Text(
                      filters.isEmpty
                          ? 'No cases in this stage.'
                          : 'No cases match your filters.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cases.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final c = cases[index];
                    final canHavePendingOffer =
                        c.status == RescueStatus.accepted || c.status == RescueStatus.awaitingAssignment;
                    if (!canHavePendingOffer) {
                      return RescueCaseCard(
                        rescueCase: c,
                        showStatusChip: filters.statusOverride != null,
                        highlightBorder: c.status == RescueStatus.pendingReview,
                        onTap: () => _navigateToDetail(context, c),
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
        ],
      ),
    );
  }
}
