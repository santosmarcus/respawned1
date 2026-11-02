import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/services/adoption_fit_assessment_service.dart';
import 'package:respawnd1/core/utils/adoption_lifecycle.dart';
import 'package:respawnd1/features/admin/adoption/post_adoption_details_page.dart';
import 'package:respawnd1/features/adoption/interview_scheduling.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_detail_page.dart';
import 'package:respawnd1/features/admin/adoption/return_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

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
  complete,
  returns_,
  rejected,
  withdrawn;

  String get label => switch (this) {
        _PageTab.pending => 'Pending',
        _PageTab.interview => 'Interview',
        // Label only — the underlying AdoptionStatus.approved value/query is
        // unchanged (see queryStatus below); applications in this tab are
        // approved and awaiting release/handover, which "Release" names
        // more accurately than "Approved" did.
        _PageTab.approved => 'Release',
        _PageTab.adopted => 'Adopted',
        _PageTab.complete => 'Complete',
        _PageTab.returns_ => 'Returns',
        _PageTab.rejected => 'Rejected',
        _PageTab.withdrawn => 'Withdrawn',
      };

  IconData get icon => switch (this) {
        _PageTab.pending => Icons.pending_actions_outlined,
        _PageTab.interview => Icons.calendar_month_outlined,
        _PageTab.approved => Icons.check_circle_outline,
        _PageTab.adopted => Icons.home_outlined,
        _PageTab.complete => Icons.task_alt_outlined,
        _PageTab.returns_ => Icons.assignment_return_outlined,
        _PageTab.rejected => Icons.cancel_outlined,
        _PageTab.withdrawn => Icons.logout_outlined,
      };

  String get emptyMessage => switch (this) {
        _PageTab.pending => 'No pending applications',
        _PageTab.interview => 'No scheduled interviews',
        _PageTab.approved => 'No applications awaiting release',
        _PageTab.adopted => 'No adoptions in active monitoring',
        _PageTab.complete => 'No completed post-adoption monitoring yet',
        _PageTab.returns_ => 'No return requests',
        _PageTab.rejected => 'No rejected applications',
        _PageTab.withdrawn => 'No withdrawn applications',
      };

  // Adopted, Complete and Returns all draw from the same AdoptionStatus.
  // adopted query bucket (see the class doc comment) and are split
  // client-side by classifyAdoptionLifecycle/isReturnActive — never a
  // separate Firestore query per tab.
  AdoptionStatus get queryStatus => switch (this) {
        _PageTab.pending => AdoptionStatus.pending,
        _PageTab.interview => AdoptionStatus.interview,
        _PageTab.approved => AdoptionStatus.approved,
        _PageTab.adopted => AdoptionStatus.adopted,
        _PageTab.complete => AdoptionStatus.adopted,
        _PageTab.returns_ => AdoptionStatus.adopted,
        _PageTab.rejected => AdoptionStatus.rejected,
        _PageTab.withdrawn => AdoptionStatus.withdrawn,
      };

  static _PageTab fromStatus(AdoptionStatus status) => values.firstWhere(
      (t) => t.queryStatus == status && t != _PageTab.returns_ && t != _PageTab.complete,
      orElse: () => _PageTab.pending);
}

enum _SortOption {
  newestSubmitted,
  oldestSubmitted,
  animalNameAsc,
  animalNameDesc,
  applicantNameAsc,
  applicantNameDesc,
  interviewSoonest,
  interviewLatest,
  recentlyUpdated,
}

extension on _SortOption {
  String get label => switch (this) {
        _SortOption.newestSubmitted => 'Newest Submitted',
        _SortOption.oldestSubmitted => 'Oldest Submitted',
        _SortOption.animalNameAsc => 'Animal Name A–Z',
        _SortOption.animalNameDesc => 'Animal Name Z–A',
        _SortOption.applicantNameAsc => 'Applicant Name A–Z',
        _SortOption.applicantNameDesc => 'Applicant Name Z–A',
        _SortOption.interviewSoonest => 'Interview Date Soonest',
        _SortOption.interviewLatest => 'Interview Date Latest',
        _SortOption.recentlyUpdated => 'Recently Updated',
      };
}

/// One practical, comprehensive filter set on top of the top-level status
/// tabs and free-text search — every field here already exists on
/// `AdoptionApplication`/the raw `adoptions/{id}` doc, nothing invented.
/// Filtering happens locally against the already-loaded per-tab list (the
/// same `adoptionsByStatusesProvider` family the tabs/badges/search already
/// share) — never a second Firestore query per filter change.
class _AdoptionFilters {
  final String? appointmentType; // exact value from kInterviewTypes, or null=any
  final String? reviewState; // 'notReviewed' | 'reviewed' | 'interviewCompleted' | 'noShow'
  final String? submissionBucket; // 'today' | 'last7' | 'last30' | 'custom'
  final DateTimeRange? submissionRange;
  final String? interviewBucket; // 'upcoming' | 'past' | 'notScheduled' | 'custom'
  final DateTimeRange? interviewRange;
  final bool? homePhotosProvided;
  final bool? documentsComplete;

  const _AdoptionFilters({
    this.appointmentType,
    this.reviewState,
    this.submissionBucket,
    this.submissionRange,
    this.interviewBucket,
    this.interviewRange,
    this.homePhotosProvided,
    this.documentsComplete,
  });

  int get activeCount => [
        appointmentType,
        reviewState,
        submissionBucket,
        interviewBucket,
        homePhotosProvided,
        documentsComplete,
      ].where((v) => v != null).length;

  bool _inRange(DateTime d, DateTimeRange r) =>
      !d.isBefore(DateTime(r.start.year, r.start.month, r.start.day)) &&
      d.isBefore(DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1)));

  bool _matchesDateBucket(DateTime? d, String bucket, DateTimeRange? customRange) {
    if (bucket == 'custom') return d != null && customRange != null && _inRange(d, customRange);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (bucket) {
      'today' => d.year == today.year && d.month == today.month && d.day == today.day,
      'last7' => !d.isBefore(today.subtract(const Duration(days: 7))),
      'last30' => !d.isBefore(today.subtract(const Duration(days: 30))),
      _ => true,
    };
  }

  bool matches(AdoptionApplication a) {
    if (appointmentType != null && a.appointmentType != appointmentType) return false;

    if (reviewState != null) {
      final ok = switch (reviewState!) {
        'notReviewed' => a.fitAssessment == FitAssessmentValue.notReviewed,
        'reviewed' => a.fitAssessment != FitAssessmentValue.notReviewed,
        'interviewCompleted' => a.interviewCompletedAt != null,
        'noShow' => a.noShowAt != null,
        _ => true,
      };
      if (!ok) return false;
    }

    if (submissionBucket != null && !_matchesDateBucket(a.createdAt, submissionBucket!, submissionRange)) return false;

    if (interviewBucket != null) {
      final ok = switch (interviewBucket!) {
        'notScheduled' => a.appointmentDate == null,
        'upcoming' => a.appointmentDate != null && !a.appointmentDate!.isBefore(DateTime.now()),
        'past' => a.appointmentDate != null && a.appointmentDate!.isBefore(DateTime.now()),
        'custom' => a.appointmentDate != null && interviewRange != null && _inRange(a.appointmentDate!, interviewRange!),
        _ => true,
      };
      if (!ok) return false;
    }

    if (homePhotosProvided != null) {
      final uploads = (a.raw['uploads'] as Map?) ?? const {};
      final has = _hasUpload(uploads['homePhotos']);
      if (has != homePhotosProvided) return false;
    }

    if (documentsComplete != null) {
      final uploads = (a.raw['uploads'] as Map?) ?? const {};
      final complete = _hasUpload(uploads['governmentId']) && _hasUpload(uploads['proofOfAddress']);
      if (complete != documentsComplete) return false;
    }

    return true;
  }

  static bool _hasUpload(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return false;
  }
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
  _SortOption _sort = _SortOption.newestSubmitted;
  _AdoptionFilters _filters = const _AdoptionFilters();
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

  // Latest of every admin-facing timestamp on the application — the closest
  // thing to an "updatedAt" field without adding a new write path just for
  // sorting. Falls back to createdAt (never null-unsafe).
  DateTime _lastActivity(AdoptionApplication a) {
    var latest = a.createdAt ?? DateTime(0);
    for (final d in [
      a.approvedAt,
      a.rejectedAt,
      a.withdrawnAt,
      a.adoptedAt,
      a.releasedAt,
      a.interviewCompletedAt,
      a.noShowAt,
      a.reservedAt,
      a.fitAssessedAt,
      a.postAdoptionCompletedAt,
    ]) {
      if (d != null && d.isAfter(latest)) latest = d;
    }
    return latest;
  }

  Future<void> _showSortFilterSheet(BuildContext context) async {
    var sort = _sort;
    var filters = _filters;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget sectionTitle(String label) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              );
          Widget choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
                label: Text(label),
                selected: selected,
                selectedColor: AppColors.yellowrspwn,
                onSelected: (_) => onTap(),
              );

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 12 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sort & Filter', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                      TextButton(
                        onPressed: () => setSheetState(() {
                          sort = _SortOption.newestSubmitted;
                          filters = const _AdoptionFilters();
                        }),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        sectionTitle('Sort by'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in _SortOption.values) choice(s.label, sort == s, () => setSheetState(() => sort = s)),
                          ],
                        ),
                        sectionTitle('Appointment type'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.appointmentType == null,
                              () => setSheetState(() => filters = _copy(filters, clearAppointmentType: true))),
                          for (final t in kInterviewTypes)
                            choice(t, filters.appointmentType == t,
                                () => setSheetState(() => filters = _copy(filters, appointmentType: t))),
                        ]),
                        sectionTitle('Review state'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.reviewState == null, () => setSheetState(() => filters = _copy(filters, clearReviewState: true))),
                          choice('Not reviewed', filters.reviewState == 'notReviewed',
                              () => setSheetState(() => filters = _copy(filters, reviewState: 'notReviewed'))),
                          choice('Reviewed', filters.reviewState == 'reviewed',
                              () => setSheetState(() => filters = _copy(filters, reviewState: 'reviewed'))),
                          choice('Interview completed', filters.reviewState == 'interviewCompleted',
                              () => setSheetState(() => filters = _copy(filters, reviewState: 'interviewCompleted'))),
                          choice('No-show', filters.reviewState == 'noShow',
                              () => setSheetState(() => filters = _copy(filters, reviewState: 'noShow'))),
                        ]),
                        sectionTitle('Submission date'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.submissionBucket == null,
                              () => setSheetState(() => filters = _copy(filters, clearSubmissionBucket: true))),
                          choice('Today', filters.submissionBucket == 'today',
                              () => setSheetState(() => filters = _copy(filters, submissionBucket: 'today'))),
                          choice('Last 7 days', filters.submissionBucket == 'last7',
                              () => setSheetState(() => filters = _copy(filters, submissionBucket: 'last7'))),
                          choice('Last 30 days', filters.submissionBucket == 'last30',
                              () => setSheetState(() => filters = _copy(filters, submissionBucket: 'last30'))),
                          choice('Custom range', filters.submissionBucket == 'custom', () async {
                            final range = await showDateRangePicker(
                                context: context, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 1)));
                            if (range != null) setSheetState(() => filters = _copy(filters, submissionBucket: 'custom', submissionRange: range));
                          }),
                        ]),
                        sectionTitle('Interview date'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.interviewBucket == null,
                              () => setSheetState(() => filters = _copy(filters, clearInterviewBucket: true))),
                          choice('Upcoming', filters.interviewBucket == 'upcoming',
                              () => setSheetState(() => filters = _copy(filters, interviewBucket: 'upcoming'))),
                          choice('Past', filters.interviewBucket == 'past',
                              () => setSheetState(() => filters = _copy(filters, interviewBucket: 'past'))),
                          choice('No interview scheduled', filters.interviewBucket == 'notScheduled',
                              () => setSheetState(() => filters = _copy(filters, interviewBucket: 'notScheduled'))),
                          choice('Custom range', filters.interviewBucket == 'custom', () async {
                            final range = await showDateRangePicker(
                                context: context, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (range != null) setSheetState(() => filters = _copy(filters, interviewBucket: 'custom', interviewRange: range));
                          }),
                        ]),
                        sectionTitle('Home photos'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.homePhotosProvided == null,
                              () => setSheetState(() => filters = _copy(filters, clearHomePhotos: true))),
                          choice('Provided', filters.homePhotosProvided == true,
                              () => setSheetState(() => filters = _copy(filters, homePhotosProvided: true))),
                          choice('Not provided', filters.homePhotosProvided == false,
                              () => setSheetState(() => filters = _copy(filters, homePhotosProvided: false))),
                        ]),
                        sectionTitle('Required documents'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          choice('Any', filters.documentsComplete == null,
                              () => setSheetState(() => filters = _copy(filters, clearDocumentsComplete: true))),
                          choice('Complete', filters.documentsComplete == true,
                              () => setSheetState(() => filters = _copy(filters, documentsComplete: true))),
                          choice('Incomplete', filters.documentsComplete == false,
                              () => setSheetState(() => filters = _copy(filters, documentsComplete: false))),
                        ]),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _sort = sort;
                          _filters = filters;
                        });
                        Navigator.pop(sheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text('Apply', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Immutable _AdoptionFilters has no generated copyWith (its null fields
  // are meaningful "any" values, not "unset") — this local helper lets the
  // sheet clear one field at a time without touching the others.
  _AdoptionFilters _copy(
    _AdoptionFilters f, {
    String? appointmentType,
    bool clearAppointmentType = false,
    String? reviewState,
    bool clearReviewState = false,
    String? submissionBucket,
    DateTimeRange? submissionRange,
    bool clearSubmissionBucket = false,
    String? interviewBucket,
    DateTimeRange? interviewRange,
    bool clearInterviewBucket = false,
    bool? homePhotosProvided,
    bool clearHomePhotos = false,
    bool? documentsComplete,
    bool clearDocumentsComplete = false,
  }) =>
      _AdoptionFilters(
        appointmentType: clearAppointmentType ? null : (appointmentType ?? f.appointmentType),
        reviewState: clearReviewState ? null : (reviewState ?? f.reviewState),
        submissionBucket: clearSubmissionBucket ? null : (submissionBucket ?? f.submissionBucket),
        submissionRange: clearSubmissionBucket ? null : (submissionRange ?? f.submissionRange),
        interviewBucket: clearInterviewBucket ? null : (interviewBucket ?? f.interviewBucket),
        interviewRange: clearInterviewBucket ? null : (interviewRange ?? f.interviewRange),
        homePhotosProvided: clearHomePhotos ? null : (homePhotosProvided ?? f.homePhotosProvided),
        documentsComplete: clearDocumentsComplete ? null : (documentsComplete ?? f.documentsComplete),
      );

  List<AdoptionApplication> _sorted(List<AdoptionApplication> apps) {
    final list = [...apps];
    switch (_sort) {
      case _SortOption.newestSubmitted:
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        break;
      case _SortOption.oldestSubmitted:
        list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        break;
      case _SortOption.animalNameAsc:
        list.sort((a, b) => a.animalName.toLowerCase().compareTo(b.animalName.toLowerCase()));
        break;
      case _SortOption.animalNameDesc:
        list.sort((a, b) => b.animalName.toLowerCase().compareTo(a.animalName.toLowerCase()));
        break;
      case _SortOption.applicantNameAsc:
        list.sort((a, b) => a.adopterName.toLowerCase().compareTo(b.adopterName.toLowerCase()));
        break;
      case _SortOption.applicantNameDesc:
        list.sort((a, b) => b.adopterName.toLowerCase().compareTo(a.adopterName.toLowerCase()));
        break;
      case _SortOption.interviewSoonest:
        list.sort((a, b) => (a.appointmentDate ?? DateTime(9999)).compareTo(b.appointmentDate ?? DateTime(9999)));
        break;
      case _SortOption.interviewLatest:
        list.sort((a, b) => (b.appointmentDate ?? DateTime(0)).compareTo(a.appointmentDate ?? DateTime(0)));
        break;
      case _SortOption.recentlyUpdated:
        list.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
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
    // Adopted/Complete/Returns all reuse the same AdoptionStatus.adopted
    // query bucket, narrowed client-side via the centralized
    // classifyAdoptionLifecycle helper (Adoption Tab Classification spec)
    // so every tab's membership agrees with its badge count and with the
    // priority order (active return > fully-complete monitoring > plain
    // adopted). A resolved return (declined/cancelled/intake) no longer
    // pins an application in Returns forever — it falls back to
    // Adopted/Complete like any other application once resolved.
    final apps = switch (_tab) {
      _PageTab.returns_ => statusApps.where((a) => isReturnActive(a.returnRequest)).toList(),
      _PageTab.adopted =>
        statusApps.where((a) => classifyAdoptionLifecycle(a) == AdoptionLifecycleStage.adopted).toList(),
      _PageTab.complete =>
        statusApps.where((a) => classifyAdoptionLifecycle(a) == AdoptionLifecycleStage.complete).toList(),
      _ => statusApps,
    };
    List<AdoptionApplication> filtered;
    if (_animalRecordIdFilter != null) {
      filtered = apps.where((a) => a.animalRecordId == _animalRecordIdFilter).toList();
    } else if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      filtered = apps.where((a) => a.animalName.toLowerCase().contains(q) || a.adopterName.toLowerCase().contains(q)).toList();
    } else {
      filtered = apps;
    }
    // Sheet filters stack on top of search/tab — same already-resolved
    // list, never a second query.
    filtered = filtered.where(_filters.matches).toList();
    final sorted = _sorted(filtered);

    // Opened two ways: as the root "Adoptions" module from the drawer (no
    // animalId), or as the "View Applications" drill-down from an Animal
    // Record (animalId set) — only the root case gets the shared burger
    // menu; the drill-down keeps back navigation to the record it came
    // from, same as every other detail/child screen.
    final isRootModule = widget.animalId == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: isRootModule ? const AdminDrawer(active: AdminModule.adoptions) : null,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: isRootModule
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: AppColors.background),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.background),
                onPressed: () => Navigator.pop(context),
              ),
        // Page title restored to the top header (spec) — same typography/
        // placement as Volunteers/Collar Tags. Only shown at the root
        // module entry (matches the drill-down back-arrow condition above
        // — a pushed-in Adoptions view opened from an Animal Record keeps
        // its own context, not a repeated "Adoptions" banner). The body's
        // own smaller title is removed below so it's never shown twice.
        title: isRootModule
            ? Text('Adoptions', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background))
            : null,
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

          // Workflow tabs — icon + count badge + label, matching Rescue
          // Reports' pipeline-tab visual pattern rather than text-only pills.
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              // Extra top padding — not just horizontal — so the badge's
              // negative top offset below has room to render instead of
              // being sliced off by the ListView's own viewport edge.
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              itemCount: _PageTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final t = _PageTab.values[index];
                final selected = _tab == t;
                final tabAppsAsync = ref.watch(adoptionsByStatusesProvider(statusFilter(t.queryStatus)));
                final tabApps = tabAppsAsync.asData?.value ?? const <AdoptionApplication>[];
                final badgeCount = switch (t) {
                  _PageTab.returns_ => tabApps.where((a) => isReturnActive(a.returnRequest)).length,
                  _PageTab.adopted =>
                    tabApps.where((a) => classifyAdoptionLifecycle(a) == AdoptionLifecycleStage.adopted).length,
                  _PageTab.complete =>
                    tabApps.where((a) => classifyAdoptionLifecycle(a) == AdoptionLifecycleStage.complete).length,
                  _ => tabApps.length,
                };
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
                              // Grows horizontally for 2-/3-digit counts
                              // instead of a fixed 18x18 box that would
                              // squeeze "100" unreadable.
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                child: Center(
                                  child: Text('$badgeCount',
                                      textAlign: TextAlign.center,
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
                  onTap: () => _showSortFilterSheet(context),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _filters.activeCount > 0 ? AppColors.yellowrspwn : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.slaterspwn),
                        ),
                        child: const Icon(Icons.tune, size: 20, color: AppColors.textPrimary),
                      ),
                      if (_filters.activeCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFFE05C5C), shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              '${_filters.activeCount}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            // Pull to Refresh spec §13 — same manual re-subscribe the
            // existing "Retry" button already performs on error, now also
            // reachable via a pull gesture; never a second/duplicate
            // listener.
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(adoptionsByStatusesProvider(statusFilter(_tab.queryStatus))),
              child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                Padding(
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
                ],
              ),
              data: (_) {
                // `sorted` already reflects the search/animalRecordId
                // filter computed above — the exact same list this
                // branch's item count is built from, never a second,
                // independently-filtered value.
                if (sorted.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: Text(_tab.emptyMessage, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                        ),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  // Navigation State spec §11 — keyed per tab so each keeps
                  // its own scroll offset.
                  key: PageStorageKey('adoption_review_list_${_tab.name}'),
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => switch (_tab) {
                    _PageTab.returns_ => _ReturnCard(application: sorted[i]),
                    // Navigation spec (§5/§6) — Adopted/Complete cards route
                    // straight to Post-Adoption; the old application-review
                    // page is only a secondary "View Application" action.
                    _PageTab.adopted => _AdoptedCard(application: sorted[i]),
                    _PageTab.complete => _CompleteCard(application: sorted[i]),
                    _ => _ApplicationCard(application: sorted[i]),
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
    // Compact, neutral-styled chip from the computed Fit Assessment —
    // separate from the manual admin-decision chip below (application.
    // fitAssessment), never colored like an approve/reject status, and
    // always the same shared calculateFitAssessment() the detail page
    // uses — never a second/different score for the same application.
    final computedAssessment = animal == null ? null : calculateFitAssessment(application: application, animal: animal);
    final computedLabel = (computedAssessment == null || computedAssessment.insufficientData)
        ? 'Not assessed'
        : '${computedAssessment.score} · ${computedAssessment.band.label}';

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
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.tearspwn.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.insights_outlined, size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text('Fit: $computedLabel',
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The manual admin-decision chip (Good Candidate / Needs
                  // Review / Not Recommended / Not Reviewed) used to sit
                  // here too — removed from the card entirely (most cards
                  // just showed "Not Reviewed" clutter); that value is
                  // still visible/settable on Adoption Details and
                  // filterable via Sort & Filter's "Review state" section,
                  // never deleted from the data.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(application.status), borderRadius: BorderRadius.circular(20)),
                      child: Text(application.status.label,
                          style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}

String _dateLabel(DateTime? d) => d == null ? '-' : '${d.month}/${d.day}/${d.year}';

/// Shared animal-photo lookup used by [_AdoptedCard]/[_CompleteCard] — same
/// Animal Record image [_ApplicationCard]/[_ReturnCard] already use, never
/// an application document or follow-up-submission photo (spec §5).
({String? photoUrl, String animalName}) _animalDisplay(WidgetRef ref, AdoptionApplication application) {
  final animalRecordId = application.animalRecordId;
  final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
  final photoUrl = animal?.photoUrls.isNotEmpty == true ? animal!.photoUrls.first : null;
  return (photoUrl: photoUrl, animalName: application.animalName.isNotEmpty ? application.animalName : 'Unknown animal');
}

Widget _monitoringCardPlaceholder() => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.pets, color: AppColors.textSecondary),
    );

/// "View Application" secondary action — every monitoring card's primary
/// tap goes to Post-Adoption (spec §5/§6); this is the only way back to the
/// original application-review page from these two tabs.
class _ViewApplicationLink extends StatelessWidget {
  final String applicationId;
  const _ViewApplicationLink({required this.applicationId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => AdoptionApplicationDetailPage(applicationId: applicationId))),
      child: Text('View Application',
          style: GoogleFonts.zain(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary, decoration: TextDecoration.underline)),
    );
  }
}

/// Adopted tab card (Adoption Tab Classification spec §5) — release/
/// handover completed, monitoring in progress. Primary tap opens
/// Post-Adoption Monitoring directly; "View Application" is a secondary
/// action only.
class _AdoptedCard extends ConsumerWidget {
  final AdoptionApplication application;
  const _AdoptedCard({required this.application});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = _animalDisplay(ref, application);
    final followUps = ref.watch(followUpsForAdoptionProvider(application.id)).asData?.value ?? const <FollowUpRecord>[];
    final completedCount = followUps.where((f) => f.isTerminal).length;
    final pending = followUps.where((f) => !f.isTerminal).toList()..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final next = pending.isNotEmpty ? pending.first : null;
    final overdue = next != null && next.scheduledDate.isBefore(DateTime.now());
    final returnActive = isReturnActive(application.returnRequest);
    final releaseDate = application.releasedAt ?? application.adoptedAt;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostAdoptionDetailsPage(applicationId: application.id))),
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
              child: display.photoUrl != null
                  ? Image.network(display.photoUrl!, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _monitoringCardPlaceholder())
                  : _monitoringCardPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display.animalName,
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Adopter: ${application.adopterName} · Adopted ${_dateLabel(releaseDate)}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    followUps.isEmpty ? 'No follow-ups scheduled' : 'Follow-ups: $completedCount of ${followUps.length} complete',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                  ),
                  if (next != null)
                    Text('Next follow-up: ${_dateLabel(next.scheduledDate)}${overdue ? ' · Overdue' : ''}',
                        style: GoogleFonts.zain(
                            fontSize: 11, fontWeight: overdue ? FontWeight.w700 : FontWeight.normal, color: overdue ? const Color(0xFFE05353) : AppColors.textSecondary)),
                  if (returnActive) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFE05353).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                      child: Text('Return in progress',
                          style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFE05353))),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Primary action label (spec: Adopted card's primary
                      // action must read "View Post-Adoption", not just an
                      // implicit whole-card tap) — the whole card already
                      // opens PostAdoptionDetailsPage on tap; this makes
                      // that explicit rather than relying on affordance
                      // alone. "View Application" stays secondary-only.
                      Text('View Post-Adoption →',
                          style: GoogleFonts.zain(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, decoration: TextDecoration.underline)),
                      _ViewApplicationLink(applicationId: application.id),
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
}

/// Complete tab card (Adoption Tab Classification spec §6) — historical,
/// read-only post-adoption record. Primary tap opens the same Post-Adoption
/// screen, which renders its own completed/read-only state once
/// postAdoptionStatus == 'completed' — never a second, separate screen.
class _CompleteCard extends ConsumerWidget {
  final AdoptionApplication application;
  const _CompleteCard({required this.application});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = _animalDisplay(ref, application);
    final followUps = ref.watch(followUpsForAdoptionProvider(application.id)).asData?.value ?? const <FollowUpRecord>[];
    final completedCount = followUps.where((f) => f.isTerminal).length;
    final releaseDate = application.releasedAt ?? application.adoptedAt;
    final returnRequest = application.returnRequest;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostAdoptionDetailsPage(applicationId: application.id))),
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
              child: display.photoUrl != null
                  ? Image.network(display.photoUrl!, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _monitoringCardPlaceholder())
                  : _monitoringCardPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display.animalName,
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Adopter: ${application.adopterName} · Adopted ${_dateLabel(releaseDate)}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Monitoring completed ${_dateLabel(application.postAdoptionCompletedAt)}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                  Text('$completedCount follow-up${completedCount == 1 ? '' : 's'} completed',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if (returnRequest != null)
                    Text('Return history: ${returnRequest.status.label}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Text('Complete', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.greenrspwn)),
                      ),
                      const SizedBox(width: 10),
                      _ViewApplicationLink(applicationId: application.id),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
