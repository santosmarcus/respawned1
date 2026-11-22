import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart' show plural, shortDate, DashSeverity;
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/core/utils/org_list_scope.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/adoption_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/finance_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/rescue_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// Module analytics (RESPAWND_ANALYTICS_PLAN, Phase 3): Rescue, Adoption and
/// Donations & funds cards added to the existing Analytics column, in its
/// card style. The figures come from the pure calculators in metrics/;
/// these widgets only load and show them. Every rate shows its fraction,
/// groups under [kMinGroupSize] show the fraction only, and a figure with
/// nothing recorded says so instead of showing 0.

// ─── Data ─────────────────────────────────────────────────────────────────

Map<String, dynamic> _caseDoc(RescueCase c) => {...c.raw, 'id': c.id};

/// The organization's transport offers (stamped with organizationId).
final orgTransportOffersProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance.collectionGroup('transportAssignments'),
    empty: const <Map<String, dynamic>>[],
    (snap) => [
      for (final d in snap.docs) {...d.data(), 'caseId': d.data()['caseId'] ?? d.reference.parent.parent?.id},
    ],
  );
});

/// Every follow-up of the organization's adoptions. Filtering on all the
/// statuses uses the existing (organizationId, status) index.
final orgFollowUpsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance
        .collectionGroup('followUps')
        .where('status', whereIn: [for (final s in FollowUpStatus.values) s.name]),
    empty: const <Map<String, dynamic>>[],
    (snap) => [for (final d in snap.docs) d.data()],
  );
});

/// The last 60 daily snapshots (snapshotDailyAnalytics), oldest first.
final analyticsSnapshotsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final orgId = await ref.watch(dashboardOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('organizations')
      .doc(orgId)
      .collection('analyticsSnapshots')
      .orderBy('day', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList().reversed.toList());
});

/// The organization's stock movements (in-kind received and used).
final stockMovementsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final orgId = await ref.watch(dashboardOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('organizations')
      .doc(orgId)
      .collection('stockMovements')
      .orderBy('at', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());
});

// ─── Shared bits ──────────────────────────────────────────────────────────

String _minutes(double? m) {
  if (m == null) return '—';
  if (m < 90) return '${m.round()} min';
  if (m < 48 * 60) return '${(m / 60).toStringAsFixed(1)} h';
  return '${(m / 1440).toStringAsFixed(1)} days';
}

String _days(double? d) => d == null ? '—' : '${d.toStringAsFixed(d < 10 ? 1 : 0)} days';

/// A rate as the big figure, or the fraction when the group is small.
class _Rate extends StatelessWidget {
  const _Rate(this.f, this.caption, {this.emptyText});
  final Fraction f;
  final String caption;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (f.whole == 0) return Text(emptyText ?? 'Nothing recorded in this period.', style: dashBody(size: 14, weight: FontWeight.w700));
    final pct = f.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(pct ?? f.text, style: GoogleFonts.tiltWarp(fontSize: 30, color: AppColors.textPrimary, height: 1)),
            const SizedBox(width: 8),
            Expanded(child: Text(caption, style: dashBody(size: 14, weight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 4),
        Text(pct == null ? 'Too few for a rate (fewer than $kMinGroupSize).' : f.text, style: dashMuted()),
      ],
    );
  }
}

/// One labelled bar: [count] out of [total].
class _BarRow extends StatelessWidget {
  const _BarRow(this.label, this.valueText, this.share, {this.note, this.color = AppColors.greenrspwn});
  final String label;
  final String valueText;
  final double share;
  final String? note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: dashBody(weight: FontWeight.w600))),
              Text(valueText, style: dashBody(weight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 3),
          DashProgress(fraction: share, semanticsLabel: '$label $valueText', color: color),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note!, style: dashMuted(11.5))),
        ],
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

Widget _gap([double h = 14]) => SizedBox(height: h);

/// A small line of daily values (snapshots), or nothing when there are
/// fewer than two days.
class _Trend extends StatelessWidget {
  const _Trend(this.values, this.label);
  final List<double> values;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: dashMuted()),
          const SizedBox(height: 4),
          SizedBox(
            height: 56,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
                    color: AppColors.textPrimary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading / error handling shared by the three sections.
Widget _whenAll(List<AsyncValue<Object?>> values, String what, Widget Function() build) {
  for (final v in values) {
    if (v.hasError) return DashError(what: what, error: v.error!);
  }
  if (values.any((v) => !v.hasValue)) return DashLoading(label: 'Loading $what…');
  return build();
}

// ─── Rescue ───────────────────────────────────────────────────────────────

class RescueModuleCards extends ConsumerWidget {
  const RescueModuleCards({super.key, required this.period, required this.cases});
  final Period period;
  final List<RescueCase> cases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(orgTransportOffersProvider);
    final occ = ref.watch(shelterOccupancyProvider).asData?.value;
    final snapshots = ref.watch(analyticsSnapshotsProvider).asData?.value ?? const [];
    final docs = cases.map(_caseDoc).toList();
    return _whenAll([offersAsync], 'transport offers', () {
      final offers = offersAsync.requireValue;
      final referrals = referralsIn(period, docs);
      final retrieved = retrievalsIn(period, docs, offers);
      final offerStats = offerStatsIn(period, offers, docs);
      final exits = treatmentExitsIn(period, docs);
      final times = responseTimesIn(period, docs);
      final intake = intakeVolumeIn(period, docs);
      final retrievedTotal = retrieved.values.fold(0, (a, b) => a + b);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashSubheading('Rescue'),
          OutlinedCard(
            title: 'Reports and how many are finished',
            child: _CardBody([
              _Rate(intake.resolved, 'of reports from this period are finished',
                  emptyText: 'No reports came in during this period.'),
              for (final e in intake.byUrgency.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                _BarRow(e.key, '${e.value}', intake.received == 0 ? 0 : e.value / intake.received),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Where did cases go instead of our care?',
            child: _CardBody([
              if (referrals.trackingSince == null)
                Text('Review decisions are dated from this update on, so there is nothing to measure yet.',
                    style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                _Rate(referrals.rate, 'of decided cases were referred or declined',
                    emptyText: 'No case was decided in this period.'),
                for (final k in ReferralKind.values)
                  if (referrals.counts[k]! > 0)
                    _BarRow(k.label, '${referrals.counts[k]}', referrals.referred == 0 ? 0 : referrals.counts[k]! / referrals.referred),
                if (referrals.referred > 0) ...[
                  _gap(10),
                  Text(
                    'Because the shelter was full: ${referrals.capacityShare.text}'
                    '${referrals.capacityShare.percent == null ? '' : ' (${referrals.capacityShare.percent})'}.',
                    style: dashBody(weight: FontWeight.w700),
                  ),
                ],
                if (period.from.isBefore(referrals.trackingSince!))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Tracking started ${shortDate(referrals.trackingSince!)}; earlier decisions aren\'t counted.',
                        style: dashMuted()),
                  ),
                const SizedBox(height: 4),
                Text('A referral is counted when it is made; what happens after is up to who took it.', style: dashMuted()),
              ],
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Who brings the animals in?',
            child: _CardBody([
              if (retrievedTotal == 0)
                Text('No animal was retrieved in this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                _Rate(Fraction(retrieved[RetrievedBy.transporter]!, retrievedTotal), 'of retrievals were by pet transporters'),
                for (final k in RetrievedBy.values)
                  _BarRow(k.label, '${retrieved[k]}', retrieved[k]! / retrievedTotal),
                const SizedBox(height: 4),
                Text('Each case counts once, even with several transport legs.', style: dashMuted()),
              ],
              _gap(),
              CardLabel('Transport offers'),
              _Rate(offerStats.acceptance, 'of offers were accepted', emptyText: 'No transport offer was sent in this period.'),
              if (!offerStats.minutesToAccept.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Median time to accept: ${_minutes(offerStats.minutesToAccept.value)} '
                    '(${plural(offerStats.minutesToAccept.count, 'offer')}).',
                    style: dashBody(weight: FontWeight.w600),
                  ),
                ),
              _gap(8),
              MetricGrid(tiles: [
                MetricTile(label: 'No transporter took it', value: offerStats.casesWithNoTaker, caption: 'every offer declined or expired'),
                MetricTile(label: 'Declined: no riders', value: offerStats.declinedNoRiders, caption: 'reports turned away'),
              ]),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Treatment',
            child: _CardBody([
              if (occ == null)
                const SizedBox.shrink()
              else if (occ.capacity == null)
                Text('${plural(occ.atVet, 'animal')} in treatment now. Set the shelter capacity in Shelter settings to see the load.',
                    style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${occ.atVet} of ${occ.capacity}',
                        style: GoogleFonts.tiltWarp(fontSize: 30, color: AppColors.textPrimary, height: 1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('in treatment, against the shelter capacity (${(occ.atVet * 100 / occ.capacity!).round()}%)',
                          style: dashBody(size: 14, weight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DashProgress(fraction: occ.atVet / occ.capacity!, semanticsLabel: 'Treatment load'),
              ],
              _Trend([for (final s in snapshots) ((s['inTreatment'] as num?) ?? 0).toDouble()],
                  'In treatment, day by day (last ${snapshots.length} days)'),
              _gap(),
              CardLabel('Leaving treatment in this period'),
              _Rate(exits.recoveredShare, 'recovered', emptyText: 'No animal left treatment in this period.'),
              for (final k in TreatmentExit.values)
                if (exits.counts[k]! > 0)
                  _BarRow(k.label, '${exits.counts[k]}', exits.counts[k]! / exits.total,
                      color: k == TreatmentExit.died ? DashSeverity.critical.color : AppColors.greenrspwn),
              if (!exits.days.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Median time in treatment: ${_days(exits.days.value)} (${plural(exits.days.count, 'animal')}).',
                      style: dashBody(weight: FontWeight.w600)),
                ),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'How fast do we respond?',
            child: _CardBody([
              for (final (label, m) in [
                ('Report → accepted', times.reportToAccepted),
                ('Accepted → picked up', times.acceptedToPickup),
                ('Picked up → at the clinic', times.pickupToClinic),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: dashBody(weight: FontWeight.w600))),
                      Text(m.isEmpty ? 'Not recorded yet' : '${_minutes(m.value)} · ${plural(m.count, 'case')}',
                          style: dashBody(weight: m.isEmpty ? FontWeight.w500 : FontWeight.w800)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text('Medians. These times are recorded from this update on.', style: dashMuted()),
            ]),
          ),
          _gap(),
        ],
      );
    });
  }
}

// ─── Adoption ─────────────────────────────────────────────────────────────

class AdoptionModuleCards extends ConsumerWidget {
  const AdoptionModuleCards({super.key, required this.period, required this.adopted, required this.intake});
  final Period period;

  /// Animals adopted and taken in during the period (computeOutcomes).
  final int adopted;
  final int intake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(allAdoptionsProvider);
    final followUpsAsync = ref.watch(orgFollowUpsProvider);
    return _whenAll([appsAsync, followUpsAsync], 'adoptions', () {
      final now = DateTime.now();
      final apps = [for (final a in appsAsync.requireValue) {...a.raw, 'id': a.id}];
      final checkIns = checkInsIn(period, followUpsAsync.requireValue, now);
      final cohort = adoptionCohortIn(period, apps, now);
      final reasons = returnReasonsIn(period, apps);
      final funnel = applicationFunnelIn(period, apps);
      final reasonTotal = reasons.fold(0, (a, r) => a + r.count);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashSubheading('Adoption'),
          OutlinedCard(
            title: 'Adoptions for every animal taken in',
            child: _CardBody([
              if (intake == 0)
                Text('No animal was taken in during this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text((adopted / intake).toStringAsFixed(2),
                        style: GoogleFonts.tiltWarp(fontSize: 30, color: AppColors.textPrimary, height: 1)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('adoptions per animal taken in', style: dashBody(size: 14, weight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 4),
                Text('$adopted adopted, $intake taken in. Above 1 means more animals left for homes than arrived.',
                    style: dashMuted()),
              ],
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'From application to adoption',
            child: _CardBody([
              if (funnel.applied == 0)
                Text('No application came in during this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                _BarRow('Applied', '${funnel.applied}', 1),
                _BarRow('Approved', '${funnel.approved}', funnel.approved / funnel.applied, note: funnel.approvedShare.text),
                _BarRow('Adopted', '${funnel.adopted}', funnel.adopted / funnel.applied,
                    note: '${funnel.adoptedShare.text} approved'),
                const SizedBox(height: 4),
                Text('Applications submitted in this period and how far they have got. Profile views aren\'t tracked.',
                    style: dashMuted()),
              ],
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Do adopters answer check-ins?',
            child: _CardBody([
              _Rate(checkIns.answered, 'of check-ins due were answered', emptyText: 'No check-in was due in this period.'),
              if (checkIns.answered.part > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Within $kCheckInGraceDays days of the date: ${checkIns.onTime.text}.',
                      style: dashBody(weight: FontWeight.w600)),
                ),
              _gap(8),
              MetricGrid(tiles: [
                MetricTile(
                  label: 'Overdue now',
                  value: checkIns.overdueNow,
                  caption: 'any period',
                  severity: checkIns.overdueNow > 0 ? DashSeverity.warning : null,
                ),
              ]),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Do adoptions last? Returns and why',
            child: _CardBody([
              if (cohort.measured == 0)
                Text(
                  'No adoption from this period has finished its $kAdoptionSuccessWindowDays-day window yet. '
                  'Adoptions handed over before ${shortDate(cohort.windowEndsBefore)} can be measured.',
                  style: dashBody(size: 14, weight: FontWeight.w700),
                )
              else ...[
                _Rate(cohort.success, 'stayed home past $kAdoptionSuccessWindowDays days'),
                const SizedBox(height: 4),
                Text('Returned within $kAdoptionSuccessWindowDays days: ${cohort.returnRate.text}. '
                    'Measured on ${plural(cohort.measured, 'adoption')} handed over before ${shortDate(cohort.windowEndsBefore)}.',
                    style: dashMuted()),
              ],
              _gap(),
              CardLabel('Why animals came back (returns asked in this period)'),
              if (reasons.isEmpty)
                Text('No return went ahead in this period.', style: dashBody(weight: FontWeight.w600))
              else
                for (final r in reasons)
                  _BarRow(r.reason, '${r.count}', r.count / reasonTotal, note: 'Support that might help: ${r.support}'),
            ]),
          ),
          _gap(),
        ],
      );
    });
  }
}

// ─── Donations & funds ────────────────────────────────────────────────────

DonationRow _donationRow(DonationHistoryRecord d) => DonationRow(
      amount: d.amountValue,
      type: d.type,
      status: d.status,
      source: d.source,
      method: d.method,
      at: d.when,
      category: d.category,
      quantity: d.quantityReceived,
    );

class FundsModuleCards extends ConsumerWidget {
  const FundsModuleCards({super.key, required this.period, required this.cases});
  final Period period;
  final List<RescueCase> cases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canViewFinancesProvider).asData?.value ?? false;
    if (!canView) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashSubheading('Donations & funds'),
          RestrictedNotice('Only people who can view the organization\'s finances see these figures.'),
          SizedBox(height: 14),
        ],
      );
    }
    final donationsAsync = ref.watch(allDonationsProvider);
    final caseExpensesAsync = ref.watch(allCaseExpensesProvider);
    final general = ref.watch(myGeneralExpensesProvider);
    final cashOuts = ref.watch(cashOutsProvider).asData?.value ?? const [];
    final allocations = ref.watch(orgAllocationsProvider).asData?.value ?? const [];
    final campaigns = ref.watch(orgCampaignsProvider).asData?.value ?? const [];
    final movements = ref.watch(stockMovementsProvider).asData?.value ?? const [];
    return _whenAll([donationsAsync, caseExpensesAsync], 'donations and expenses', () {
      final donations = donationsAsync.requireValue.map(_donationRow).toList();
      // General expenses are readable only by people who manage money.
      final generalExpenses = general.asData?.value ?? const <Expense>[];
      final expenses = [...caseExpensesAsync.requireValue, ...generalExpenses];
      final collected = fundsCollectedIn(period, donations);
      final spending = expensesIn(period, expenses);
      final flow = fundsFlowIn(
        period,
        donations: donations,
        cashOuts: [for (final c in cashOuts) (amount: c.amount, at: c.occurredAt ?? c.createdAt)],
        allocations: [
          for (final a in allocations)
            if (a.entry.kind == 'expense') (amount: a.entry.amount, at: a.entry.createdAt),
        ],
        expenses: expenses,
      );
      final inKind = inKindReceivedIn(period, donations);
      final usage = inKindUsageIn(period, movements);
      final progress = campaignsByProgress([
        for (final c in campaigns)
          (title: c.title, target: c.target, collected: c.collected, active: c.isActive, createdAt: c.createdAt),
      ]);
      final perAnimal = costPerAnimal(
        caseExpensesAsync.requireValue.where((e) => period.has(expenseDateOf(e))).toList(),
        {for (final c in cases) c.id: c.animalCount},
      );
      final totals = perAnimal.values.map((v) => v.paid + v.running).toList();
      final median = medianOf(totals);
      final top = perAnimal.entries.toList()
        ..sort((a, b) => (b.value.paid + b.value.running).compareTo(a.value.paid + a.value.running));
      final caseById = {for (final c in cases) c.id: c};
      String animalLabel(String key) {
        final [caseId, idx] = key.split('#');
        final c = caseById[caseId];
        final animals = c?.animals ?? const [];
        final i = int.tryParse(idx) ?? 0;
        final a = i < animals.length ? animals[i] : const <String, dynamic>{};
        final name = (a['name'] as String?)?.trim();
        final what = (name == null || name.isEmpty) ? ((a['species'] as String?) ?? 'Animal') : name;
        return c == null ? what : '$what · case #${c.shortCaseId}';
      }

      final channelMax = collected.byChannel.values.fold<double>(0, (m, v) => v.amount > m ? v.amount : m);
      final categoryEntries = spending.byCategory.entries.toList()
        ..sort((a, b) => (b.value.paid + b.value.running).compareTo(a.value.paid + a.value.running));
      final categoryMax = categoryEntries.isEmpty ? 0.0 : categoryEntries.first.value.paid + categoryEntries.first.value.running;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashSubheading('Donations & funds'),
          OutlinedCard(
            title: 'Money received',
            child: _CardBody([
              if (collected.count == 0)
                Text('No money was received in this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                Text(formatPeso(collected.total), style: GoogleFonts.tiltWarp(fontSize: 30, color: AppColors.textPrimary, height: 1)),
                const SizedBox(height: 4),
                Text('${plural(collected.count, 'donation')} received. Donors are counted, never named.', style: dashMuted()),
                for (final e in collected.byChannel.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount)))
                  _BarRow(e.key, '${formatPeso(e.value.amount)} · ${e.value.count}', channelMax == 0 ? 0 : e.value.amount / channelMax),
                _gap(10),
                Text(
                  'Recorded automatically through PayMongo: ${collected.automatic.text}'
                  '${collected.automatic.percent == null ? '' : ' (${collected.automatic.percent})'}. The rest was typed in by staff.',
                  style: dashBody(weight: FontWeight.w600),
                ),
              ],
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Where the money went',
            child: _CardBody([
              MetricGrid(tiles: [
                MetricTile(label: 'Received', valueText: formatPeso(flow.received), caption: 'donations'),
                MetricTile(label: 'Cashed out', valueText: formatPeso(flow.cashedOut), caption: 'taken out of PayMongo, bank or cash box'),
                MetricTile(label: 'Assigned to costs', valueText: formatPeso(flow.allocated), caption: 'spending recorded on funds'),
                MetricTile(label: 'Spent', valueText: formatPeso(flow.spent), caption: 'paid expenses'),
              ]),
              const SizedBox(height: 6),
              Text('Four separate records; one isn\'t worked out from another, so they needn\'t add up.', style: dashMuted()),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Expenses',
            child: _CardBody([
              if (categoryEntries.isEmpty)
                Text('No expense was recorded in this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                MetricGrid(tiles: [
                  MetricTile(label: 'Paid', valueText: formatPeso(spending.paid)),
                  MetricTile(
                    label: 'Running bills',
                    valueText: formatPeso(spending.running),
                    caption: 'owed, not paid yet',
                    severity: spending.running > 0 ? DashSeverity.warning : null,
                  ),
                ]),
                for (final e in categoryEntries)
                  _BarRow(
                    e.key,
                    formatPeso(e.value.paid + e.value.running),
                    categoryMax == 0 ? 0 : (e.value.paid + e.value.running) / categoryMax,
                    note: e.value.running > 0 ? '${formatPeso(e.value.running)} still owed' : null,
                  ),
              ],
              const SizedBox(height: 6),
              Text(
                'Only expenses recorded in ResPAWnd. Some costs are paid directly by the owners.'
                '${general.hasError ? ' General expenses are visible only to people who manage money.' : ''}',
                style: dashMuted(),
              ),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Spending per animal',
            child: _CardBody([
              if (median.isEmpty)
                Text('No expense in this period was tied to one animal.', style: dashBody(size: 14, weight: FontWeight.w700))
              else ...[
                Text('Median ${formatPeso(median.value!)}', style: GoogleFonts.tiltWarp(fontSize: 24, color: AppColors.textPrimary)),
                Text('per animal, over ${plural(median.count, 'animal')} (paid and running bills).', style: dashMuted()),
                for (final e in top.take(5))
                  _BarRow(
                    animalLabel(e.key),
                    formatPeso(e.value.paid + e.value.running),
                    totals.isEmpty ? 0 : (e.value.paid + e.value.running) / (top.first.value.paid + top.first.value.running),
                    note: e.value.running > 0 ? '${formatPeso(e.value.running)} of it still owed' : null,
                  ),
              ],
              const SizedBox(height: 6),
              Text('Counts only expenses tied to one animal; shared costs for several animals aren\'t split.', style: dashMuted()),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'Campaigns still short of their goal',
            child: _CardBody([
              if (progress.isEmpty)
                Text('No active campaign with a goal.', style: dashBody(size: 14, weight: FontWeight.w700))
              else
                for (final c in progress.take(6))
                  _BarRow(
                    c.title,
                    '${formatPeso(c.collected)} of ${formatPeso(c.target)}',
                    c.collected / c.target,
                    note: c.createdAt == null ? null : 'Open ${DateTime.now().difference(c.createdAt!).inDays} days',
                  ),
            ]),
          ),
          _gap(),
          OutlinedCard(
            title: 'In-kind donations',
            child: _CardBody([
              if (inKind.isEmpty)
                Text('No in-kind donation was received in this period.', style: dashBody(size: 14, weight: FontWeight.w700))
              else
                for (final e in inKind.entries)
                  _BarRow(e.key, '${e.value.quantity} received · ${plural(e.value.donations, 'donation')}', 1),
              _gap(),
              CardLabel('Used out of received (Stock)'),
              if (usage.isEmpty)
                Text('No in-kind stock was received or used in this period.', style: dashBody(weight: FontWeight.w600))
              else
                for (final u in usage)
                  _BarRow(
                    u.item,
                    '${_qty(u.used)} used of ${_qty(u.received)}',
                    u.received == 0 ? 0 : u.used / u.received,
                    note: u.received == 0 ? 'Received before this period' : null,
                  ),
              const SizedBox(height: 6),
              Text('Counted in quantities; never added to money totals.', style: dashMuted()),
            ]),
          ),
          _gap(),
        ],
      );
    });
  }
}


String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
