import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/area_reports.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// The "Analytics" tab. Its sections answer plain questions, and together
/// they cover the 12 Lifesaving Ingredients (American Pets Alive!
/// Lifesaving Workbook) without naming them:
///
///  Are we saving more lives? ............ 1 Lifesaving Vision
///  Where did animals go? ................ 5 Transfer, 8 Adoption, 11 Return-to-Owner
///  How fast do animals find homes? ...... 3 Immediate Make Ready, 8 Adoption Policies
///  Who waits longest? ................... 6 Large Adult Dogs, 7 Foster
///  Could animals stay home or outside? .. 2 Safety Net, 4 Community Cats, 9 Intake Diversion
///  Are animals protected from illness? .. 10 Disease Prevention
///  End-of-care decisions (restricted) ... 12 Euthanasia List Scrutiny
///  What we're improving ................. the workbook's Results/Resources/Responsibility
///
/// Measurement rules: missing data is excluded and counted, never treated
/// as zero; every rate states its population; groups under
/// [kMinGroupSize] are flagged; the 90% figure is the workbook's benchmark
/// shown for context, not a Respawnd target.

// ─── Period ──────────────────────────────────────────────────────────────

class AnalyticsPeriodNotifier extends Notifier<int> {
  @override
  int build() => 90;
  void set(int days) => state = days;
}

final analyticsPeriodProvider = NotifierProvider<AnalyticsPeriodNotifier, int>(AnalyticsPeriodNotifier.new);

class Period {
  final DateTime from;
  final DateTime to;
  const Period(this.from, this.to);
  Period get previous => Period(from.subtract(to.difference(from)), from);
  bool has(DateTime? t) => inPeriod(t, from, to);
}

// ─── Outcomes ────────────────────────────────────────────────────────────

/// Outcome counts for one period. Population: every animal whose time in
/// the organization's care ended inside the period — animal records
/// (adopted / transfer started / died) plus rescue-case animals that left
/// care without becoming a record (released to reporter, transfer started,
/// died during treatment, reunited with owner).
class OutcomeCounts {
  int intake = 0;
  int adopted = 0;
  int returnedToOwner = 0;
  int transferStarted = 0;
  int releasedToReporter = 0;
  int diedInCare = 0;
  int euthanasia = 0;
  int causeNotClassified = 0;
  int noOutcomeRecorded = 0;
  final List<DeathRecord> deaths = [];

  int get live => adopted + returnedToOwner + transferStarted + releasedToReporter;
  int get nonLive => diedInCare + euthanasia;
  int get finalized => live + nonLive;

  /// Live outcomes ÷ finalized outcomes. Null when nothing finalized.
  double? get liveRate => finalized == 0 ? null : live / finalized;
}

class DeathRecord {
  final String name;
  final DateTime at;
  final String? cause;
  const DeathRecord(this.name, this.at, this.cause);
  bool get euthanasia => (cause ?? '').toLowerCase().contains('euthan');
}

OutcomeCounts computeOutcomes({
  required Period p,
  required List<AnimalRecord> records,
  required List<RescueCase> cases,
}) {
  final o = OutcomeCounts();
  void death(String name, DateTime at, String? cause) {
    final d = DeathRecord(name, at, cause);
    o.deaths.add(d);
    if (d.euthanasia) {
      o.euthanasia++;
    } else {
      o.diedInCare++;
    }
    if ((cause ?? '').trim().isEmpty) o.causeNotClassified++;
  }

  for (final a in records.where((a) => !a.isMalformed)) {
    if (p.has(a.createdAt)) o.intake++;
    final transferAt = tsOf(a.raw['transferredAt']);
    if (p.has(a.adoptedAt)) {
      o.adopted++;
    } else if (a.raw['transferStatus'] != null && p.has(transferAt)) {
      o.transferStarted++;
    } else if (p.has(a.deceasedAt)) {
      death(a.name.isEmpty ? a.species : a.name, a.deceasedAt!, a.deceasedCause);
    } else if (a.archived &&
        a.adoptedAt == null &&
        a.deceasedAt == null &&
        a.raw['transferStatus'] == null &&
        p.has(a.updatedAt)) {
      o.noOutcomeRecorded++;
    }
  }

  for (final c in cases) {
    // Case-level death during treatment; skip admissions of existing
    // animal records so a death is never counted twice.
    if (p.has(c.deceasedAt) && c.raw['sourceType'] != 'animalRecordAdmission') {
      death('${c.speciesSummary} #${c.shortCaseId}', c.deceasedAt!, c.causeOfDeath);
    }
    if (c.raw['closureReason'] == ClosureReason.reunitedWithOwner.name && p.has(tsOf(c.raw['closedAt']))) {
      o.returnedToOwner += c.animalCount;
    }
    for (final a in c.animals) {
      final action = a['postTreatmentAction'];
      if (action == 'release' && p.has(tsOf(a['releaseCompletedAt']))) o.releasedToReporter++;
      if (action == 'transfer' && p.has(tsOf(a['postTreatmentStartedAt']))) o.transferStarted++;
    }
  }
  return o;
}

final _allCasesForAnalyticsProvider = Provider.autoDispose<AsyncValue<List<RescueCase>>>((ref) {
  final snap = ref.watch(dashboardRescueSnapshotProvider);
  final closed = ref.watch(closedCasesProvider);
  if (snap.hasError) return AsyncValue.error(snap.error!, StackTrace.current);
  if (closed.hasError) return AsyncValue.error(closed.error!, StackTrace.current);
  if (!snap.hasValue || !closed.hasValue) return const AsyncValue.loading();
  final byId = <String, RescueCase>{for (final c in closed.requireValue) c.id: c};
  for (final c in snap.requireValue.all) {
    byId[c.id] = c;
  }
  return AsyncValue.data(byId.values.toList());
});

// ─── View ────────────────────────────────────────────────────────────────

class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(analyticsPeriodProvider);
    final now = DateTime.now();
    final period = Period(now.subtract(Duration(days: days)), now);
    final recordsAsync = ref.watch(allAnimalRecordsProvider);
    final casesAsync = ref.watch(_allCasesForAnalyticsProvider);

    if (recordsAsync.hasError) return DashError(what: 'animal records', error: recordsAsync.error!);
    if (casesAsync.hasError) return DashError(what: 'rescue cases', error: casesAsync.error!);
    if (!recordsAsync.hasValue || !casesAsync.hasValue) return const DashLoading(label: 'Calculating outcomes…');

    final records = recordsAsync.requireValue;
    final cases = casesAsync.requireValue;
    final cur = computeOutcomes(p: period, records: records, cases: cases);
    final prev = computeOutcomes(p: period.previous, records: records, cases: cases);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LivesCard(cur: cur, prev: prev, records: records),
        const SizedBox(height: 14),
        const _ConstraintCallout(),
        const SizedBox(height: 14),
        _PathwaysCard(cur: cur, cases: cases, records: records),
        const SizedBox(height: 14),
        _SpeedCard(period: period, records: records, cases: cases),
        const SizedBox(height: 14),
        _WaitsCard(records: records),
        const SizedBox(height: 14),
        _DiversionCard(period: period, cases: cases),
        const SizedBox(height: 14),
        _PreventionCard(records: records),
        const SizedBox(height: 14),
        _EndOfCareCard(cur: cur),
        const SizedBox(height: 14),
        const _FocusAreasCard(),
        const SizedBox(height: 14),
        const AreaReportsCard(),
      ],
    );
  }
}

/// The period selector shown in the Analytics header row.
class AnalyticsPeriodButton extends ConsumerWidget {
  const AnalyticsPeriodButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(analyticsPeriodProvider);
    return PopupMenuButton<int>(
      tooltip: 'Reporting period',
      onSelected: (d) => ref.read(analyticsPeriodProvider.notifier).set(d),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 30, child: Text('Last 30 days')),
        PopupMenuItem(value: 90, child: Text('Last 90 days')),
        PopupMenuItem(value: 365, child: Text('Last 12 months')),
      ],
      child: _Pill(
        icon: Icons.timer_outlined,
        text: days == 365 ? 'Last 12 months' : 'Last $days days',
        dropdown: true,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool dropdown;
  const _Pill({required this.icon, required this.text, this.dropdown = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          Text(text, style: dashBody(size: 14, weight: FontWeight.w700)),
          if (dropdown) const Icon(Icons.arrow_drop_down, color: AppColors.textPrimary),
        ],
      ),
    );
  }
}

// ─── 1. Are we saving more lives? ────────────────────────────────────────

class _LivesCard extends StatelessWidget {
  final OutcomeCounts cur;
  final OutcomeCounts prev;
  final List<AnimalRecord> records;
  const _LivesCard({required this.cur, required this.prev, required this.records});

  @override
  Widget build(BuildContext context) {
    final rate = cur.liveRate;
    final prevRate = prev.liveRate;
    final inCare = records.where(isInCare).length;
    return OutlinedCard(
      title: 'Are we saving more lives?',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rate == null)
              Text(
                'No animal left care in this period, so there’s no rate yet.',
                style: dashBody(size: 14, weight: FontWeight.w700),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(rate * 100).round()}%',
                    style: GoogleFonts.tiltWarp(fontSize: 34, color: AppColors.textPrimary, height: 1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('left our care alive', style: dashBody(size: 14, weight: FontWeight.w700)),
                  ),
                  if (prevRate != null)
                    _Delta(now: rate * 100, before: prevRate * 100, unit: '%', higherIsBetter: true),
                ],
              ),
              const SizedBox(height: 10),
              _RateBar(rate: rate, previous: prevRate),
              const SizedBox(height: 5),
              Text(
                '${cur.live} of ${cur.finalized} animals whose stay ended. The black marker is the workbook’s 90% benchmark, '
                    'shown for context only.',
                style: dashMuted(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _MiniStat('${cur.intake}', 'Taken in · was ${prev.intake}')),
                const SizedBox(width: 8),
                Expanded(child: _MiniStat('$inCare', 'Still in care · not counted yet')),
              ],
            ),
            if (cur.noOutcomeRecorded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DetailLine(
                  Icons.warning_rounded,
                  '${plural(cur.noOutcomeRecorded, 'animal')} archived with no outcome recorded. Excluded; tap Animal Records to fix.',
                  color: DashSeverity.warning.color,
                  maxLines: null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  final double rate;
  final double? previous;
  const _RateBar({required this.rate, this.previous});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 18,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(color: const Color(0xFFE6E3DA), borderRadius: BorderRadius.circular(5)),
                ),
              ),
              Positioned(
                left: 0,
                top: 4,
                child: Container(
                  width: w * rate,
                  height: 10,
                  decoration: BoxDecoration(color: DashSeverity.ok.color, borderRadius: BorderRadius.circular(5)),
                ),
              ),
              if (previous != null)
                Positioned(
                  left: w * previous! - 1,
                  top: 2,
                  child: Container(width: 2, height: 14, color: const Color(0xFF9B978B)),
                ),
              Positioned(
                left: w * 0.9 - 1,
                top: 0,
                child: Container(width: 2, height: 18, color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Delta extends StatelessWidget {
  final double now;
  final double before;
  final String unit;
  final bool higherIsBetter;
  const _Delta({required this.now, required this.before, required this.unit, required this.higherIsBetter});

  @override
  Widget build(BuildContext context) {
    final diff = now - before;
    if (diff.abs() < 0.5) return Text('same as before', style: dashMuted(13));
    final better = higherIsBetter ? diff > 0 : diff < 0;
    return Text(
      '${diff > 0 ? '↑' : '↓'} was ${before.round()}$unit',
      style: dashBody(
        size: 13,
        weight: FontWeight.w700,
        color: better ? DashSeverity.ok.color : DashSeverity.critical.color,
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final bool dashed;
  final Color? color;
  const _MiniStat(this.value, this.label, {this.dashed = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: dashed ? Border.all(color: const Color(0xFFA9A79F)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.tiltWarp(
              fontSize: 19,
              color: color ?? (dashed ? AppColors.textSecondary : AppColors.textPrimary),
            ),
          ),
          Text(label, style: dashMuted()),
        ],
      ),
    );
  }
}

// ─── Biggest constraint ──────────────────────────────────────────────────

class _ConstraintCallout extends ConsumerWidget {
  const _ConstraintCallout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supply = ref.watch(transportSupplyProvider).asData?.value;
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final occ = ref.watch(shelterOccupancyProvider).asData?.value;
    final waiting = snap?.count(RescueStage.transporter) ?? 0;

    String? title;
    String? body;
    if (supply != null && waiting > 0 && waiting >= supply.free) {
      title = 'Transport';
      body = '${supply.free} of ${supply.registered} riders free · ${plural(waiting, 'case')} waiting for a ride.';
    } else if (occ?.free != null && occ!.free! <= 0) {
      title = 'Shelter space';
      body = '${occ.used} of ${occ.capacity} spaces in use with ${occ.arriving} arriving.';
    } else if (occ != null && occ.isolationFull) {
      title = 'Isolation';
      body = 'All ${occ.isolationCapacity} isolation spots are in use.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, color: AppColors.yellowrspwn, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BIGGEST CONSTRAINT RIGHT NOW',
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.yellowrspwn,
                  ),
                ),
                Text(title ?? 'None recorded', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
                Text(
                  body ?? 'No recorded factor is limiting rescues. Care staffing and supplies aren’t tracked yet.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.background.withValues(alpha: .85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 2. Where did animals go? ────────────────────────────────────────────

class _PathwaysCard extends ConsumerWidget {
  final OutcomeCounts cur;
  final List<RescueCase> cases;
  final List<AnimalRecord> records;
  const _PathwaysCard({required this.cur, required this.cases, required this.records});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final possibleOwners = cases
        .where(
          (c) =>
      !c.status.isTerminal &&
          (c.raw['ownershipStatus'] == 'Possible owner' || c.raw['ownershipStatus'] == 'Owner identified'),
    )
        .length;
    final transfersPending = records.where((a) => a.raw['transferStatus'] == 'pending' && isInCare(a)).length;
    final maxV = [
      cur.adopted,
      cur.returnedToOwner,
      cur.transferStarted,
      cur.releasedToReporter,
      cur.diedInCare,
      cur.euthanasia,
    ].fold<int>(1, (m, v) => v > m ? v : m);
    const live1 = Color(0xFF3F8F5A), live2 = Color(0xFF6FB487), live3 = Color(0xFF8DBF9C), live4 = Color(0xFFB3D6BE);
    return SectionCard(
      icon: Icons.alt_route,
      title: 'Where did animals go?',
      onOpen: () => openAdoptionQueue(context, AdoptionStatus.adopted),
      child: Column(
        children: [
          _PathRow(Icons.home, live1, 'Adopted', cur.adopted, maxV),
          _PathRow(
            Icons.person,
            live2,
            'Back with owner',
            cur.returnedToOwner,
            maxV,
            note: possibleOwners == 0
                ? null
                : '${plural(possibleOwners, 'possible owner')} still unresolved on open cases',
          ),
          _PathRow(
            Icons.local_shipping,
            live3,
            'Transferred out',
            cur.transferStarted,
            maxV,
            note: transfersPending == 0
                ? 'Completion isn’t confirmed in the app yet'
                : '$transfersPending started, completion not confirmed',
          ),
          _PathRow(Icons.assignment_ind, live4, 'Released to reporter', cur.releasedToReporter, maxV),
          _PathRow(
            Icons.healing,
            const Color(0xFF8E8A7E),
            'Died in care',
            cur.diedInCare,
            maxV,
            note: cur.causeNotClassified == 0 ? null : '${cur.causeNotClassified} with cause not recorded',
          ),
          _PathRow(
            Icons.circle,
            const Color(0xFF5E5B52),
            'Euthanasia',
            cur.euthanasia,
            maxV,
            note: cur.euthanasia == 0 ? null : 'Second review: not recorded',
          ),
          DetailLine(
            Icons.info_outline,
            'Transfers and returns to owner are their own outcomes, not adoptions.',
            maxLines: null,
          ),
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final int max;
  final String? note;
  const _PathRow(this.icon, this.color, this.label, this.value, this.max, {this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 118,
                child: Text(label, style: dashBody(size: 14, weight: FontWeight.w700)),
              ),
              Expanded(
                child: DashProgress(fraction: value / max, color: color, semanticsLabel: '$label: $value'),
              ),
              SizedBox(
                width: 30,
                child: Text('$value', textAlign: TextAlign.right, style: GoogleFonts.tiltWarp(fontSize: 16)),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 2),
              child: Text(note!, style: dashMuted(11.5)),
            ),
        ],
      ),
    );
  }
}

// ─── 3. How fast do animals find homes? ──────────────────────────────────

class _SpeedCard extends ConsumerWidget {
  final Period period;
  final List<AnimalRecord> records;
  final List<RescueCase> cases;
  const _SpeedCard({required this.period, required this.records, required this.cases});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(allAdoptionsProvider).asData?.value ?? const <AdoptionApplication>[];

    final stabilize = median([
      for (final c in cases)
        if (c.dateAdmitted != null && period.has(c.dischargedAt)) c.dischargedAt!.difference(c.dateAdmitted!).inDays,
    ]);
    final overall = median([
      for (final a in records)
        if (a.createdAt != null && period.has(a.adoptedAt)) a.adoptedAt!.difference(a.createdAt!).inDays,
    ]);
    List<int> reviewDays(Period p) => [
      for (final a in apps)
        if (a.createdAt != null)
          if (p.has(a.approvedAt ?? a.rejectedAt))
            (a.approvedAt ?? a.rejectedAt)!.difference(a.createdAt!).inHours ~/ 24,
    ];
    final review = median(reviewDays(period));
    final reviewPrev = median(reviewDays(period.previous));
    final clearance = records
        .where((a) => isInCare(a) && a.adoptionStatus == 'not_ready' && !hasOpenMedicalCase(a))
        .length;
    final stalled = apps
        .where((a) => a.status == AdoptionStatus.interview && (a.appointmentDate == null || a.noShowAt != null))
        .length;
    final interviewing = apps.where((a) => a.status == AdoptionStatus.interview).length;

    String d(double? v) => v == null ? 'no data' : '${v.round()} d';

    return SectionCard(
      icon: Icons.timer_outlined,
      title: 'How fast do animals find homes?',
      onOpen: () => openAdoptionQueue(context, AdoptionStatus.pending),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Median days per step', style: dashMuted()),
          _StepRow(
            Icons.healing,
            'Vet admission to discharge',
            d(stabilize),
            stabilize == null ? null : (stabilize / 60).clamp(0.05, 1.0),
          ),
          const _StepRow(Icons.check, 'Stable to ready for adoption', 'not recorded', null),
          const _StepRow(Icons.home, 'Ready to adopted', 'not recorded', null),
          _StepRow(
            Icons.timer_outlined,
            'Intake to adopted, overall',
            d(overall),
            overall == null ? null : (overall / 120).clamp(0.05, 1.0),
            strong: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  '$clearance',
                  'Waiting for vet or behavior clearance',
                  color: clearance > 0 ? DashSeverity.warning.color : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  review == null ? '—' : '${review.toStringAsFixed(1)} d',
                  'Review time${reviewPrev == null ? '' : ' (was ${reviewPrev.toStringAsFixed(1)} d)'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MiniStat('$stalled of $interviewing', 'Interviews not scheduled or missed'),
          const SizedBox(height: 6),
          DetailLine(
            Icons.info_outline,
            'Recording a “ready” date would show where the days go. Readiness still needs health, behavior and preventive care.',
            maxLines: null,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double? fraction;
  final bool strong;
  const _StepRow(this.icon, this.label, this.value, this.fraction, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final unknown = fraction == null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: strong ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: .14),
            width: strong ? 1.3 : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: AppColors.tearspwn, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: dashBody(size: 13.5, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                unknown
                    ? const _DashedTrack()
                    : DashProgress(
                  fraction: fraction!,
                  color: strong ? AppColors.greenrspwn : AppColors.textPrimary,
                  semanticsLabel: '$label $value',
                ),
              ],
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: unknown || value == 'no data'
                  ? dashMuted(12)
                  : GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedTrack extends StatelessWidget {
  const _DashedTrack();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = (c.maxWidth / 9).floor();
        return Row(
          children: [
            for (int i = 0; i < n; i++)
              Container(width: 5, height: 7, margin: const EdgeInsets.only(right: 4), color: const Color(0xFFC9C5B8)),
          ],
        );
      },
    );
  }
}

// ─── 4. Who waits longest? ───────────────────────────────────────────────

class _WaitsCard extends StatelessWidget {
  final List<AnimalRecord> records;
  const _WaitsCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final inCare = records.where((a) => isInCare(a) && a.createdAt != null).toList();
    int days(AnimalRecord a) => DateTime.now().difference(a.createdAt!).inDays;
    final groups = <(String, List<AnimalRecord>)>[
      ('Large adult dogs', inCare.where(isLargeAdultDog).toList()),
      ('Other dogs', inCare.where((a) => a.species.toLowerCase() == 'dog' && !isLargeAdultDog(a)).toList()),
      ('Cats', inCare.where((a) => a.species.toLowerCase() == 'cat').toList()),
      ('On medication', inCare.where((a) => (a.health.currentMedications ?? '').trim().isNotEmpty).toList()),
      ('Seniors (7+ y)', inCare.where((a) => ageGroupOf(a) == 'Senior (7+ y)').toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    final medians = {for (final g in groups) g.$1: median(g.$2.map(days).toList())!};
    final eligible = groups.where((g) => g.$2.length >= kMinGroupSize).toList();
    final longest = eligible.isEmpty ? null : eligible.reduce((a, b) => medians[a.$1]! >= medians[b.$1]! ? a : b).$1;
    final noDate = records.where((a) => isInCare(a) && a.createdAt == null).length;

    return SectionCard(
      icon: Icons.schedule,
      title: 'Who waits longest?',
      onOpen: () => openAnimalRecords(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isEmpty)
            const DashEmpty('No animals in care with an intake date.', severity: DashSeverity.info)
          else
            Table(
              columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.8)},
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.textPrimary, width: 1.3)),
                  ),
                  children: [
                    for (final h in ['GROUP', 'IN CARE', 'MEDIAN DAYS'])
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(h, style: dashMuted(11)),
                      ),
                  ],
                ),
                for (final g in groups)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.textPrimary.withValues(alpha: .14))),
                    ),
                    children: [
                      _cell(g.$1, small: g.$2.length < kMinGroupSize),
                      _cell('${g.$2.length}', small: g.$2.length < kMinGroupSize),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
                        child: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${medians[g.$1]!.round()}',
                              style: dashBody(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: g.$2.length < kMinGroupSize
                                    ? const Color(0xFF9A988F)
                                    : (g.$1 == longest ? DashSeverity.warning.color : AppColors.textPrimary),
                              ),
                            ),
                            if (g.$2.length < kMinGroupSize) const StatusChip('n<10', tone: ChipTone.notRecorded),
                            if (g.$1 == longest) const StatusChip('Longest', tone: ChipTone.amber),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: _MiniStat('—', 'Large-dog spaces · not set', dashed: true)),
              SizedBox(width: 8),
              Expanded(child: _MiniStat('0', 'Foster homes recorded · could free space', dashed: true)),
            ],
          ),
          const SizedBox(height: 6),
          DetailLine(
            Icons.info_outline,
            'Grey rows have fewer than $kMinGroupSize animals: early signs, not conclusions.${noDate == 0 ? '' : ' $noDate without an intake date are excluded.'}',
            maxLines: null,
          ),
        ],
      ),
    );
  }

  Widget _cell(String t, {bool small = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
    child: Text(
      t,
      style: dashBody(
        size: 13.5,
        weight: FontWeight.w700,
        color: small ? const Color(0xFF9A988F) : AppColors.textPrimary,
      ),
    ),
  );
}

// ─── 5. Could animals stay home or outside? ──────────────────────────────

class _DiversionCard extends ConsumerWidget {
  final Period period;
  final List<RescueCase> cases;
  const _DiversionCard({required this.period, required this.cases});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = cases.where((c) => period.has(c.createdAt)).length;
    final closedHere = cases.where((c) => period.has(tsOf(c.raw['closedAt']))).toList();
    String? reason(RescueCase c) => c.raw['closureReason'] as String?;
    final confirmed = closedHere.where((c) => reason(c) == ClosureReason.reunitedWithOwner.name).length;
    final ownerKnown = closedHere.where((c) => reason(c) == ClosureReason.hasOwner.name).length;
    final resolved = closedHere.where((c) => reason(c) == ClosureReason.resolvedWithoutTransport.name).length;
    final unknown = ownerKnown + resolved;
    final diverted = confirmed + unknown;
    final referred = cases.where((c) => c.status == RescueStatus.referred && period.has(lastUpdateOf(c))).length;

    return SectionCard(
      icon: Icons.groups,
      title: 'Could animals stay home or outside?',
      // Closed cases are stored as cancelled; reuse Rescue Reports' own
      // status filter to list them.
      onOpen: () {
        ref.read(rescueFilterProvider.notifier).setStatusOverride(RescueStatus.cancelled);
        openRescueTab(context, ref, RescuePipelineTab.review);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reports closed without bringing the animal in', style: dashMuted()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$diverted', style: GoogleFonts.tiltWarp(fontSize: 34, color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('of $reports reports', style: dashMuted(13)),
              ),
            ],
          ),
          if (diverted > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    if (confirmed > 0)
                      Expanded(
                        flex: confirmed,
                        child: Container(color: DashSeverity.ok.color),
                      ),
                    if (confirmed > 0 && unknown > 0) const SizedBox(width: 2),
                    if (unknown > 0)
                      Expanded(
                        flex: unknown,
                        child: Container(color: const Color(0xFFD7D4CB)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                LegendText(
                  DashSeverity.ok.color,
                  '$confirmed reunited (confirmed safe)',
                  style: dashBody(size: 12.5, weight: FontWeight.w700, color: DashSeverity.ok.color),
                ),
                LegendText(
                  const Color(0xFFD7D4CB),
                  '$unknown outcome unknown, not counted as success',
                  style: dashMuted(12.5),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _MiniStat('$ownerKnown', 'Closed: animal has an owner')),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat('$referred', 'Referred to another org, LGU or volunteer')),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: _MiniStat('—', 'Help requests (food, vet costs) · not tracked', dashed: true)),
              SizedBox(width: 8),
              Expanded(child: _MiniStat('—', 'Community cats · not tagged on reports', dashed: true)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 6. Are animals protected from illness? ──────────────────────────────

class _PreventionCard extends ConsumerWidget {
  final List<AnimalRecord> records;
  const _PreventionCard({required this.records});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaxAsync = ref.watch(vaccinationsByAnimalProvider);
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    return SectionCard(
      icon: Icons.vaccines,
      title: 'Are animals protected from illness?',
      onOpen: () => openAnimalRecords(context),
      child: DashAsync<Map<String, List<VaccinationRecord>>>(
        value: vaxAsync,
        what: 'vaccination records',
        builder: (vax) {
          final inCare = records.where(isInCare).toList();
          final withRecords = inCare.where((a) => (vax[a.id] ?? const []).isNotEmpty).toList();
          final current = withRecords.where((a) => healthStatusOf(vax[a.id]) != HealthRecordStatus.overdue).length;
          final overdue = withRecords.length - current;
          final notRecorded = inCare.length - withRecords.length;
          final rate = withRecords.isEmpty ? null : current / withRecords.length;
          final dewormedYes = inCare.where((a) => a.health.dewormed == true).length;
          final dewormedKnown = inCare.where((a) => a.health.dewormed != null).length;
          final quarantines = snap == null
              ? 0
              : [
            ...snap.of(RescueStage.intake),
            ...snap.of(RescueStage.treatment),
          ].where((c) => c.isQuarantineActive).length;
          final recent = inCare
              .where((a) => a.createdAt != null && DateTime.now().difference(a.createdAt!).inDays < 14)
              .toList();
          final recentNoVax = recent.where((a) => (vax[a.id] ?? const []).isEmpty).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 84,
                          height: 84,
                          child: CircularProgressIndicator(
                            value: rate ?? 0,
                            strokeWidth: 10,
                            backgroundColor: const Color(0xFFE6E3DA),
                            color: DashSeverity.ok.color,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              rate == null ? '—' : '${(rate * 100).round()}%',
                              style: GoogleFonts.tiltWarp(fontSize: 19),
                            ),
                            Text('current', style: dashMuted(10.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$current of ${withRecords.length} animals with vaccine records are up to date',
                          style: dashBody(size: 14, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$notRecorded have no vaccine record. They’re excluded, not counted as unvaccinated.',
                          style: dashMuted(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  if (overdue > 0) StatusChip('$overdue overdue', tone: ChipTone.red, icon: Icons.error_outline),
                  StatusChip('Dewormed $dewormedYes of $dewormedKnown recorded', tone: ChipTone.info),
                  StatusChip('Quarantine active $quarantines', tone: quarantines > 0 ? ChipTone.amber : ChipTone.green),
                  const StatusChip('Flea/tick not tracked', tone: ChipTone.notRecorded),
                  const StatusChip('Illness log not tracked', tone: ChipTone.notRecorded),
                ],
              ),
              if (recentNoVax > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DetailLine(
                    Icons.warning_rounded,
                    'Most at risk: recent intakes. $recentNoVax of ${recent.length} from the last 14 days have no vaccine record yet.',
                    color: DashSeverity.critical.color,
                    maxLines: null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── 7. End-of-care decisions (restricted) ───────────────────────────────

class _EndOfCareCard extends ConsumerWidget {
  final OutcomeCounts cur;
  const _EndOfCareCard({required this.cur});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final total = cur.deaths.length;
    final documented = cur.deaths.where((d) => (d.cause ?? '').trim().isNotEmpty).length;
    return SectionCard(
      icon: Icons.lock,
      title: 'End-of-care decisions',
      background: const Color(0xFFF3F1EB),
      trailing: const Padding(
        padding: EdgeInsets.only(right: 6),
        child: StatusChip('Authorized only', tone: ChipTone.ink, icon: Icons.lock),
      ),
      child: !canManage
          ? const RestrictedNotice('Visible to authorized admins only.')
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  '$total',
                  'Non-live outcomes (${cur.diedInCare} died, ${cur.euthanasia} euthanasia)',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat('$documented of $total', 'Cause documented')),
            ],
          ),
          const SizedBox(height: 8),
          const _MiniStat(
            '—',
            'Second review and alternatives considered: not recorded yet. This supports careful decisions; it is never used to delay medically justified ones.',
            dashed: true,
          ),
        ],
      ),
    );
  }
}

// ─── 8. What we're improving (Results · Resources · Responsibility) ─────

class FocusArea {
  final String title;
  final String result;
  final String resources;
  final String owner;
  final DateTime? due;
  final String status; // planned | active | done
  const FocusArea({
    required this.title,
    required this.result,
    required this.resources,
    required this.owner,
    this.due,
    this.status = 'planned',
  });

  factory FocusArea.fromMap(Map<String, dynamic> m) => FocusArea(
    title: m['title'] as String? ?? '',
    result: m['result'] as String? ?? '',
    resources: m['resources'] as String? ?? '',
    owner: m['owner'] as String? ?? '',
    due: tsOf(m['due']),
    status: m['status'] as String? ?? 'planned',
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'result': result,
    'resources': resources,
    'owner': owner,
    'due': due == null ? null : Timestamp.fromDate(due!),
    'status': status,
  };
}

/// Stored at `organizations/{orgId}.focusAreas` (a short list, at most 4,
/// matching the workbook's advice to work on 2–4 at a time).
final focusAreasProvider = StreamProvider.autoDispose<List<FocusArea>>((ref) {
  final orgId = ref.watch(dashboardOrgIdProvider).asData?.value;
  if (orgId == null) return Stream.value(const []);
  return FirebaseFirestore.instance.collection('organizations').doc(orgId).snapshots().map((d) {
    final raw = d.data()?['focusAreas'];
    if (raw is! List) return const <FocusArea>[];
    return raw.whereType<Map>().map((m) => FocusArea.fromMap(Map<String, dynamic>.from(m))).toList();
  });
});

Future<void> _saveFocusAreas(String orgId, List<FocusArea> areas) => FirebaseFirestore.instance
    .collection('organizations')
    .doc(orgId)
    .set({'focusAreas': areas.map((a) => a.toMap()).toList()}, SetOptions(merge: true));

class _FocusAreasCard extends ConsumerWidget {
  const _FocusAreasCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(focusAreasProvider);
    final orgId = ref.watch(dashboardOrgIdProvider).asData?.value;
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final areas = areasAsync.asData?.value ?? const <FocusArea>[];
    final canEdit = orgId != null && canManage;

    return SectionCard(
      icon: Icons.star,
      title: 'What we’re improving',
      trailing: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: StatusChip('${areas.length} of 4 focus areas'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (areasAsync.isLoading && !areasAsync.hasValue)
            const DashLoading()
          else if (areas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No focus areas yet. Pick 2–4 things to improve, each with a result, resources and a person responsible.',
                style: dashMuted(13),
              ),
            ),
          for (int i = 0; i < areas.length; i++)
            InkWell(
              onTap: canEdit ? () => _editFocusArea(context, orgId, areas, i) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: .14))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(areas[i].title, style: dashBody(size: 14.5, weight: FontWeight.w700)),
                          Text(
                            'Result: ${areas[i].result.isEmpty ? 'target not set' : areas[i].result}',
                            style: dashMuted(12.5),
                          ),
                          if (areas[i].resources.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.inventory_2, size: 13, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(child: Text(areas[i].resources, style: dashMuted(12.5))),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    areas[i].owner.isEmpty
                        ? const StatusChip('Assign owner', tone: ChipTone.amber)
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${areas[i].owner}${areas[i].due == null ? '' : ' · ${shortDate(areas[i].due!)}'}',
                          style: dashMuted(12.5),
                        ),
                        const SizedBox(height: 4),
                        StatusChip(
                          areas[i].status == 'done'
                              ? 'Done'
                              : (areas[i].status == 'active' ? 'Active' : 'Planned'),
                          tone: areas[i].status == 'done'
                              ? ChipTone.green
                              : (areas[i].status == 'active' ? ChipTone.amber : ChipTone.info),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (canEdit && areas.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: DashLinkButton(
                label: 'Add focus area',
                icon: Icons.add,
                onPressed: () => _editFocusArea(context, orgId, areas, null),
              ),
            ),
          DetailLine(Icons.info_outline, 'Targets only appear when an admin sets one.', maxLines: null),
        ],
      ),
    );
  }

  Future<void> _editFocusArea(BuildContext context, String orgId, List<FocusArea> areas, int? index) async {
    final existing = index == null ? null : areas[index];
    final title = TextEditingController(text: existing?.title);
    final result = TextEditingController(text: existing?.result);
    final resources = TextEditingController(text: existing?.resources);
    final owner = TextEditingController(text: existing?.owner);
    String status = existing?.status ?? 'planned';
    DateTime? due = existing?.due;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(index == null ? 'New focus area' : 'Edit focus area', style: dashTitle(19)),
                const SizedBox(height: 10),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'What to improve'),
                ),
                TextField(
                  controller: result,
                  decoration: const InputDecoration(labelText: 'Result (measurable, optional)'),
                ),
                TextField(
                  controller: resources,
                  decoration: const InputDecoration(labelText: 'Resources needed'),
                ),
                TextField(
                  controller: owner,
                  decoration: const InputDecoration(labelText: 'Person responsible'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in const ['planned', 'active', 'done'])
                      ChoiceChip(
                        label: Text(s[0].toUpperCase() + s.substring(1)),
                        selected: status == s,
                        onSelected: (_) => setSheet(() => status = s),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.event, size: 16),
                      label: Text(due == null ? 'Set due date' : 'Due ${shortDate(due!)}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: due ?? DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) setSheet(() => due = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (index != null)
                      TextButton(
                        onPressed: () async {
                          final next = [...areas]..removeAt(index);
                          await _saveFocusAreas(orgId, next);
                          if (ctx.mounted) Navigator.pop(ctx, false);
                        },
                        child: const Text('Remove'),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      final area = FocusArea(
        title: title.text.trim(),
        result: result.text.trim(),
        resources: resources.text.trim(),
        owner: owner.text.trim(),
        due: due,
        status: status,
      );
      final next = [...areas];
      if (index == null) {
        next.add(area);
      } else {
        next[index] = area;
      }
      await _saveFocusAreas(orgId, next);
    }
    for (final c in [title, result, resources, owner]) {
      c.dispose();
    }
  }
}
