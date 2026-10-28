import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_alerts.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/rescue_readiness.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/donation/models.dart';

/// The "Today" tab: what needs action now, whether the shelter can take
/// another rescue, and the state of care, adoption and funds.
class TodayView extends StatelessWidget {
  final GlobalKey? priorityKey;
  const TodayView({super.key, this.priorityKey});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlanceCard(),
        const SizedBox(height: 14),
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
        const RecentActivityCard(),
      ],
    );
  }
}

// ─── Today at a glance ───────────────────────────────────────────────────

class _Tile {
  final IconData icon;
  final String value;
  final String label;
  final ChipTone? tone;
  final VoidCallback? onTap;
  const _Tile(this.icon, this.value, this.label, {this.tone, this.onTap});
}

class GlanceCard extends ConsumerWidget {
  const GlanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occ = ref.watch(shelterOccupancyProvider).asData?.value;
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final pending = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.pending))).asData?.value;
    final approved = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved))).asData?.value;
    final adopted = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted))).asData?.value;
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final payments = canManage ? ref.watch(paymentAttemptsProvider).asData?.value : null;
    final campaigns = ref.watch(adminCampaignsProvider).asData?.value;

    String n(int? v) => v == null ? '—' : '$v';
    ChipTone? warnIf(int? v) => (v ?? 0) > 0 ? ChipTone.amber : null;

    final urgent = snap?.all.where((c) => UrgencyLevel.fromFirestoreValue(c.urgency) == UrgencyLevel.critical).length;
    final returns = adopted == null ? null : activeReturnsIn(adopted).length;
    final toVerify = payments?.where((p) => p.status == 'needs_review').length;
    final active = campaigns?.where((c) => !c.isDraft && !c.isArchived && !c.isEnded && c.status == 'active').toList();
    final gap = active?.fold<double>(0, (s, c) => s + (c.target > c.collected ? c.target - c.collected : 0));
    final supplies = campaigns == null
        ? null
        : [
      for (final c in campaigns.where((c) => !c.isDraft && !c.isArchived && !c.isEnded))
        for (final i in c.inKindItems)
          if ((i.quantityRemaining ?? 0) > 0) i,
    ].length;
    final free = occ?.free;

    return OutlinedCard(
      title: 'Today at a glance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GlanceGroup(
            icon: Icons.sos,
            name: 'Rescue',
            onOpen: () => openRescueTab(context, ref, RescuePipelineTab.review),
            tiles: [
              // Capacity first, then urgent rescues, then the rest.
              _Tile(
                Icons.house,
                occ == null ? '—' : (free == null ? 'Set' : '${free < 0 ? 0 : free}'),
                free == null ? 'Capacity not set' : 'Spaces free',
                tone: free != null && free <= 0 ? ChipTone.red : null,
                onTap: free == null ? () => showShelterSetupSheet(context) : null,
              ),
              _Tile(
                Icons.sos,
                n(urgent),
                'Urgent rescues',
                tone: (urgent ?? 0) > 0 ? ChipTone.red : null,
                onTap: () => openRescueTab(context, ref, RescuePipelineTab.review),
              ),
              _Tile(
                Icons.fact_check,
                n(snap?.count(RescueStage.review)),
                'Unverified reports',
                tone: warnIf(snap?.count(RescueStage.review)),
                onTap: () => openRescueTab(context, ref, RescuePipelineTab.review),
              ),
              _Tile(
                Icons.medication,
                n(occ?.atVet),
                'Need medical care',
                tone: warnIf(occ?.atVet),
                onTap: () => openRescueTab(context, ref, RescuePipelineTab.treatment),
              ),
            ],
          ),
          _GlanceGroup(
            icon: Icons.favorite,
            name: 'Adoption',
            onOpen: () => openAdoptionQueue(context, AdoptionStatus.pending),
            tiles: [
              _Tile(
                Icons.assignment_ind,
                n(pending?.length),
                'Applications to review',
                onTap: () => openAdoptionQueue(context, AdoptionStatus.pending),
              ),
              _Tile(
                Icons.home,
                n(approved?.length),
                'Handovers due',
                onTap: () => openAdoptionQueue(context, AdoptionStatus.approved),
              ),
              _Tile(
                Icons.assignment_return,
                n(returns),
                'Return requests',
                tone: warnIf(returns),
                onTap: () => openAdoptionQueue(context, AdoptionStatus.adopted),
              ),
            ],
          ),
          _GlanceGroup(
            icon: Icons.volunteer_activism,
            name: 'Donation',
            onOpen: () => openDonationsAdmin(context),
            last: true,
            tiles: [
              canManage
                  ? _Tile(
                Icons.payments,
                n(toVerify),
                'Donations to verify',
                tone: warnIf(toVerify),
                onTap: () => openDonationsAdmin(context),
              )
                  : const _Tile(Icons.lock, '—', 'Donations to verify (admins)'),
              _Tile(
                Icons.campaign,
                gap == null ? '—' : _shortPeso(gap),
                'Campaign gap',
                onTap: () => openDonationsAdmin(context),
              ),
              _Tile(
                Icons.inventory_2,
                n(supplies),
                'Supplies needed',
                tone: warnIf(supplies),
                onTap: () => openDonationsAdmin(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _shortPeso(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '₱${k >= 100 ? k.round() : k.toStringAsFixed(1)}k';
  }
  return formatPeso(v);
}

class _GlanceGroup extends StatelessWidget {
  final IconData icon;
  final String name;
  final List<_Tile> tiles;
  final VoidCallback onOpen;
  final bool last;
  const _GlanceGroup({
    required this.icon,
    required this.name,
    required this.tiles,
    required this.onOpen,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final line = AppColors.textPrimary.withValues(alpha: 0.14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0E4),
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textPrimary),
                const SizedBox(width: 7),
                Expanded(child: Text(name, style: dashTitle(13.5))),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.textPrimary, width: 1.3)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < tiles.length; i++)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: i == tiles.length - 1 ? null : Border(right: BorderSide(color: line)),
                      ),
                      child: _GlanceTile(tile: tiles[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GlanceTile extends StatelessWidget {
  final _Tile tile;
  const _GlanceTile({required this.tile});

  @override
  Widget build(BuildContext context) {
    final color = switch (tile.tone) {
      ChipTone.red => DashSeverity.critical.color,
      ChipTone.amber => DashSeverity.warning.color,
      _ => AppColors.textPrimary,
    };
    return Semantics(
      button: tile.onTap != null,
      label: '${tile.label}: ${tile.value}',
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 9),
          child: Column(
            children: [
              Icon(tile.icon, size: 19, color: AppColors.textSecondary),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tile.value, style: GoogleFonts.tiltWarp(fontSize: 21, color: color, height: 1)),
              ),
              const SizedBox(height: 3),
              Text(
                tile.label,
                textAlign: TextAlign.center,
                style: dashBody(size: 12, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Priority actions ────────────────────────────────────────────────────

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
    final shown = _all ? filtered : filtered.take(6).toList();

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
          if (filtered.length > 6)
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = alert.severity.color;
    final subtitle = [alert.subject, alert.status].whereType<String>().join(' · ');
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
                    if (alert.timing != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: StatusChip(
                          alert.timing!,
                          tone: alert.timing!.startsWith('Overdue') ? ChipTone.red : ChipTone.info,
                          icon: alert.timing!.startsWith('Overdue') ? Icons.error_outline : Icons.schedule,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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

// ─── Rescue (reference card) ─────────────────────────────────────────────

class RescueSummaryCard extends ConsumerWidget {
  const RescueSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(dashboardRescueSnapshotProvider);
    final supply = ref.watch(transportSupplyProvider).asData?.value;

    return SectionCard(
      icon: Icons.sos,
      title: 'Rescue',
      onOpen: () => openRescueTab(context, ref, RescuePipelineTab.review),
      padding: EdgeInsets.zero,
      child: DashAsync<RescueSnapshot>(
        value: snapAsync,
        what: 'rescue cases',
        builder: (snap) {
          final urgent = snap.all
              .where((c) => UrgencyLevel.fromFirestoreValue(c.urgency) == UrgencyLevel.critical)
              .length;
          // Current wait = time since the clinic was chosen for cases still
          // waiting for a rider. Uses recorded timestamps only.
          final waits = snap
              .of(RescueStage.transporter)
              .map((c) => c.vetClinicSelectedAt ?? c.createdAt)
              .whereType<DateTime>()
              .map((t) => DateTime.now().difference(t).inMinutes / 60)
              .toList();
          final avgWait = waits.isEmpty ? null : waits.reduce((a, b) => a + b) / waits.length;
          final line = AppColors.textPrimary.withValues(alpha: 0.14);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BigStat(
                        value: '$urgent',
                        label: 'Urgent',
                        color: urgent > 0 ? DashSeverity.critical.color : null,
                        onTap: () => openRescueTab(context, ref, RescuePipelineTab.review),
                      ),
                    ),
                    Expanded(
                      child: BigStat(value: '${snap.all.length}', label: 'Active cases'),
                    ),
                    Expanded(
                      child: BigStat(
                        value: '${snap.count(RescueStage.review)}',
                        label: 'Awaiting verification',
                        color: snap.count(RescueStage.review) > 0 ? DashSeverity.warning.color : null,
                        onTap: () => openRescueTab(context, ref, RescuePipelineTab.review),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 9, 8, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SubStat(supply == null ? '—' : '${supply.onAssignment}', 'on a ride'),
                    _SubStat(supply == null ? '—' : '${supply.free}', 'riders free'),
                    _SubStat(avgWait == null ? '0' : '${avgWait.round()}h', 'avg wait now'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  final String value;
  final String label;
  const _SubStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
          ),
          TextSpan(text: label, style: dashMuted(12.5)),
        ],
      ),
    );
  }
}

// ─── Shelter care ────────────────────────────────────────────────────────

class ShelterCareCard extends ConsumerWidget {
  const ShelterCareCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);
    final vaxAsync = ref.watch(vaccinationsByAnimalProvider);
    final vax = vaxAsync.asData?.value;

    final inCare = (recordsAsync.asData?.value ?? const <AnimalRecord>[]).where(isInCare).toList();
    final statuses = {for (final a in inCare) a.id: vax == null ? null : healthStatusOf(vax[a.id])};
    int count(HealthRecordStatus s) => statuses.values.where((v) => v == s).length;
    final overdue = count(HealthRecordStatus.overdue);

    return SectionCard(
      icon: Icons.monitor_heart,
      title: 'Shelter care',
      onOpen: () => openAnimalRecords(context),
      trailing: overdue > 0
          ? Padding(
        padding: const EdgeInsets.only(right: 6),
        child: StatusChip('$overdue overdue', tone: ChipTone.red, icon: Icons.error_outline),
      )
          : null,
      child: DashAsync<List<AnimalRecord>>(
        value: recordsAsync,
        what: 'animal records',
        builder: (_) {
          final total = inCare.length;
          int pct(int n) => total == 0 ? 0 : (n * 1000 / total).round();
          final attention = [...inCare]
            ..sort((a, b) => _attentionRank(a, statuses[a.id]).compareTo(_attentionRank(b, statuses[b.id])));
          final top = attention.where((a) => _attentionRank(a, statuses[a.id]) < 4).take(3).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardLabel('Today’s care'),
              const _NotTrackedRow(
                icon: Icons.restaurant,
                text: 'Feeding, water, cleaning and medication rounds aren’t recorded as tasks yet.',
              ),
              const SizedBox(height: 6),
              const _NotTrackedRow(
                icon: Icons.videocam,
                text: 'Carer videos are attached to treatment updates on each case, not collected here yet.',
              ),
              CardLabel('Health records · ${plural(total, 'animal')} in care'),
              if (vax == null && vaxAsync.isLoading)
                const DashLoading(label: 'Loading vaccinations…')
              else if (vaxAsync.hasError)
                DashError(what: 'vaccination records', error: vaxAsync.error!)
              else if (total == 0)
                  const DashEmpty('No animals in care.', severity: DashSeverity.info)
                else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 12,
                        child: Row(
                          children: [
                            for (final (s, color) in [
                              (HealthRecordStatus.completed, DashSeverity.ok.color),
                              (HealthRecordStatus.dueSoon, DashSeverity.warning.color),
                              (HealthRecordStatus.overdue, DashSeverity.critical.color),
                              (HealthRecordStatus.notRecorded, const Color(0xFFD7D4CB)),
                            ])
                              if (count(s) > 0)
                                Expanded(
                                  flex: pct(count(s)),
                                  child: Container(color: color, margin: const EdgeInsets.only(right: 2)),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        StatusChip(
                          'Up to date ${count(HealthRecordStatus.completed)}',
                          tone: ChipTone.green,
                          icon: Icons.check,
                        ),
                        StatusChip(
                          'Due ≤$kDueSoonDays d ${count(HealthRecordStatus.dueSoon)}',
                          tone: ChipTone.amber,
                          icon: Icons.schedule,
                        ),
                        StatusChip('Overdue $overdue', tone: ChipTone.red, icon: Icons.error_outline),
                        StatusChip('Not recorded ${count(HealthRecordStatus.notRecorded)}', tone: ChipTone.notRecorded),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Based on vaccination records. “Not recorded” never means “not given”.',
                        style: dashMuted(),
                      ),
                    ),
                    for (final a in top) _AnimalAttentionRow(animal: a, status: statuses[a.id], vax: vax?[a.id]),
                  ],
            ],
          );
        },
      ),
    );
  }

  static int _attentionRank(AnimalRecord a, HealthRecordStatus? s) {
    if (s == HealthRecordStatus.overdue) return 0;
    if (hasOpenMedicalCase(a)) return 1;
    if ((a.health.currentMedications ?? '').trim().isNotEmpty || s == HealthRecordStatus.dueSoon) return 2;
    if (s == HealthRecordStatus.notRecorded) return 3;
    return 9;
  }
}

class _NotTrackedRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _NotTrackedRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: dashMuted(12.5))),
        const SizedBox(width: 6),
        const StatusChip('Not tracked yet', tone: ChipTone.notRecorded),
      ],
    );
  }
}

class _AnimalAttentionRow extends StatelessWidget {
  final AnimalRecord animal;
  final HealthRecordStatus? status;
  final List<VaccinationRecord>? vax;
  const _AnimalAttentionRow({required this.animal, required this.status, required this.vax});

  @override
  Widget build(BuildContext context) {
    final due = nextVaccineDue(vax);
    final chips = <Widget>[
      if (status == HealthRecordStatus.overdue)
        StatusChip('Vaccine overdue${due == null ? '' : ' · ${shortDate(due)}'}', tone: ChipTone.red),
      if (status == HealthRecordStatus.dueSoon && due != null)
        StatusChip('Vaccine due ${shortDate(due)}', tone: ChipTone.amber),
      if (hasOpenMedicalCase(animal)) const StatusChip('In treatment', tone: ChipTone.amber),
      if ((animal.health.currentMedications ?? '').trim().isNotEmpty)
        const StatusChip('On medication', tone: ChipTone.amber),
      if (status == HealthRecordStatus.notRecorded)
        const StatusChip('Vaccines not recorded', tone: ChipTone.notRecorded),
    ];
    return InkWell(
      onTap: () => openAnimalRecord(context, animal),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
        ),
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
                  Wrap(spacing: 4, runSpacing: 4, children: chips),
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

// ─── Adoption ────────────────────────────────────────────────────────────

class AdoptionSummaryCard extends ConsumerWidget {
  const AdoptionSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(allAnimalRecordsProvider).asData?.value;
    final pending = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.pending)));
    final interview =
        ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.interview))).asData?.value ?? const [];
    final approved =
        ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved))).asData?.value ?? const [];

    final inCare = (records ?? const <AnimalRecord>[]).where(isInCare).toList();
    final available = records == null ? null : inCare.where((a) => a.isAdoptable).length;
    final awaiting = records == null
        ? null
        : inCare.where((a) => a.adoptionStatus == 'not_ready' && !hasOpenMedicalCase(a)).length;
    final listedWithGaps = inCare.where((a) => a.isAdoptable && readinessGaps(a) > 0).toList()
      ..sort((a, b) => readinessGaps(b).compareTo(readinessGaps(a)));

    return SectionCard(
      icon: Icons.favorite,
      title: 'Adoption',
      onOpen: () => openAdoptionQueue(context, AdoptionStatus.pending),
      child: DashAsync<List<AdoptionApplication>>(
        value: pending,
        what: 'applications',
        builder: (pendingApps) {
          final epoch = DateTime.fromMillisecondsSinceEpoch(0);
          final queue = [
            ...([...pendingApps]..sort((a, b) => (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch))),
            ...interview,
            ...approved,
          ].take(4).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BigStat(
                      value: available == null ? '—' : '$available',
                      label: 'Available',
                      onTap: () => openAnimalRecords(context),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: awaiting == null ? '—' : '$awaiting',
                      label: 'Awaiting assessment',
                      color: (awaiting ?? 0) > 0 ? DashSeverity.warning.color : null,
                      onTap: () => openAnimalRecords(context),
                    ),
                  ),
                  Expanded(
                    child: BigStat(
                      value: '${pendingApps.length}',
                      label: 'Applications to review',
                      onTap: () => openAdoptionQueue(context, AdoptionStatus.pending),
                    ),
                  ),
                ],
              ),
              if (queue.isEmpty)
                const DashEmpty('No applications waiting.')
              else
                for (final app in queue) _ApplicationRow(app: app),
              if (listedWithGaps.isNotEmpty) ...[
                CardLabel(
                  'Readiness · ${listedWithGaps.first.name.isEmpty ? listedWithGaps.first.species : listedWithGaps.first.name}',
                ),
                InkWell(
                  onTap: () => openAnimalRecord(context, listedWithGaps.first),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final item in readinessItemsFor(listedWithGaps.first))
                        StatusChip(
                          item.label,
                          tone: item.done == true
                              ? ChipTone.green
                              : (item.done == false ? ChipTone.amber : ChipTone.notRecorded),
                          icon: item.done == true
                              ? Icons.check
                              : (item.done == false ? Icons.close : Icons.question_mark),
                        ),
                      if ((listedWithGaps.first.health.currentMedications ?? '').trim().isNotEmpty)
                        const StatusChip('On meds · disclose', tone: ChipTone.amber, icon: Icons.medication),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
        ),
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
        child: StatusChip('Admins only', tone: ChipTone.ink, icon: Icons.lock),
      )
          : null,
      child: canManageAsync.isLoading
          ? const DashLoading()
          : (!canManage
          ? const RestrictedNotice(
        'Fund balances, donation records and bills are visible to authorized admins only.',
      )
          : const _FundsBody()),
    );
  }
}

class _FundsBody extends ConsumerWidget {
  const _FundsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentAttemptsProvider).asData?.value;
    final donations = ref.watch(allDonationsProvider).asData?.value;
    final campaignsAsync = ref.watch(adminCampaignsProvider);
    final expenses = ref.watch(allCaseExpensesProvider);

    final since = DateTime.now().subtract(const Duration(days: 30));
    final pendingList = payments?.where((p) => p.status == 'needs_review' || p.status == 'pending').toList();
    final pendingSum = pendingList?.fold<double>(0, (s, p) => s + p.amount);
    final verified = donations
        ?.where((d) => !d.isInKind && d.when != null && d.when!.isAfter(since))
        .fold<double>(0, (s, d) => s + d.amountValue);

    return DashAsync<List<DonationListing>>(
      value: campaignsAsync,
      what: 'campaigns',
      builder: (all) {
        final live = all.where((c) => !c.isDraft && !c.isArchived && c.status != 'closed').toList();
        double bal(Iterable<DonationListing> l) =>
            l.fold(0, (s, c) => s + (c.availableBalance > 0 ? c.availableBalance : 0));
        final general = bal(live.where((c) => !c.restricted));
        final restricted = bal(live.where((c) => c.restricted));
        final campaigns = live.where((c) => c.target > 0).toList()
          ..sort((a, b) => (b.collected / b.target).compareTo(a.collected / a.target));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CardLabel('Donations · last 30 days'),
            Row(
              children: [
                Expanded(
                  child: BigStat(
                    value: pendingSum == null ? '—' : _shortPeso(pendingSum),
                    label: 'Pending (${pendingList?.length ?? '—'})',
                    color: (pendingSum ?? 0) > 0 ? DashSeverity.warning.color : null,
                  ),
                ),
                Expanded(
                  child: BigStat(value: verified == null ? '—' : _shortPeso(verified), label: 'Recorded'),
                ),
              ],
            ),
            const CardLabel('Available funds · verified only'),
            if (general + restricted > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      if (general > 0)
                        Expanded(
                          flex: general.round(),
                          child: Container(color: AppColors.textPrimary),
                        ),
                      if (restricted > 0) ...[
                        const SizedBox(width: 2),
                        Expanded(
                          flex: restricted.round(),
                          child: Container(color: AppColors.lavenderrspwn),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                LegendText(AppColors.textPrimary, 'General ${formatPeso(general)}'),
                LegendText(
                  AppColors.lavenderrspwn,
                  'Restricted ${formatPeso(restricted)}',
                  style: dashBody(size: 12.5, weight: FontWeight.w700, color: const Color(0xFF5D68C9)),
                ),
                if ((pendingSum ?? 0) > 0)
                  Text('Pending ${formatPeso(pendingSum!)} not counted', style: dashMuted(12.5)),
              ],
            ),
            if (campaigns.isNotEmpty) const CardLabel('Campaigns'),
            for (final c in campaigns.take(2)) _CampaignRow(c: c),
            const CardLabel('Obligations'),
            ...expenses.when(
              data: (list) {
                const vetCats = {
                  ExpenseCategory.consultation,
                  ExpenseCategory.medication,
                  ExpenseCategory.procedure,
                  ExpenseCategory.laboratory,
                  ExpenseCategory.vaccination,
                  ExpenseCategory.confinement,
                };
                final unfunded = list.where((e) => e.fundingSource == FundingSource.unfunded);
                final vet = unfunded.where((e) => vetCats.contains(e.category)).fold<double>(0, (s, e) => s + e.amount);
                final transport = unfunded
                    .where((e) => e.category == ExpenseCategory.transport)
                    .fold<double>(0, (s, e) => s + e.amount);
                final missing = list.where((e) => (e.receiptUrl ?? '').isEmpty).length;
                return [
                  _KvRow(
                    Icons.local_hospital,
                    'Unfunded vet bills',
                    Text(formatPeso(vet), style: GoogleFonts.tiltWarp(fontSize: 15)),
                    first: true,
                  ),
                  _KvRow(
                    Icons.local_shipping,
                    'Unfunded transport',
                    Text(formatPeso(transport), style: GoogleFonts.tiltWarp(fontSize: 15)),
                  ),
                  _KvRow(
                    Icons.receipt_long,
                    'Missing receipts',
                    StatusChip('$missing', tone: missing > 0 ? ChipTone.amber : ChipTone.green),
                  ),
                  const _KvRow(
                    Icons.pending_actions,
                    'Payments awaiting approval',
                    StatusChip('Not tracked yet', tone: ChipTone.notRecorded),
                  ),
                ];
              },
              loading: () => [const DashLoading(label: 'Loading expenses…')],
              error: (e, _) => [DashError(what: 'expenses', error: e)],
            ),
          ],
        );
      },
    );
  }
}

class _CampaignRow extends StatelessWidget {
  final DonationListing c;
  const _CampaignRow({required this.c});

  @override
  Widget build(BuildContext context) {
    final pct = (c.collected / c.target * 100).round();
    final over = c.collected >= c.target;
    final note = over
        ? '${formatPeso(c.collected - c.target)} above target · ${c.restricted ? 'stays with its stated purpose' : 'reconcile before reuse'}'
        : '${formatPeso(c.target - c.collected)} short${c.linkedCaseId != null ? ' · urgent care may proceed from general funds' : ''}';
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
                Text(
                  '$pct%',
                  style: dashBody(
                    size: 14,
                    weight: FontWeight.w700,
                    color: over ? DashSeverity.ok.color : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            DashProgress(
              fraction: c.collected / c.target,
              color: over ? DashSeverity.ok.color : AppColors.greenrspwn,
              semanticsLabel: '${formatPeso(c.collected)} of ${formatPeso(c.target)}',
            ),
            const SizedBox(height: 3),
            Text(note, style: dashMuted()),
          ],
        ),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final bool first;
  const _KvRow(this.icon, this.label, this.value, {this.first = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: dashBody(size: 14, weight: FontWeight.w700)),
          ),
          value,
        ],
      ),
    );
  }
}

// ─── Recent activity ─────────────────────────────────────────────────────

class _Event {
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime time;
  final void Function(BuildContext) open;
  const _Event(this.icon, this.title, this.subtitle, this.time, this.open);
}

/// Built from timestamps already on loaded records (case reports,
/// treatment updates, adoption decisions, donations) — no generated
/// entries and no extra query.
class RecentActivityCard extends ConsumerWidget {
  const RecentActivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final approved =
        ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved))).asData?.value ?? const [];
    final adopted =
        ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted))).asData?.value ?? const [];
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final donations = canManage ? ref.watch(recentDonationsProvider).asData?.value : null;

    String animalOf(RescueCase c) => c.speciesSummary.isEmpty ? 'Animal' : c.speciesSummary;
    final events = <_Event>[
      for (final c in snap?.all ?? const <RescueCase>[])
        if (c.createdAt != null)
          _Event(
            Icons.sos,
            'New report · ${animalOf(c)}${c.address == null ? '' : ', ${c.address!.split(',').first}'}',
            c.reporterName ?? 'Community reporter',
            c.createdAt!,
                (ctx) => openRescueCase(ctx, c),
          ),
      for (final c in snap?.of(RescueStage.treatment) ?? const <RescueCase>[])
        if (c.treatmentUpdatedAt != null)
          _Event(
            Icons.healing,
            'Treatment update · ${animalOf(c)} #${c.shortCaseId}',
            [c.latestTreatmentUpdateType, c.vetClinicName].whereType<String>().join(' · '),
            c.treatmentUpdatedAt!,
                (ctx) => openTreatment(ctx, c),
          ),
      for (final a in approved)
        if (a.approvedAt != null)
          _Event(
            Icons.check,
            'Application approved · ${a.animalName}',
            a.adopterName,
            a.approvedAt!,
                (ctx) => openApplication(ctx, a),
          ),
      for (final a in adopted)
        if (a.adoptedAt != null)
          _Event(
            Icons.home,
            'Adopted · ${a.animalName}',
            a.adopterName,
            a.adoptedAt!,
                (ctx) => openApplication(ctx, a),
          ),
      for (final d in donations ?? const [])
        if (d.when != null)
          _Event(
            Icons.payments,
            d.isInKind ? 'In-kind donation recorded' : 'Donation ${formatPeso(d.amountValue)} recorded',
            d.campaignName.isEmpty ? d.displayName : d.campaignName,
            d.when!,
                (ctx) => openDonationsAdmin(ctx),
          ),
    ]..sort((a, b) => b.time.compareTo(a.time));

    return SectionCard(
      icon: Icons.history,
      title: 'Recent activity',
      child: events.isEmpty
          ? (snap == null
          ? const DashLoading()
          : const DashEmpty('No recent activity recorded.', severity: DashSeverity.info))
          : Column(children: [for (final e in events.take(5)) _EventRow(e: e)]),
    );
  }
}

class _EventRow extends StatelessWidget {
  final _Event e;
  const _EventRow({required this.e});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => e.open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: AppColors.tearspwn, shape: BoxShape.circle),
              child: Icon(e.icon, size: 15, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14, weight: FontWeight.w700),
                  ),
                  Text('${e.subtitle.isEmpty ? '' : '${e.subtitle} · '}${elapsedSince(e.time)}', style: dashMuted()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
