import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/alert_claims.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_alerts.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/events_card.dart';
import 'package:respawnd1/features/adminhome/dashboard/care_need_row.dart';
import 'package:respawnd1/features/adminhome/dashboard/rescue_readiness.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/care/care_rounds_widgets.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_home.dart';

/// The "Today" tab, top to bottom: Priority actions, Rescue readiness for
/// today, Rescue, Shelter care, Adoption, Donations & funds and Volunteer
/// events. Recent activity is on the bell's Notifications page
/// (admin_notifications.dart).
class TodayView extends StatelessWidget {
  final GlobalKey? priorityKey;
  const TodayView({super.key, this.priorityKey});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: priorityKey, child: const PriorityActionsCard()),
        const SizedBox(height: 14),
        const RescueReadinessCard(),
        const SizedBox(height: 14),
        const RescueSummaryCard(),
        const SizedBox(height: 14),
        const ShelterCareCard(),
        const SizedBox(height: 14),
        const AdoptionSummaryCard(),
        const SizedBox(height: 14),
        const DonationsFundsCard(),
        const SizedBox(height: 14),
        const EventsCard(),
      ],
    );
  }
}

// ─── Priority actions ────────────────────────────────────────────────────

/// Priority actions show at most this many items; the rest are under View all.
const int kPriorityActionsShown = 5;

class PriorityActionsCard extends ConsumerStatefulWidget {
  const PriorityActionsCard({super.key});

  @override
  ConsumerState<PriorityActionsCard> createState() => _PriorityActionsCardState();
}

class _PriorityActionsCardState extends ConsumerState<PriorityActionsCard> {
  AlertArea? _area;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardAlertsProvider);
    final filtered = state.alerts.where((a) => _area == null || a.area == _area).toList();
    final shown = _all ? filtered : filtered.take(kPriorityActionsShown).toList();

    Widget tab(String label, AlertArea? area) {
      final on = _area == area;
      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => setState(() {
            _area = area;
            _all = false;
          }),
          labelStyle: GoogleFonts.zain(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: on ? AppColors.background : AppColors.textPrimary,
          ),
          selectedColor: AppColors.textPrimary,
          backgroundColor: const Color(0xFFFFFDF8),
          side: BorderSide(color: on ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.14)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      );
    }

    return SectionCard(
      icon: Icons.pending_actions,
      title: 'Priority actions',
      trailing: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 1),
        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(10)),
        child: Text(
          '${state.alerts.length}',
          style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.background),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                tab('All', null),
                for (final a in AlertArea.values) tab('${a.label} ${state.alerts.where((x) => x.area == a).length}', a),
              ],
            ),
          ),
          if (state.alerts.isEmpty && state.loading)
            const DashLoading(label: 'Checking queues…')
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.done_all, size: 32, color: Color(0xFF3F8F5A)),
                  SizedBox(height: 4),
                  Text('All caught up'),
                ],
              ),
            )
          else
            for (int i = 0; i < shown.length; i++) _ActionRow(alert: shown[i], first: i == 0),
          if (filtered.length > kPriorityActionsShown)
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Container(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _all ? 'Show less' : 'View all ${filtered.length}',
                      style: dashBody(size: 14, weight: FontWeight.w700),
                    ),
                    Icon(_all ? Icons.expand_less : Icons.chevron_right, size: 18, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
          if (state.failedSources.isNotEmpty)
            DetailLine(
              Icons.cloud_off_outlined,
              'Some items may be missing: couldn’t load ${state.failedSources.join(', ')}.',
              color: DashSeverity.critical.color,
              maxLines: null,
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  final DashAlert alert;
  final bool first;
  const _ActionRow({required this.alert, required this.first});

  Future<void> _claim(BuildContext context, WidgetRef ref, String action, AlertClaim? claim) async {
    final orgId = await ref.read(dashboardOrgIdProvider.future);
    if (orgId == null) return;
    try {
      if (action == 'release') {
        await releaseAlert(orgId: orgId, key: alert.key);
      } else {
        await claimAlert(orgId: orgId, key: alert.key, title: alert.title);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'release' && claim != null && !claim.isMine
              ? 'Only ${claim.byName} or an admin can release this.'
              : 'Could not save: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = alert.severity.color;
    final subtitle = [alert.subject, alert.status].whereType<String>().join(' · ');
    final claim = ref.watch(alertClaimsProvider).asData?.value[alertClaimDocId(alert.key)];
    return InkWell(
      onTap: () => alert.open(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
                child: Icon(alert.icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title, style: dashBody(size: 15, weight: FontWeight.w700)),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: dashMuted(12.5)),
                    if (alert.timing != null || claim != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (alert.timing != null)
                              StatusChip(
                                alert.timing!,
                                tone: alert.timing!.startsWith('Overdue') ? ChipTone.red : ChipTone.info,
                                icon: alert.timing!.startsWith('Overdue') ? Icons.error_outline : Icons.schedule,
                              ),
                            // Dashboard gap 7: who is handling it.
                            if (claim != null)
                              StatusChip(
                                '${claim.isMine ? 'You’re' : '${claim.byName} is'} on it'
                                    '${claim.at == null ? '' : ' · ${elapsedSince(claim.at)}'}',
                                tone: ChipTone.green,
                                icon: Icons.pan_tool_outlined,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Who is handling this',
                icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                onSelected: (a) => _claim(context, ref, a, claim),
                itemBuilder: (_) => [
                  if (claim == null)
                    const PopupMenuItem(value: 'claim', child: Text('I’m on it'))
                  else if (claim.isMine)
                    const PopupMenuItem(value: 'release', child: Text('Release'))
                  else ...[
                      PopupMenuItem(value: 'claim', child: Text('Take over from ${claim.byName}')),
                      const PopupMenuItem(value: 'release', child: Text('Release (admins)')),
                    ],
                ],
              ),
              Center(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: alert.severity == DashSeverity.info ? Colors.transparent : AppColors.textPrimary,
                    foregroundColor: alert.severity == DashSeverity.info ? AppColors.textPrimary : AppColors.background,
                    side: const BorderSide(color: AppColors.textPrimary, width: 1.3),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => alert.open(context, ref),
                  child: Text(alert.button, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Rescue ──────────────────────────────────────────────────────────────

/// Urgent cases, reports awaiting verification and the active cases by
/// stage.
class RescueSummaryCard extends ConsumerWidget {
  const RescueSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(dashboardRescueSnapshotProvider);
    // Review tab = pending review, verifying and accepted-without-clinic.
    final reviewTab = ref.watch(casesForTabProvider(RescuePipelineTab.review)).asData?.value;

    return SectionCard(
      icon: Icons.sos,
      title: 'Rescue',
      onOpen: () => openRescueTab(context, ref, RescuePipelineTab.review),
      child: DashAsync<RescueSnapshot>(
        value: snapAsync,
        what: 'rescue cases',
        builder: (snap) {
          final epoch = DateTime.fromMillisecondsSinceEpoch(0);
          int oldestFirst(RescueCase a, RescueCase b) => (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch);
          final urgent = [...snap.urgentWaiting]..sort(oldestFirst);
          final verifying = [
            for (final c in reviewTab ?? snap.of(RescueStage.review))
              if (c.status == RescueStatus.pendingReview || c.status == RescueStatus.verifying) c,
          ]..sort(oldestFirst);
          final active = snap.all;
          const stages = [
            (RescueStage.clinic, RescuePipelineTab.review),
            (RescueStage.transporter, RescuePipelineTab.assign),
            (RescueStage.transit, RescuePipelineTab.ongoing),
            (RescueStage.treatment, RescuePipelineTab.treatment),
            (RescueStage.intake, RescuePipelineTab.intake),
            (RescueStage.fieldIssue, RescuePipelineTab.ongoing),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BigStat(
                      value: '${urgent.length}',
                      label: 'Urgent cases',
                      color: urgent.isNotEmpty ? DashSeverity.critical.color : null,
                      onTap: () => openRescueTab(context, ref, urgentTabFor(urgent)),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: '${verifying.length}',
                      label: 'Awaiting verification',
                      color: verifying.isNotEmpty ? DashSeverity.warning.color : null,
                      onTap: () => openRescueTab(context, ref, RescuePipelineTab.review),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: '${active.length}',
                      label: 'Active cases',
                      onTap: () => openRescueTab(context, ref, RescuePipelineTab.ongoing),
                    ),
                  ),
                ],
              ),
              const CardLabel('Urgent cases'),
              if (urgent.isEmpty)
                const DashEmpty('No critical case is waiting on staff.')
              else
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All urgent cases',
                  children: [
                    for (final c in urgent)
                      _CaseRow(
                        c: c,
                        sub: '${c.status.label} · waiting ${elapsedSince(c.createdAt).replaceAll(' ago', '')}',
                        chip: const StatusChip('Critical', tone: ChipTone.red, icon: Icons.priority_high),
                      ),
                  ],
                ),
              const CardLabel('Awaiting verification'),
              if (verifying.isEmpty)
                const DashEmpty('Every report has been assessed.')
              else
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All reports to verify',
                  children: [
                    for (final c in verifying)
                      _CaseRow(
                        c: c,
                        sub: c.status == RescueStatus.verifying
                            ? 'Rider sent to verify · reported ${elapsedSince(c.createdAt)}'
                            : 'Not yet assessed · reported ${elapsedSince(c.createdAt)}',
                        chip: _urgencyChip(c),
                      ),
                  ],
                ),
              const CardLabel('Active cases by stage'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (stage, tab) in stages)
                    ActionChip(
                      avatar: Icon(stage.icon, size: 16, color: AppColors.textPrimary),
                      label: Text('${stage.label} ${snap.count(stage)}'),
                      labelStyle: dashBody(size: 12.5, weight: FontWeight.w700),
                      backgroundColor: const Color(0xFFFFFDF8),
                      side: BorderSide(
                        color: stage == RescueStage.fieldIssue && snap.count(stage) > 0
                            ? DashSeverity.critical.color
                            : AppColors.textPrimary.withValues(alpha: 0.14),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openRescueTab(context, ref, tab),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static StatusChip _urgencyChip(RescueCase c) => switch (UrgencyLevel.fromFirestoreValue(c.urgency)) {
    UrgencyLevel.critical => const StatusChip('Critical', tone: ChipTone.red),
    UrgencyLevel.medium => const StatusChip('Medium', tone: ChipTone.amber),
    _ => const StatusChip('Low', tone: ChipTone.info),
  };
}

class _CaseRow extends StatelessWidget {
  final RescueCase c;
  final String sub;
  final Widget chip;
  const _CaseRow({required this.c, required this.sub, required this.chip});

  @override
  Widget build(BuildContext context) {
    final where = c.address == null ? '' : ' · ${c.address!.split(',').first}';
    return InkWell(
      onTap: () => openRescueCase(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.speciesSummary.isEmpty ? 'Animal' : c.speciesSummary} #${c.shortCaseId}$where',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14.5, weight: FontWeight.w700),
                  ),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: dashMuted(12.5)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            chip,
          ],
        ),
      ),
    );
  }
}

// ─── Shelter care ────────────────────────────────────────────────────────

/// The animals' continuing care: who needs medication, isolation,
/// treatment or other ongoing care, most urgent first.
class ShelterCareCard extends ConsumerWidget {
  const ShelterCareCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);
    final vax = ref.watch(vaccinationsByAnimalProvider).asData?.value;
    final plans = ref.watch(activeMedicationPlansByAnimalProvider).asData?.value;
    final missed = ref.watch(missedDosesByAnimalProvider).asData?.value;
    final orgId = ref.watch(dashboardOrgIdProvider).asData?.value;
    final isAdmin = ref.watch(isOrgAdminProvider).asData?.value ?? false;

    return SectionCard(
      icon: Icons.monitor_heart,
      title: 'Shelter care',
      onOpen: () => openAnimalRecords(context),
      child: DashAsync<List<AnimalRecord>>(
        value: recordsAsync,
        what: 'animal records',
        builder: (records) {
          final inCare = records.where(isInCare).toList();
          final needing = animalsNeedingCare(inCare, plans: plans, missedDoses: missed, vaccinations: vax);

          int count(bool Function(CareNeed) test) => needing.where((e) => e.$2.any(test)).length;
          final tally = [
            (Icons.medication, 'Medication', count((n) => n.label.startsWith('Medication')), ChipTone.amber),
            (Icons.do_not_touch, 'Isolation', count((n) => n.label == 'Isolation'), ChipTone.amber),
            (Icons.local_hospital, 'In treatment', count((n) => n.label == 'In treatment'), ChipTone.red),
            (Icons.error_outline, 'Missed doses', count((n) => n.label.contains('missed dose')), ChipTone.red),
            (Icons.vaccines, 'Vaccine overdue', count((n) => n.label == 'Vaccine overdue'), ChipTone.red),
            (Icons.healing, 'Recovering', count((n) => n.label == 'Recovering'), ChipTone.info),
            (Icons.accessible, 'Special needs', count((n) => n.label.startsWith('Special needs')), ChipTone.info),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                needing.isEmpty
                    ? '${plural(inCare.length, 'animal')} in care. None needs continuing care.'
                    : '${plural(needing.length, 'animal')} of ${inCare.length} in care need continuing care.',
                style: dashBody(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final (icon, label, n, tone) in tally)
                    if (n > 0) StatusChip('$label $n', tone: tone, icon: icon),
                ],
              ),
              if (needing.isNotEmpty) ...[
                const CardLabel('Continuing care'),
                ExpandableList(
                  initialCount: 5,
                  moreLabel: 'All animals needing care',
                  children: [for (final (a, needs) in needing) CareNeedRow(animal: a, needs: needs)],
                ),
              ],
              const SizedBox(height: 4),
              const DetailLine(
                Icons.medication,
                'Carers log each dose, with optional photos, on the animal’s Medical tab. Missed doses show here.',
                maxLines: null,
              ),
              if (orgId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DashLinkButton(
                      label: 'Today’s care rounds',
                      icon: Icons.checklist,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CareRoundsPage(organizationId: orgId, canEditSetup: isAdmin),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Adoption ────────────────────────────────────────────────────────────

/// Animals ready to be turned over for adoption (vaccinations,
/// spay/neuter, medication course and behavior all done), then the
/// applications awaiting review and the upcoming interviews.
class AdoptionSummaryCard extends ConsumerWidget {
  const AdoptionSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);
    final vax = ref.watch(vaccinationsByAnimalProvider).asData?.value;
    final plans = ref.watch(activeMedicationPlansByAnimalProvider).asData?.value;
    final pending = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.pending))).asData?.value;
    final interview = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.interview))).asData?.value;

    return SectionCard(
      icon: Icons.favorite,
      title: 'Adoption',
      onOpen: () => openAdoptionQueue(context, AdoptionStatus.pending),
      child: DashAsync<List<AnimalRecord>>(
        value: recordsAsync,
        what: 'animal records',
        builder: (records) {
          // Candidates: in care, not in treatment, not already reserved or
          // placed, not being transferred out.
          final candidates = records
              .where((a) => isInCare(a) && !hasOpenMedicalCase(a) && !a.isReserved && !a.isTransferredOut)
              .map((a) => (a, turnoverChecksFor(a, vaccines: vax == null ? null : healthStatusOf(vax[a.id]), plans: plans?[a.id])))
              .toList();
          int gaps(List<TurnoverCheck> c) => c.where((x) => x.done != true).length;
          final ready = candidates.where((e) => gaps(e.$2) == 0).toList()
            ..sort((x, y) => (x.$1.isAdoptable ? 1 : 0).compareTo(y.$1.isAdoptable ? 1 : 0));
          final almost = candidates.where((e) => gaps(e.$2) > 0 && gaps(e.$2) <= 2).toList()
            ..sort((x, y) => gaps(x.$2).compareTo(gaps(y.$2)));

          final epoch = DateTime.fromMillisecondsSinceEpoch(0);
          final toReview = [...?pending]..sort((a, b) => (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch));
          final today = DateTime.now();
          final startOfToday = DateTime(today.year, today.month, today.day);
          final upcoming = [
            for (final a in interview ?? const <AdoptionApplication>[])
              if (a.appointmentDate != null && !a.appointmentDate!.isBefore(startOfToday)) a,
          ]..sort((a, b) => a.appointmentDate!.compareTo(b.appointmentDate!));
          final unscheduled = (interview ?? const <AdoptionApplication>[]).where((a) => a.appointmentDate == null).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BigStat(
                      value: '${ready.length}',
                      label: 'Ready for adoption',
                      color: ready.isNotEmpty ? DashSeverity.ok.color : null,
                      onTap: () => openAnimalRecords(context),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: pending == null ? '—' : '${toReview.length}',
                      label: 'Applications to review',
                      color: toReview.isNotEmpty ? DashSeverity.warning.color : null,
                      onTap: () => openAdoptionQueue(context, AdoptionStatus.pending),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: interview == null ? '—' : '${upcoming.length}',
                      label: 'Upcoming interviews',
                      onTap: () => openAdoptionQueue(context, AdoptionStatus.interview),
                    ),
                  ),
                ],
              ),
              const CardLabel('Ready to turn over for adoption'),
              if (ready.isEmpty)
                const DashEmpty(
                  'No animal has vaccinations, spay/neuter, medication and behavior all done yet.',
                  severity: DashSeverity.info,
                )
              else
                ExpandableList(
                  initialCount: 5,
                  moreLabel: 'All ready animals',
                  children: [
                    for (final (a, checks) in ready)
                      _TurnoverRow(
                        animal: a,
                        checks: checks,
                        trailing: a.isAdoptable
                            ? const StatusChip('Listed', tone: ChipTone.green, icon: Icons.check)
                            : const StatusChip('Not listed yet', tone: ChipTone.amber, icon: Icons.campaign),
                      ),
                  ],
                ),
              if (almost.isNotEmpty) ...[
                const CardLabel('Almost ready'),
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All almost-ready animals',
                  children: [
                    for (final (a, checks) in almost)
                      _TurnoverRow(animal: a, checks: checks, showOnlyGaps: true),
                  ],
                ),
              ],
              const CardLabel('Awaiting application review'),
              if (pending == null)
                const DashLoading(label: 'Loading applications…')
              else if (toReview.isEmpty)
                const DashEmpty('No applications waiting for review.')
              else
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All applications to review',
                  children: [for (final app in toReview) _ApplicationRow(app: app)],
                ),
              const CardLabel('Upcoming interviews'),
              if (interview == null)
                const DashLoading(label: 'Loading interviews…')
              else if (upcoming.isEmpty)
                const DashEmpty('No interviews scheduled from today on.', severity: DashSeverity.info)
              else
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All upcoming interviews',
                  children: [for (final app in upcoming) _ApplicationRow(app: app)],
                ),
              if (unscheduled > 0)
                DetailLine(
                  Icons.event_busy,
                  '${plural(unscheduled, 'application')} in Interview without a date yet.',
                  color: DashSeverity.warning.color,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TurnoverRow extends StatelessWidget {
  final AnimalRecord animal;
  final List<TurnoverCheck> checks;
  final Widget? trailing;
  final bool showOnlyGaps;
  const _TurnoverRow({required this.animal, required this.checks, this.trailing, this.showOnlyGaps = false});

  @override
  Widget build(BuildContext context) {
    final shown = showOnlyGaps ? checks.where((c) => c.done != true) : checks;
    return InkWell(
      onTap: () => openAnimalRecord(context, animal),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            DashThumb(url: animal.photoUrls.isNotEmpty ? animal.photoUrls.first : null, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    animal.name.isNotEmpty ? animal.name : '${animal.species} (unnamed)',
                    style: dashBody(size: 14.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final c in shown)
                        StatusChip(
                          showOnlyGaps ? '${c.label}: ${c.detail}' : c.label,
                          tone: c.done == true
                              ? ChipTone.green
                              : (c.done == false ? ChipTone.amber : ChipTone.notRecorded),
                          icon: c.done == true ? Icons.check : (c.done == false ? Icons.close : Icons.question_mark),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  final AdoptionApplication app;
  const _ApplicationRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final (String sub, StatusChip chip) = switch (app.status) {
      AdoptionStatus.pending => (
      'Screening · waiting ${elapsedSince(app.createdAt).replaceAll(' ago', '')}',
      const StatusChip('Screen', tone: ChipTone.amber),
      ),
      AdoptionStatus.interview => (
      app.appointmentDate == null
          ? 'Interview not scheduled'
          : 'Interview ${shortDate(app.appointmentDate!)}${app.appointmentTime == null ? '' : ', ${app.appointmentTime}'}',
      const StatusChip('Interview', tone: ChipTone.info),
      ),
      _ => (
      app.scheduledReleaseDate == null
          ? 'Handover not scheduled'
          : 'Handover ${shortDate(app.scheduledReleaseDate!)}',
      const StatusChip('Approved', tone: ChipTone.green),
      ),
    };
    return InkWell(
      onTap: () => openApplication(context, app),
      // Rows sit in an ExpandableList, which draws the dividers.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_firstName(app.adopterName)} → ${app.animalName.isEmpty ? 'animal' : app.animalName}',
                    style: dashBody(size: 14.5, weight: FontWeight.w700),
                  ),
                  Text(sub, style: dashMuted(12.5)),
                ],
              ),
            ),
            chip,
          ],
        ),
      ),
    );
  }
}

String _firstName(String full) {
  final parts = full.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return full;
  return '${parts.first} ${parts.last[0]}.';
}

// ─── Donations & funds (authorized only) ─────────────────────────────────

class DonationsFundsCard extends ConsumerWidget {
  const DonationsFundsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManageAsync = ref.watch(canManageFinancesProvider);
    final canManage = canManageAsync.asData?.value ?? false;
    return SectionCard(
      icon: Icons.volunteer_activism,
      title: 'Donations & funds',
      onOpen: () => openDonationsAdmin(context),
      trailing: canManage
          ? const Padding(
        padding: EdgeInsets.only(right: 6),
        child: StatusChip('Money managers', tone: ChipTone.ink, icon: Icons.lock),
      )
          : null,
      child: canManageAsync.isLoading
          ? const DashLoading()
          : (!canManage
          ? const RestrictedNotice(
        'Fund balances, donation records and bills are visible to the people who manage money.',
      )
          : const _FundsBody()),
    );
  }
}

/// How well a fund category is covered.
enum FundLevel {
  sufficient('Sufficient', ChipTone.green, Icons.check),
  low('Low', ChipTone.amber, Icons.trending_down),
  critical('Critical', ChipTone.red, Icons.error_outline);

  const FundLevel(this.label, this.tone, this.icon);
  final String label;
  final ChipTone tone;
  final IconData icon;

  /// Sufficient: the money set aside covers the need. Low: at least half.
  /// Critical: less than half. Nothing needed counts as sufficient.
  static FundLevel of(double setAside, double need) {
    if (need <= 0) return FundLevel.sufficient;
    final r = setAside / need;
    if (r >= 1) return FundLevel.sufficient;
    if (r >= 0.5) return FundLevel.low;
    return FundLevel.critical;
  }
}

/// The allocation category ('Food', 'Medicine and Treatment', ... as in
/// kAllocationCategories) a bill counts against.
String fundCategoryOfExpense(ExpenseCategory c) => switch (c) {
  ExpenseCategory.consultation ||
  ExpenseCategory.medication ||
  ExpenseCategory.procedure ||
  ExpenseCategory.laboratory ||
  ExpenseCategory.vaccination ||
  ExpenseCategory.confinement => 'Medicine and Treatment',
  ExpenseCategory.transport => 'Transport',
  ExpenseCategory.foodAndSupplies => 'Food',
  ExpenseCategory.utilities => 'Bills and Utilities',
  ExpenseCategory.rent => 'Shelter',
  ExpenseCategory.staffCompensation || ExpenseCategory.administrative => 'Administrative',
  ExpenseCategory.other => 'Other',
};

/// The allocation categories a campaign's money is set aside for, from its
/// purpose tags (or, untagged, its fund kind). Empty = general money that
/// can go anywhere ('General Operations' or no purpose).
List<String> fundCategoriesOfCampaign(DonationListing c) {
  const byTag = {
    'Medicine & Treatment': 'Medicine and Treatment',
    'Food and Supplies': 'Food',
    'Shelter': 'Shelter',
    'Rescue': 'Transport',
  };
  final fromTags = {for (final t in c.purposeTags) ?byTag[t]}.toList();
  if (fromTags.isNotEmpty) return fromTags;
  return switch (c.fundKind) {
  'medical' => const ['Medicine and Treatment'],
  'shelter_resource' => const ['Shelter'],
  _ => const [],
  };
}

class _FundCategory {
  final String name;
  double setAside = 0;
  double unpaid = 0;
  double spent30 = 0;
  double allocatedTotal = 0;
  _FundCategory(this.name);

  double get need => unpaid + spent30;
  FundLevel get level => FundLevel.of(setAside, need);
}

class _FundsBody extends ConsumerWidget {
  const _FundsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(adminCampaignsProvider);
    final allocations = ref.watch(orgAllocationsProvider);
    final expenses = ref.watch(allCaseExpensesProvider);
    final general = ref.watch(myGeneralExpensesProvider);
    final donations = ref.watch(allDonationsProvider);
    final asOf = DateTime.now();

    return DashAsync<List<DonationListing>>(
      value: campaignsAsync,
      what: 'campaigns',
      builder: (all) {
        final live = all.where((c) => !c.isDraft && !c.isArchived && c.status != 'closed').toList();

        // ── Funds by category ──
        final cats = {for (final n in kAllocationCategories) n: _FundCategory(n)};
        _FundCategory cat(String name) => cats[name] ?? cats['Other']!;
        var generalPool = 0.0;
        var restrictedElsewhere = 0.0;
        for (final c in live) {
          final balance = c.availableBalance > 0 ? c.availableBalance : 0.0;
          if (balance == 0) continue;
          final targets = fundCategoriesOfCampaign(c);
          if (targets.isNotEmpty) {
            for (final t in targets) {
              cat(t).setAside += balance / targets.length;
            }
          } else if (c.restricted) {
            restrictedElsewhere += balance;
          } else {
            generalPool += balance;
          }
        }
        final since = asOf.subtract(const Duration(days: 30));
        for (final a in allocations.asData?.value ?? const <({String campaignId, AllocationEntry entry})>[]) {
          if (a.entry.isTransfer) continue;
          final c = cat(a.entry.category);
          c.allocatedTotal += a.entry.amount;
          if (a.entry.createdAt != null && a.entry.createdAt!.isAfter(since)) c.spent30 += a.entry.amount;
        }
        for (final e in [...?expenses.asData?.value, ...?general.asData?.value]) {
          if (e.outstandingAmount > 0) cat(fundCategoryOfExpense(e.category)).unpaid += e.outstandingAmount;
        }
        final shown = cats.values.where((c) => c.setAside > 0 || c.need > 0 || c.allocatedTotal > 0).toList()
          ..sort((a, b) => b.level.index.compareTo(a.level.index));
        final loadingParts = allocations.isLoading || expenses.isLoading || general.isLoading;
        final failedParts = [
          if (allocations.hasError) 'allocations',
          if (expenses.hasError) 'case bills',
          if (general.hasError) 'general expenses',
        ];

        // ── Donations ──
        double pct(DonationListing c) => c.target > 0 ? c.collected / c.target : 0;
        final running = live.where((c) => c.target > 0 && !c.isEnded && !c.isGoalMet).toList();
        final almost = running.where((c) => pct(c) >= 0.75 && pct(c) < 1).toList()
          ..sort((a, b) => pct(b).compareTo(pct(a)));
        String? attentionReason(DonationListing c) {
          if (c.needsExtensionDecision) return 'Ended short of its goal: extend or close it';
          if (c.status == 'paused') return 'Paused';
          if (c.status == 'goal_not_met') return 'Ended short of its goal';
          if (c.target > 0 && c.endDate != null && !c.isEnded && c.daysRemaining <= 14 && pct(c) < 0.75) {
            return '${plural(c.daysRemaining, 'day')} left at ${(pct(c) * 100).round()}%';
          }
          return null;
        }

        final attention = [
          for (final c in live)
            if (attentionReason(c) case final reason?) (c, reason),
        ]..sort((a, b) => a.$1.daysRemaining.compareTo(b.$1.daysRemaining));
        final refunds = [
          for (final d in donations.asData?.value ?? const <DonationHistoryRecord>[])
            if (d.refundRequest?.isOpen ?? false) d,
        ]..sort((a, b) => (a.refundRequest!.requestedAt ?? asOf).compareTo(b.refundRequest!.requestedAt ?? asOf));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Expanded(child: Text('As of ${formatDateTime(asOf)}', style: dashMuted(12.5))),
              ],
            ),
            const CardLabel('Funds by category'),
            if (loadingParts && shown.isEmpty)
              const DashLoading(label: 'Loading allocations and bills…')
            else if (shown.isEmpty)
              const DashEmpty('No funds allocated or bills recorded yet.', severity: DashSeverity.info)
            else
              for (int i = 0; i < shown.length; i++) _FundCategoryRow(c: shown[i], first: i == 0),
            if (failedParts.isNotEmpty)
              DetailLine(
                Icons.cloud_off_outlined,
                'Couldn’t load ${failedParts.join(', ')}; levels may be off.',
                color: DashSeverity.critical.color,
                maxLines: null,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                LegendText(AppColors.textPrimary, 'General funds, any category ${formatPeso(generalPool)}'),
                if (restrictedElsewhere > 0)
                  LegendText(AppColors.lavenderrspwn, 'Restricted to specific animals ${formatPeso(restrictedElsewhere)}'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Need = unpaid bills + the last 30 days’ spending in that category. Sufficient: money set aside '
                    'covers the need. Low: covers at least half. Critical: less than half. General funds can cover a gap.',
                style: dashMuted(),
              ),
            ),
            const CardLabel('Almost complete'),
            if (almost.isEmpty)
              const DashEmpty('No campaign is between 75% and its goal.', severity: DashSeverity.info)
            else
              for (final c in almost.take(3)) _CampaignRow(c: c),
            const CardLabel('Needs more attention'),
            if (attention.isEmpty)
              const DashEmpty('No campaign is ending short or waiting on a decision.')
            else
              ExpandableList(
                initialCount: 3,
                moreLabel: 'All campaigns needing attention',
                children: [
                  for (final (c, reason) in attention)
                    InkWell(
                      onTap: () => openCampaign(context, c.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: dashBody(size: 14, weight: FontWeight.w700),
                                  ),
                                  Text(
                                    '$reason · ${formatPeso(c.collected)}'
                                        '${c.target > 0 ? ' of ${formatPeso(c.target)}' : ''}',
                                    style: dashMuted(12.5),
                                  ),
                                ],
                              ),
                            ),
                            const StatusChip('Attention', tone: ChipTone.amber, icon: Icons.flag_outlined),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            const CardLabel('Needs refund review'),
            if (donations.isLoading)
              const DashLoading(label: 'Loading donations…')
            else if (donations.hasError)
              DashError(what: 'donations', error: donations.error!)
            else if (refunds.isEmpty)
                const DashEmpty('No refund requests waiting.')
              else
                ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All refund requests',
                  children: [
                    for (final d in refunds)
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DonationAdminHomeScreen(openOnRefunds: true)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${formatPeso(d.amountValue)} · ${d.displayName}',
                                      style: dashBody(size: 14, weight: FontWeight.w700),
                                    ),
                                    Text(
                                      [
                                        if (d.campaignName.isNotEmpty) d.campaignName,
                                        d.refundRequest!.reason?.label ?? 'Refund requested',
                                        'requested ${elapsedSince(d.refundRequest!.requestedAt)}',
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: dashMuted(12.5),
                                    ),
                                  ],
                                ),
                              ),
                              StatusChip(
                                d.refundRequest!.status == 'failed' ? 'Refund failed' : 'Review',
                                tone: d.refundRequest!.status == 'failed' ? ChipTone.red : ChipTone.amber,
                                icon: Icons.undo,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DashLinkButton(label: 'Donations', icon: Icons.volunteer_activism, onPressed: () => openDonationsAdmin(context)),
                DashLinkButton(
                  label: 'Expenses & receipts',
                  icon: Icons.receipt_long,
                  onPressed: () => openExpenseOversight(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FundCategoryRow extends StatelessWidget {
  final _FundCategory c;
  final bool first;
  const _FundCategoryRow({required this.c, required this.first});

  @override
  Widget build(BuildContext context) {
    final level = c.level;
    final color = switch (level) {
      FundLevel.sufficient => DashSeverity.ok.color,
      FundLevel.low => DashSeverity.warning.color,
      FundLevel.critical => DashSeverity.critical.color,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.name, style: dashBody(size: 14.5, weight: FontWeight.w700))),
              StatusChip(level.label, tone: level.tone, icon: level.icon),
            ],
          ),
          const SizedBox(height: 5),
          DashProgress(
            fraction: c.need <= 0 ? 1 : c.setAside / c.need,
            color: color,
            semanticsLabel: '${formatPeso(c.setAside)} set aside for ${formatPeso(c.need)} needed',
          ),
          const SizedBox(height: 3),
          Text(
            c.need <= 0
                ? '${formatPeso(c.setAside)} set aside · nothing unpaid or spent in 30 days'
                : '${formatPeso(c.setAside)} set aside · needs ${formatPeso(c.need)} '
                '(${formatPeso(c.unpaid)} unpaid + ${formatPeso(c.spent30)} spent in 30 days)',
            style: dashMuted(12.5),
          ),
          if (c.allocatedTotal > 0) Text('${formatPeso(c.allocatedTotal)} allocated so far', style: dashMuted(12)),
        ],
      ),
    );
  }
}

class _CampaignRow extends StatelessWidget {
  final DonationListing c;
  const _CampaignRow({required this.c});

  @override
  Widget build(BuildContext context) {
    final pct = (c.collected / c.target * 100).round();
    return InkWell(
      onTap: () => openCampaign(context, c.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14, weight: FontWeight.w700),
                  ),
                ),
                Text('$pct%', style: dashBody(size: 14, weight: FontWeight.w700, color: DashSeverity.ok.color)),
              ],
            ),
            const SizedBox(height: 5),
            DashProgress(
              fraction: c.collected / c.target,
              color: AppColors.greenrspwn,
              semanticsLabel: '${formatPeso(c.collected)} of ${formatPeso(c.target)}',
            ),
            const SizedBox(height: 3),
            Text(
              '${formatPeso(c.target - c.collected)} to go'
                  '${c.endDate == null ? '' : ' · ${plural(c.daysRemaining, 'day')} left'}',
              style: dashMuted(),
            ),
          ],
        ),
      ),
    );
  }
}
