import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_detail_page.dart';
import 'package:respawnd1/features/admin/adoption/return_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

String _friendlyAdoptionsError(Object err) {
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
  return 'Could not load applications.';
}

/// The page's own tab set — distinct from [AdoptionStatus] because Returns
/// isn't a real top-level status: a return can only start from an adopted
/// application, and the top-level `status` field never leaves 'adopted'
/// during one (only the nested `returnRequest.status` changes — see
/// AdoptionApplicationRepository's class doc comment). Returns therefore
/// queries the same Adopted bucket and is filtered client-side to
/// applications that actually have a returnRequest, rather than being a
/// seventh AdoptionStatus enum value (which is switched over exhaustively
/// in many other places — reserve/release/detail-page logic — that have
/// nothing to do with returns).
enum _PageTab {
  pending,
  interview,
  approved,
  adopted,
  returns_,
  rejected,
  withdrawn;

  String get label => switch (this) {
        _PageTab.pending => 'Pending',
        _PageTab.interview => 'Interview',
        _PageTab.approved => 'Approved',
        _PageTab.adopted => 'Adopted',
        _PageTab.returns_ => 'Returns',
        _PageTab.rejected => 'Rejected',
        _PageTab.withdrawn => 'Withdrawn',
      };

  IconData get icon => switch (this) {
        _PageTab.pending => Icons.pending_actions_outlined,
        _PageTab.interview => Icons.calendar_month_outlined,
        _PageTab.approved => Icons.check_circle_outline,
        _PageTab.adopted => Icons.home_outlined,
        _PageTab.returns_ => Icons.assignment_return_outlined,
        _PageTab.rejected => Icons.cancel_outlined,
        _PageTab.withdrawn => Icons.logout_outlined,
      };

  String get emptyMessage => switch (this) {
        _PageTab.pending => 'No pending applications',
        _PageTab.interview => 'No scheduled interviews',
        _PageTab.approved => 'No approved applications',
        _PageTab.adopted => 'No completed adoptions',
        _PageTab.returns_ => 'No return requests',
        _PageTab.rejected => 'No rejected applications',
        _PageTab.withdrawn => 'No withdrawn applications',
      };

  AdoptionStatus get queryStatus => switch (this) {
        _PageTab.pending => AdoptionStatus.pending,
        _PageTab.interview => AdoptionStatus.interview,
        _PageTab.approved => AdoptionStatus.approved,
        _PageTab.adopted => AdoptionStatus.adopted,
        _PageTab.returns_ => AdoptionStatus.adopted,
        _PageTab.rejected => AdoptionStatus.rejected,
        _PageTab.withdrawn => AdoptionStatus.withdrawn,
      };

  static _PageTab fromStatus(AdoptionStatus status) =>
      values.firstWhere((t) => t.queryStatus == status && t != _PageTab.returns_, orElse: () => _PageTab.pending);
}

enum _SortOption { recent, oldest, applicantName, animalName, interviewDate, status, fitAssessment }

extension on _SortOption {
  String get label => switch (this) {
        _SortOption.recent => 'Recently Submitted',
        _SortOption.oldest => 'Oldest Submitted',
        _SortOption.applicantName => 'Applicant Name',
        _SortOption.animalName => 'Animal Name',
        _SortOption.interviewDate => 'Interview Date',
        _SortOption.status => 'Application Status',
        _SortOption.fitAssessment => 'Fit Assessment',
      };
}

/// Application Review — six phases (see AdoptionStatus): Pending, Interview,
/// Approved, Adopted as one horizontally scrollable tab row, Rejected and
/// Withdrawn kept distinguishable as their own tabs too (not merged) so an
/// admin can always tell which closed applications ended which way.
///
/// This is the ONE Adoption Applications page — AnimalProfileTab's "View
/// Applications" opens this exact page (never a separate custom-filtered
/// screen) with [animalId] (the animal's real, stable `animals/{id}` doc
/// id — see AdoptionApplication's own doc comment on why that, not a name
/// or the legacy animalId hash, is the safe join key) and [animalName]
/// (display text only) pre-filling the normal search bar.
class AdoptionApplicationReviewPage extends ConsumerStatefulWidget {
  final String? animalId;
  final String? animalName;
  final AdoptionStatus initialStatus;
  const AdoptionApplicationReviewPage({super.key, this.animalId, this.animalName, this.initialStatus = AdoptionStatus.pending});

  @override
  ConsumerState<AdoptionApplicationReviewPage> createState() => _AdoptionApplicationReviewPageState();
}

class _AdoptionApplicationReviewPageState extends ConsumerState<AdoptionApplicationReviewPage> {
  late _PageTab _tab = _PageTab.fromStatus(widget.initialStatus);
  _SortOption _sort = _SortOption.recent;
  // Set only when arriving via "View Applications" and not yet edited —
  // filters by the real, stable animal doc id rather than by the
  // (possibly duplicated) name shown in the search box. Cleared the moment
  // the admin edits the search text, at which point it becomes a normal
  // free-text search instead.
  String? _animalRecordIdFilter;
  late final _searchController = TextEditingController(text: widget.animalName ?? '');
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _animalRecordIdFilter = widget.animalId;
    _searchText = _searchController.text.trim();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    setState(() {
      _animalRecordIdFilter = null;
      _searchText = v.trim();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _animalRecordIdFilter = null;
      _searchText = '';
    });
  }

  Future<void> _showSortSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Sort by', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 8),
              for (final s in _SortOption.values)
                RadioListTile<_SortOption>(
                  value: s,
                  groupValue: _sort,
                  activeColor: AppColors.greenrspwn,
                  title: Text(s.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  onChanged: (v) {
                    setState(() => _sort = v ?? _sort);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<AdoptionApplication> _sorted(List<AdoptionApplication> apps) {
    final list = [...apps];
    switch (_sort) {
      case _SortOption.recent:
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        break;
      case _SortOption.oldest:
        list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        break;
      case _SortOption.applicantName:
        list.sort((a, b) => a.adopterName.toLowerCase().compareTo(b.adopterName.toLowerCase()));
        break;
      case _SortOption.animalName:
        list.sort((a, b) => a.animalName.toLowerCase().compareTo(b.animalName.toLowerCase()));
        break;
      case _SortOption.interviewDate:
        list.sort((a, b) => (b.appointmentDate ?? DateTime(0)).compareTo(a.appointmentDate ?? DateTime(0)));
        break;
      case _SortOption.status:
        list.sort((a, b) => a.status.label.compareTo(b.status.label));
        break;
      case _SortOption.fitAssessment:
        list.sort((a, b) => a.fitAssessment.label.compareTo(b.fitAssessment.label));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(adoptionsByStatusesProvider(statusFilter(_tab.queryStatus)));
    // Same resolved value backs the list body's .when() branches below —
    // never a second, independently-derived count. Filtering by search
    // text (or, initially, by the stable animalRecordId from "View
    // Applications") happens locally against this already-resolved list —
    // never a second Firestore query per keystroke.
    final statusApps = appsAsync.asData?.value ?? const <AdoptionApplication>[];
    // Returns reuses the Adopted query bucket, narrowed to only
    // applications that actually have an active return request.
    final apps = _tab == _PageTab.returns_ ? statusApps.where((a) => a.returnRequest != null).toList() : statusApps;
    final List<AdoptionApplication> filtered;
    if (_animalRecordIdFilter != null) {
      filtered = apps.where((a) => a.animalRecordId == _animalRecordIdFilter).toList();
    } else if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      filtered = apps.where((a) => a.animalName.toLowerCase().contains(q) || a.adopterName.toLowerCase().contains(q)).toList();
    } else {
      filtered = apps;
    }
    final sorted = _sorted(filtered);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      // Same structure/order as Rescue Reports: module heading inside the
      // content area, then workflow tabs, then a search + sort/filter row,
      // then the list — never a second oversized AppBar title.
      body: Column(
        children: [
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Adoptions', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),

          const SizedBox(height: 16),

          // Workflow tabs — icon + count badge + label, matching Rescue
          // Reports' pipeline-tab visual pattern rather than text-only pills.
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _PageTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final t = _PageTab.values[index];
                final selected = _tab == t;
                final tabAppsAsync = ref.watch(adoptionsByStatusesProvider(statusFilter(t.queryStatus)));
                final tabApps = tabAppsAsync.asData?.value ?? const <AdoptionApplication>[];
                final badgeCount =
                    t == _PageTab.returns_ ? tabApps.where((a) => a.returnRequest != null).length : tabApps.length;
                return GestureDetector(
                  onTap: () => setState(() => _tab = t),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.textPrimary : AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(t.icon, color: selected ? AppColors.background : AppColors.textSecondary, size: 22),
                          ),
                          if (badgeCount > 0)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                child: Center(
                                  child: Text('$badgeCount',
                                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.label,
                        style: GoogleFonts.zain(
                          fontSize: 11,
                          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Search + sort/filter, same row layout and tune-button pattern
          // as Rescue Reports (search box + tune icon beside it, opening a
          // bottom sheet) — never a separate AppBar sort menu.
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
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search animal or applicant name…',
                              hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: _clearSearch,
                            child: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _showSortSheet(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _sort == _SortOption.recent ? Colors.white : AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    child: const Icon(Icons.tune, size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 32, color: AppColors.textSecondary),
                      const SizedBox(height: 10),
                      Text(_friendlyAdoptionsError(e),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        // Manual re-subscribe of only this tab's family
                        // instance — never an automatic retry loop.
                        onPressed: () => ref.invalidate(adoptionsByStatusesProvider(statusFilter(_tab.queryStatus))),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (_) {
                // `sorted` already reflects the search/animalRecordId
                // filter computed above — the exact same list this
                // branch's item count is built from, never a second,
                // independently-filtered value.
                if (sorted.isEmpty) {
                  return Center(
                    child: Text(_tab.emptyMessage, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _tab == _PageTab.returns_
                      ? _ReturnCard(application: sorted[i])
                      : _ApplicationCard(application: sorted[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// The Returns tab's own card — animal name, adopter name, request date,
// return reason, and the return's own status (not the top-level adoption
// status chip _ApplicationCard shows), using the Animal Record's own image
// only, never an application document or return-evidence photo.
class _ReturnCard extends ConsumerWidget {
  final AdoptionApplication application;
  const _ReturnCard({required this.application});

  Color _returnStatusColor(ReturnRequestStatus s) => switch (s) {
        ReturnRequestStatus.pendingReview => AppColors.slaterspwn,
        ReturnRequestStatus.approved || ReturnRequestStatus.retrievalUnscheduled => AppColors.yellowrspwn,
        ReturnRequestStatus.retrievalScheduled => AppColors.lavenderrspwn,
        ReturnRequestStatus.retrieved || ReturnRequestStatus.intake => AppColors.greenrspwn,
        ReturnRequestStatus.declined || ReturnRequestStatus.cancelled => const Color(0xFFE05353),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = application.returnRequest;
    if (r == null) return const SizedBox.shrink();
    final animalRecordId = application.animalRecordId;
    final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
    final photoUrl = animal?.photoUrls.isNotEmpty == true ? animal!.photoUrls.first : null;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReturnDetailsPage(applicationId: application.id))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photoUrl != null
                  ? Image.network(photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _returnPlaceholder())
                  : _returnPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(application.animalName.isNotEmpty ? application.animalName : 'Unknown animal',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Adopter: ${application.adopterName}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (r.requestedAt != null)
                    Text('Requested ${r.requestedAt!.month}/${r.requestedAt!.day}/${r.requestedAt!.year}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  Text('Reason: ${r.reason.isEmpty ? 'Not provided' : r.reason}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _returnStatusColor(r.status), borderRadius: BorderRadius.circular(20)),
                      child: Text(r.status.label, style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _returnPlaceholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}

class _ApplicationCard extends ConsumerWidget {
  final AdoptionApplication application;
  const _ApplicationCard({required this.application});

  Color _statusColor(AdoptionStatus s) => switch (s) {
        AdoptionStatus.pending => AppColors.slaterspwn,
        AdoptionStatus.interview => AppColors.yellowrspwn,
        AdoptionStatus.approved => AppColors.greenrspwn,
        AdoptionStatus.adopted => AppColors.lavenderrspwn,
        AdoptionStatus.rejected => const Color(0xFFE05353),
        AdoptionStatus.withdrawn => AppColors.tearspwn,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // application.animalId is the legacy hash/catalog-int join key, never a
    // real animals/{id} doc id — looking it up here would never resolve.
    // animalRecordId (null on pre-fix applications) is the reliable one.
    final animalRecordId = application.animalRecordId;
    final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
    final photoUrl = animal?.photoUrls.isNotEmpty == true ? animal!.photoUrls.first : null;
    final dateStr = application.createdAt != null
        ? '${application.createdAt!.month}/${application.createdAt!.day}/${application.createdAt!.year}'
        : '-';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdoptionApplicationDetailPage(applicationId: application.id))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photoUrl != null
                  ? Image.network(photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animal name is the primary heading — the adopter name
                  // used to be here, with the animal name relegated to a
                  // subtitle; swapped so the card matches what an admin
                  // scanning the list actually looks for first.
                  Text(
                    application.animalName.isNotEmpty ? application.animalName : 'Unknown animal',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('Applicant: ${application.adopterName} · Submitted $dateStr',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if ((application.adopterCity ?? '').isNotEmpty)
                    Text(application.adopterCity!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if (application.appointmentDate != null)
                    Text(
                        'Interview: ${application.appointmentDate!.month}/${application.appointmentDate!.day}/${application.appointmentDate!.year}'
                        '${application.appointmentTime != null ? ' · ${application.appointmentTime}' : ''}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: application.fitAssessment == FitAssessmentValue.notReviewed
                              ? AppColors.slaterspwn
                              : AppColors.yellowrspwn,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(application.fitAssessment.label,
                            style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _statusColor(application.status), borderRadius: BorderRadius.circular(20)),
                        child: Text(application.status.label,
                            style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}
