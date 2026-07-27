import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/utils/adoption_lifecycle.dart';
import 'package:respawnd1/core/utils/shelter_occupancy.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/volunteers/volunteers_page.dart';
import 'package:respawnd1/features/organization/organization_profile_edit_page.dart';

/// Action Required + Current Operations — replaces adminhome_screen.dart's
/// old hardcoded gauge/"Pending Requests" placeholder block with real,
/// live-computed sections (Dashboard Improvement spec). Every count here
/// reuses the SAME Riverpod providers Rescue Reports/Adoptions/Assign
/// Transporter already watch (casesForTabProvider, adoptionsByStatusesProvider,
/// activeAssignmentsByRiderProvider, allAnimalRecordsProvider) — Riverpod
/// shares one underlying Firestore listener per provider instance, so this
/// section never opens a second, duplicate query for data another open
/// admin screen is already streaming.
///
/// Deliberately does NOT include any alert that would require an invented
/// time threshold (e.g. "pending review beyond N hours") — see the
/// Dashboard Gap Analysis for the full list of what's classified
/// CONFIGURATION REQUIRED instead of fabricated here.

// ─── Shared row/card widgets ────────────────────────────────────────────

class _AlertRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AlertRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(subtitle, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _KpiCard({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value,
                style: GoogleFonts.tiltWarp(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// A responsive wrap-based KPI grid — avoids GridView's fixed-column
/// overflow risk on narrow phones/very long labels (spec §13/§18).
class _KpiWrap extends StatelessWidget {
  final List<Widget> cards;
  const _KpiWrap({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 700 ? 4 : (constraints.maxWidth >= 420 ? 3 : 2);
      final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final c in cards) SizedBox(width: cardWidth, child: c)],
      );
    });
  }
}

class _DashboardSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _DashboardSectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

Widget _loadingState() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );

// ─── Action Required ─────────────────────────────────────────────────────

/// One data point an alert is derived from, together with how to reach it
/// — kept as plain values (not built inline) so a failing provider only
/// removes its own row instead of taking the whole section down (spec §16
/// "one failed analytics query must not crash the entire dashboard").
class ActionRequiredSection extends ConsumerWidget {
  const ActionRequiredSection({super.key});

  void _openRescueReview(BuildContext context, WidgetRef ref) {
    ref.read(rescuePipelineTabProvider.notifier).select(RescuePipelineTab.review);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
  }

  void _openRescueAssign(BuildContext context, WidgetRef ref) {
    ref.read(rescuePipelineTabProvider.notifier).select(RescuePipelineTab.assign);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
  }

  void _openAdoptions(BuildContext context, AdoptionStatus status) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AdoptionApplicationReviewPage(initialStatus: status)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewCases = ref.watch(casesForTabProvider(RescuePipelineTab.review));
    final assignCases = ref.watch(casesForTabProvider(RescuePipelineTab.assign));
    final staleOffersAsync = ref.watch(staleTransportOffersProvider);
    final approvedAsync = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved)));
    final adoptedBucketAsync = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted)));
    final overdueFollowUpsAsync = ref.watch(overdueFollowUpsProvider);

    final rows = <Widget>[];

    // Dashboard-flicker fix — every branch below reads `.value`
    // rather than pattern-matching only on AsyncData via `.when(data: ...)`.
    // Riverpod's AsyncValue already keeps the LAST successfully-received
    // value accessible through `.value` even while a provider is
    // between emissions (a brief AsyncLoading during refresh) or has hit a
    // transient AsyncError — `.when()`'s `loading`/`error` callbacks simply
    // never see that carried-over value, so a bare `data: (v) => ...` with
    // empty `loading`/`error` branches was silently discarding perfectly
    // good cached data and rendering as if the count had dropped to zero.
    // Reading `.value` uniformly means: nothing shows before the
    // first real result ever arrives (matches `anyLoading` below), and
    // once a result has arrived it is never replaced by a blank/zero state
    // just because the provider is momentarily reloading or errored — only
    // a genuinely new emission with a different count changes what's shown.
    // An error banner only appears when there is no prior value at all to
    // fall back on.

    // Critical rescue reports awaiting review — no threshold, just
    // status==pendingReview/accepted (the Review tab's own definition)
    // filtered to urgency=='Critical'.
    final reviewList = reviewCases.value;
    if (reviewList != null) {
      final critical = reviewList.where((c) => c.urgency == 'Critical').length;
      if (critical > 0) {
        rows.add(_AlertRow(
          icon: Icons.priority_high,
          color: const Color(0xFFE05353),
          title: '$critical critical rescue report${critical == 1 ? '' : 's'} awaiting review',
          subtitle: 'Urgency: Critical · status: pending review',
          onTap: () => _openRescueReview(context, ref),
        ));
      }
      final acceptedNoClinic = reviewList.where((c) => c.status == RescueStatus.accepted).length;
      if (acceptedNoClinic > 0) {
        rows.add(_AlertRow(
          icon: Icons.local_hospital_outlined,
          color: const Color(0xFF9C6B10),
          title: '$acceptedNoClinic accepted case${acceptedNoClinic == 1 ? '' : 's'} without a clinic',
          subtitle: 'Accepted, no clinic selected yet',
          onTap: () => _openRescueReview(context, ref),
        ));
      }
    } else if (reviewCases.hasError) {
      rows.add(_AlertRow(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        title: 'Could not load Rescue Review data',
        subtitle: '${reviewCases.error}',
        onTap: () => _openRescueReview(context, ref),
      ));
    }

    final assignList = assignCases.value;
    if (assignList != null && assignList.isNotEmpty) {
      rows.add(_AlertRow(
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFF9C6B10),
        title: '${assignList.length} case${assignList.length == 1 ? '' : 's'} awaiting transporter assignment',
        subtitle: 'Clinic selected, no transporter offered yet',
        onTap: () => _openRescueAssign(context, ref),
      ));
    }

    final staleOffers = staleOffersAsync.value;
    if (staleOffers != null && staleOffers.isNotEmpty) {
      rows.add(_AlertRow(
        icon: Icons.hourglass_disabled_outlined,
        color: const Color(0xFFE05353),
        title: '${staleOffers.length} unanswered transporter offer${staleOffers.length == 1 ? '' : 's'} expired',
        subtitle: 'Pending offer passed its own response window',
        onTap: () => _openRescueAssign(context, ref),
      ));
    }

    final approvedApps = approvedAsync.value;
    if (approvedApps != null && approvedApps.isNotEmpty) {
      rows.add(_AlertRow(
        icon: Icons.home_outlined,
        color: AppColors.greenrspwn,
        title: '${approvedApps.length} approved application${approvedApps.length == 1 ? '' : 's'} awaiting release',
        subtitle: 'Approved, release/handover not completed yet',
        onTap: () => _openAdoptions(context, AdoptionStatus.approved),
      ));
    }

    final adoptedBucket = adoptedBucketAsync.value;
    if (adoptedBucket != null) {
      final activeReturns = adoptedBucket.where((a) => isReturnActive(a.returnRequest)).length;
      if (activeReturns > 0) {
        rows.add(_AlertRow(
          icon: Icons.assignment_return_outlined,
          color: const Color(0xFFE05353),
          title: '$activeReturns active return request${activeReturns == 1 ? '' : 's'}',
          subtitle: 'A return is in progress for an adopted animal',
          onTap: () => _openAdoptions(context, AdoptionStatus.adopted),
        ));
      }
    }

    final overdueFollowUps = overdueFollowUpsAsync.value;
    if (overdueFollowUps != null && overdueFollowUps.isNotEmpty) {
      rows.add(_AlertRow(
        icon: Icons.event_busy_outlined,
        color: const Color(0xFFE05353),
        title: '${overdueFollowUps.length} overdue post-adoption follow-up${overdueFollowUps.length == 1 ? '' : 's'}',
        subtitle: 'Past their own scheduled check-in date',
        onTap: () => _openAdoptions(context, AdoptionStatus.adopted),
      ));
    }

    // Loading is "before the first result ever" only — once any of these
    // providers has a value, `anyLoading` never fires again for it, even
    // during a later refresh.
    final anyLoading = [reviewCases, assignCases, staleOffersAsync, approvedAsync, adoptedBucketAsync, overdueFollowUpsAsync]
        .any((a) => !a.hasValue && a.isLoading);

    return _DashboardSectionCard(
      title: 'Action Required',
      child: rows.isEmpty
          ? (anyLoading ? _loadingState() : _emptyActionRequired())
          : Column(children: [for (int i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(height: 1), rows[i]]]),
    );
  }

  Widget _emptyActionRequired() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, size: 18, color: AppColors.greenrspwn),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Nothing needs attention right now.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ]),
      );
}

// Deliberately NOT .autoDispose (dashboard-flicker root cause, part 1):
// an autoDispose provider is torn down the moment its last widget listener
// unmounts, and rebuilt from scratch — a fresh Firestore listener — the
// next time something watches it. Both of these are watched from two
// sibling sections (ActionRequiredSection + CurrentOperationsSection) that
// are always mounted together on the dashboard, so autoDispose bought no
// real memory savings here, while making every "count reappears after
// having disappeared" report reproducible any time the dashboard is
// briefly left and returned to. A plain (never-disposed) StreamProvider
// keeps exactly one Firestore subscription alive for the app's session,
// so once a value has ever been shown, AsyncValue.value below never
// goes back to null.
final staleTransportOffersProvider = StreamProvider<List<TransportAssignment>>((ref) {
  return ref.watch(rescueCaseRepositoryProvider).streamStalePendingAssignments();
});

final overdueFollowUpsProvider = StreamProvider<List<FollowUpRecord>>((ref) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamOverdueFollowUps();
});

/// The shelter's configured maximum capacity — `settings/shelter.maxCapacity`
/// — the only real "configured maximum" field anywhere in the data model
/// (confirmed by inspection: no organization/animal-record field for this
/// exists). Null when unset; the Capacity card shows "Capacity not
/// configured" rather than inventing/hardcoding a maximum in that case.
final shelterMaxCapacityProvider = StreamProvider.autoDispose<int?>((ref) {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('shelter')
      .snapshots()
      .map((snap) => (snap.data()?['maxCapacity'] as num?)?.toInt());
});

// ─── Top compact metrics: Capacity / Active Rescues / Active Volunteers ──

/// A compact card for the top metrics row — deliberately smaller/denser
/// than the Current Operations KPI cards below it, matching the old
/// Capacity gauge's intent ("first thing under Action Required") without
/// reviving the fabricated gauge graphic itself.
class _CompactMetricCard extends StatelessWidget {
  final String title;
  final String primary;
  final String? secondary;
  final VoidCallback? onTap;

  const _CompactMetricCard({required this.title, required this.primary, this.secondary, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text(primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tiltWarp(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              if (secondary != null) ...[
                const SizedBox(height: 2),
                Text(secondary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shelter Capacity / Active Rescues / Active Volunteers — the three
/// compact top-level metrics requested right after Action Required.
class TopMetricsRow extends ConsumerWidget {
  const TopMetricsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Capacity — current occupancy traced from the real AnimalRecord
    // status/adoptionStatus/archived values via the shared
    // isCurrentlyHoused classifier (core/utils/shelter_occupancy.dart) —
    // the SAME classifier Organization Profile's over-capacity warning
    // uses, so the two can never disagree. Maximum comes from
    // shelterMaxCapacityProvider (settings/shelter.maxCapacity) — never
    // hardcoded, never used to compute a percentage when absent.
    final animalsAsync = ref.watch(allAnimalRecordsProvider);
    final currentOccupancy = animalsAsync.value?.where(isCurrentlyHoused).length;
    final maxCapacity = ref.watch(shelterMaxCapacityProvider).value;

    final review = ref.watch(casesForTabProvider(RescuePipelineTab.review));
    final assign = ref.watch(casesForTabProvider(RescuePipelineTab.assign));
    final ongoing = ref.watch(casesForTabProvider(RescuePipelineTab.ongoing));
    final treatment = ref.watch(casesForTabProvider(RescuePipelineTab.treatment));
    final intake = ref.watch(casesForTabProvider(RescuePipelineTab.intake));
    final activeTabs = [review, assign, ongoing, treatment, intake];
    final allLoaded = activeTabs.every((a) => a.hasValue);
    final activeCaseCount = allLoaded ? activeTabs.fold<int>(0, (sum, a) => sum + a.value!.length) : null;
    final activeAnimalCount =
        allLoaded ? activeTabs.fold<int>(0, (sum, a) => sum + a.value!.fold<int>(0, (s, c) => s + c.animalCount)) : null;

    // Active Volunteers — no distinct active/inactive account field exists
    // for rescue_volunteer users (confirmed by inspection); the only real
    // presence signal already used elsewhere (Volunteers page itself) is
    // PetTransporter.isOnline (online + seen within the last 5 minutes).
    // Reported honestly as "online now" rather than implying a broader
    // "active" concept the data can't actually support.
    final volunteersAsync = ref.watch(rescueVolunteersProvider);
    final onlineVolunteers = volunteersAsync.value?.where((v) => v.isOnline).length;
    final totalVolunteers = volunteersAsync.value?.length;

    return Row(
      children: [
        _CompactMetricCard(
          title: 'Capacity',
          primary: currentOccupancy == null
              ? '—'
              : '$currentOccupancy / ${maxCapacity ?? '—'}',
          secondary: maxCapacity == null ? 'Capacity not configured' : null,
          // Opens Organization Profile (spec §9) — Shelter Capacity now
          // lives there (see section 8), so this is the "existing... page"
          // this metric's own maximum comes from, rather than the Animal
          // Records list this used to open.
          onTap: () async {
            final membership = await ref.read(currentOrgMembershipProvider.future);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OrganizationProfileEditPage(organizationId: membership?.organizationId)),
              );
            }
          },
        ),
        const SizedBox(width: 10),
        _CompactMetricCard(
          title: 'Active Rescues',
          primary: activeCaseCount == null ? '—' : '$activeCaseCount cases',
          secondary: activeAnimalCount == null ? null : '$activeAnimalCount animals',
          onTap: () => _pushRescueReview(context, ref),
        ),
        const SizedBox(width: 10),
        _CompactMetricCard(
          title: 'Active Volunteers',
          primary: onlineVolunteers == null ? '—' : '$onlineVolunteers online',
          secondary: totalVolunteers == null ? 'True active-state requires additional data' : '$totalVolunteers registered',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VolunteersPage())),
        ),
      ],
    );
  }

  void _pushRescueReview(BuildContext context, WidgetRef ref) {
    ref.read(rescuePipelineTabProvider.notifier).select(RescuePipelineTab.review);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
  }
}

// ─── Current Operations KPIs ─────────────────────────────────────────────

class CurrentOperationsSection extends ConsumerWidget {
  const CurrentOperationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(casesForTabProvider(RescuePipelineTab.review));
    final assign = ref.watch(casesForTabProvider(RescuePipelineTab.assign));
    final ongoing = ref.watch(casesForTabProvider(RescuePipelineTab.ongoing));
    final treatment = ref.watch(casesForTabProvider(RescuePipelineTab.treatment));
    final intake = ref.watch(casesForTabProvider(RescuePipelineTab.intake));
    final animalsAsync = ref.watch(allAnimalRecordsProvider);
    final pendingApps = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.pending)));
    final interviewApps = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.interview)));
    final approvedApps = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved)));
    final adoptedBucket = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted)));
    final overdueFollowUps = ref.watch(overdueFollowUpsProvider);
    final activeByRider = ref.watch(activeAssignmentsByRiderProvider);
    final transporters = ref.watch(petTransportersProvider);

    int? lenOf(AsyncValue<List<dynamic>> a) => a.value?.length;

    final activeRescueCases = [review, assign, ongoing, treatment, intake]
        .map(lenOf)
        .fold<int?>(0, (sum, v) => sum == null || v == null ? null : sum + v);

    final pendingAdoptionApps = [pendingApps, interviewApps]
        .map(lenOf)
        .fold<int?>(0, (sum, v) => sum == null || v == null ? null : sum + v);

    final availableForAdoption = animalsAsync.value?.where((a) => a.adoptionStatus == 'adoptable').length;

    final activeMonitoring = adoptedBucket.value
        ?.where((a) => classifyAdoptionLifecycle(a) == AdoptionLifecycleStage.adopted)
        .length;

    final activeAssignments = activeByRider.value?.values
        .where((s) => s == TransportAssignmentStatus.pending || s == TransportAssignmentStatus.accepted)
        .length;
    final availableTransporters = transporters.value == null || !activeByRider.hasValue
        ? null
        : transporters.value!.where((t) {
            if (!t.isOnline) return false;
            final status = activeByRider.value![t.uid];
            return status != TransportAssignmentStatus.pending && status != TransportAssignmentStatus.accepted;
          }).length;

    String v(int? n) => n == null ? '—' : '$n';

    return _DashboardSectionCard(
      title: 'Current Operations',
      child: _KpiWrap(cards: [
        _KpiCard(
          value: v(activeRescueCases),
          label: 'Active rescue cases',
          onTap: () => _pushRescue(context, ref, RescuePipelineTab.review),
        ),
        _KpiCard(
          value: v(lenOf(review)),
          label: 'Pending rescue reports',
          onTap: () => _pushRescue(context, ref, RescuePipelineTab.review),
        ),
        _KpiCard(
          value: v(review.value?.where((c) => c.urgency == 'Critical').length),
          label: 'Critical rescue reports',
          onTap: () => _pushRescue(context, ref, RescuePipelineTab.review),
        ),
        _KpiCard(
          value: v(lenOf(treatment)),
          label: 'Cases in treatment',
          onTap: () => _pushRescue(context, ref, RescuePipelineTab.treatment),
        ),
        _KpiCard(
          value: v(lenOf(intake)),
          label: 'Cases awaiting intake',
          onTap: () => _pushRescue(context, ref, RescuePipelineTab.intake),
        ),
        _KpiCard(
          value: v(availableForAdoption),
          label: 'Animals available for adoption',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimalRecordsPage())),
        ),
        _KpiCard(
          value: v(pendingAdoptionApps),
          label: 'Pending adoption applications',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdoptionApplicationReviewPage(initialStatus: AdoptionStatus.pending))),
        ),
        _KpiCard(
          value: v(lenOf(approvedApps)),
          label: 'Approved applications awaiting release',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdoptionApplicationReviewPage(initialStatus: AdoptionStatus.approved))),
        ),
        _KpiCard(
          value: v(activeMonitoring),
          label: 'Active post-adoption monitoring',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdoptionApplicationReviewPage(initialStatus: AdoptionStatus.adopted))),
        ),
        _KpiCard(
          value: v(lenOf(overdueFollowUps)),
          label: 'Overdue post-adoption follow-ups',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdoptionApplicationReviewPage(initialStatus: AdoptionStatus.adopted))),
        ),
        _KpiCard(value: v(activeAssignments), label: 'Active transporter assignments'),
        _KpiCard(value: v(availableTransporters), label: 'Available transporters'),
      ]),
    );
  }

  void _pushRescue(BuildContext context, WidgetRef ref, RescuePipelineTab tab) {
    ref.read(rescuePipelineTabProvider.notifier).select(tab);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
  }
}
