import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

// ─── Reports by area ────────────────────────────────────────────────────
//
// The Rescue / Adoptions / Donations analytics from the `dev` admin
// dashboard (analytics_dashboard.dart's AdminAnalyticsSection), carried
// into the Analytics tab with the same metrics, charts, filters and notes.
// Changes from that version, all for data honesty:
//  - an empty data set shows "—" / "No data yet", never 0% or 0.0 hrs;
//  - donations read `donations/` (what the app writes today) instead of
//    the `donors` collection group, which nothing writes any more;
//  - the adoption return rate counts real return requests that ended in a
//    retrieval/intake, not `releasedAt`;
//  - donation figures are visible to finance admins only.

enum AreaReport { rescue, adoption, donation }

extension AreaReportX on AreaReport {
  String get label => switch (this) {
    AreaReport.rescue => 'Rescue',
    AreaReport.adoption => 'Adoptions',
    AreaReport.donation => 'Donations',
  };
}

/// Every case, read once — the same unscoped query `dev` used
/// (`cases.organizationId` is not written by any report path yet).
final reportCasesProvider = FutureProvider.autoDispose<List<RescueCase>>((ref) async {
  final snap = await FirebaseFirestore.instance.collection('cases').get();
  final cases = <RescueCase>[];
  for (final doc in snap.docs) {
    try {
      cases.add(RescueCase.fromFirestore(doc));
    } catch (e) {
      debugPrint('[AreaReports] Skipping unparseable case ${doc.id}: $e');
    }
  }
  return cases;
});

/// Every transporter offer (`cases/{id}/transportAssignments`), read once.
final reportAssignmentsProvider = FutureProvider.autoDispose<List<TransportAssignment>>((ref) async {
  final snap = await FirebaseFirestore.instance.collectionGroup('transportAssignments').get();
  return snap.docs.map((d) => TransportAssignment.fromFirestore(d, d.reference.parent.parent!.id)).toList();
});

class _AreaNotifier extends Notifier<AreaReport> {
  @override
  AreaReport build() => AreaReport.rescue;
  void set(AreaReport a) => state = a;
}

final _areaProvider = NotifierProvider<_AreaNotifier, AreaReport>(_AreaNotifier.new);

class AreaReportsCard extends ConsumerWidget {
  const AreaReportsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(_areaProvider);
    return SectionCard(
      icon: Icons.bar_chart_rounded,
      title: 'Reports by area',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashFilterChips<AreaReport>(
            options: AreaReport.values,
            selected: area,
            labelOf: (a) => a.label,
            onSelected: (a) => ref.read(_areaProvider.notifier).set(a),
          ),
          const SizedBox(height: 12),
          switch (area) {
            AreaReport.rescue => const _RescueReport(),
            AreaReport.adoption => const _AdoptionReport(),
            AreaReport.donation => const _DonationReport(),
          },
        ],
      ),
    );
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────

String _pct(int part, int whole) => whole == 0 ? '—' : '${(part / whole * 100).round()}%';

Widget _note(String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(text, style: dashMuted(11.5)),
);

/// Groups "dog"/"Dog"/"DOG" under one "Dog" bucket; null for a blank or
/// placeholder species so charts never invent a category.
String? _normalizedSpecies(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'unknown species') return null;
  return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
}

const _chartPalette = [
  AppColors.yellowrspwn,
  AppColors.greenrspwn,
  AppColors.lavenderrspwn,
  AppColors.tearspwn,
  Color(0xFFE05C5C),
  Color(0xFF8C6A3F),
  Color(0xFF4F8A8B),
  Color(0xFFF29E4C),
  Color(0xFF9A9A92),
];

/// A chart that can tell its block it has nothing to draw, so the block
/// collapses to a one-line "No data yet." instead of an empty frame.
abstract interface class _DataChart {
  bool get isEmpty;
}

class _ChartBlock extends StatelessWidget {
  final String title;
  final Widget child;
  final List<String>? filterOptions;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;
  final double height;

  const _ChartBlock({
    required this.title,
    required this.child,
    this.filterOptions,
    this.selectedFilter,
    this.onFilterChanged,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: dashBody(size: 13.5, weight: FontWeight.w800)),
              ),
              if (filterOptions != null)
                DropdownButton<String>(
                  value: selectedFilter,
                  underline: const SizedBox(),
                  isDense: true,
                  style: dashBody(size: 12.5, weight: FontWeight.w700),
                  items: [for (final f in filterOptions!) DropdownMenuItem(value: f, child: Text(f))],
                  onChanged: (v) {
                    if (v != null) onFilterChanged?.call(v);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: child is _DataChart && (child as _DataChart).isEmpty ? 44 : height, child: child),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String note;
  const _EmptyChart([this.note = 'No data yet.']);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(note, textAlign: TextAlign.center, style: dashMuted(12)),
    ),
  );
}

class _BarChart extends StatelessWidget implements _DataChart {
  final Map<String, num> data;
  final String Function(num)? valueLabel;

  /// One colour for a single series over time (months); otherwise each
  /// category gets its own.
  final Color? color;
  const _BarChart({required this.data, this.valueLabel, this.color});

  @override
  bool get isEmpty => data.values.every((v) => v == 0);

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    if (entries.isEmpty || entries.every((e) => e.value == 0)) return const _EmptyChart();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY * 1.25,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              valueLabel?.call(rod.toY) ?? '${rod.toY.toInt()}',
              GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.background),
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: color ?? _chartPalette[i % _chartPalette.length],
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 10.5, color: AppColors.textPrimary, height: 1),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
      ),
    );
  }
}

/// Horizontal bars, label beside its own bar — for long category names
/// (decline reasons). Scrolls inside the block past five rows.
class _HorizontalBars extends StatelessWidget implements _DataChart {
  final Map<String, num> data;
  final String empty;
  const _HorizontalBars({required this.data, this.empty = 'No data yet.'});

  @override
  bool get isEmpty => !data.values.any((v) => v > 0);

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _EmptyChart(empty);
    final maxValue = entries.first.value.toDouble();

    return ListView.separated(
      physics: entries.length > 5 ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(e.key, maxLines: 2, overflow: TextOverflow.ellipsis, style: dashBody(size: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (e.value / maxValue).clamp(0.05, 1.0).toDouble(),
                  minHeight: 14,
                  backgroundColor: AppColors.slaterspwn.withValues(alpha: 0.35),
                  color: _chartPalette[i % _chartPalette.length],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: Text(
                '${e.value.toInt()}',
                textAlign: TextAlign.right,
                style: dashBody(size: 12, weight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Tall enough for one legend row per slice, so labels never clip.
double _pieHeight(Map<String, num> data) =>
    (data.values.where((v) => v > 0).length * 30 + 8).clamp(170, 420).toDouble();

class _PieChart extends StatelessWidget implements _DataChart {
  final Map<String, num> data;
  const _PieChart({required this.data});

  @override
  bool get isEmpty => !data.values.any((v) => v > 0);

  @override
  Widget build(BuildContext context) {
    final filtered = data.entries.where((e) => e.value > 0).toList();
    if (filtered.isEmpty) return const _EmptyChart();
    final total = filtered.fold<num>(0, (s, e) => s + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 24,
              sections: [
                for (int i = 0; i < filtered.length; i++)
                  PieChartSectionData(
                    value: filtered[i].value.toDouble(),
                    color: _chartPalette[i % _chartPalette.length],
                    title: '${(filtered[i].value / total * 100).round()}%',
                    radius: 42,
                    titleStyle: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < filtered.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: LegendText(
                    _chartPalette[i % _chartPalette.length],
                    '${filtered[i].key} (${filtered[i].value.toInt()})',
                    style: dashBody(size: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Rescue ──────────────────────────────────────────────────────────────

class _RescueReport extends ConsumerStatefulWidget {
  const _RescueReport();

  @override
  ConsumerState<_RescueReport> createState() => _RescueReportState();
}

class _RescueReportState extends ConsumerState<_RescueReport> {
  String _urgencyWindow = 'All time';

  @override
  Widget build(BuildContext context) {
    return DashAsync<List<RescueCase>>(value: ref.watch(reportCasesProvider), what: 'rescue cases', builder: _content);
  }

  Widget _content(List<RescueCase> cases) {
    final total = cases.length;
    final successful = cases.where((c) => c.status == RescueStatus.completed).length;

    // Response time: report filed → first status change away from pending.
    final responseHours = <double>[];
    for (final c in cases) {
      if (c.createdAt == null) continue;
      final moves = c.statusHistory.where((h) => h.timestamp != null && h.status != 'pending').toList()
        ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      if (moves.isNotEmpty) {
        responseHours.add(moves.first.timestamp!.difference(c.createdAt!).inMinutes / 60.0);
      }
    }
    final avgResponse = responseHours.isEmpty ? null : responseHours.reduce((a, b) => a + b) / responseHours.length;

    final now = DateTime.now();
    final windowStart = switch (_urgencyWindow) {
      'Last 7 days' => now.subtract(const Duration(days: 7)),
      'Last 30 days' => now.subtract(const Duration(days: 30)),
      _ => null,
    };
    final windowed = windowStart == null
        ? cases
        : cases.where((c) => c.createdAt != null && c.createdAt!.isAfter(windowStart));
    final byUrgency = <String, num>{'Critical': 0, 'Medium': 0, 'Low': 0};
    for (final c in windowed) {
      if (c.urgency != null && byUrgency.containsKey(c.urgency)) {
        byUrgency[c.urgency!] = byUrgency[c.urgency]! + 1;
      }
    }

    // Cases and animals are different units: a two-cat report is 1 case
    // and 2 animals.
    var animalsReported = 0;
    final bySpecies = <String, num>{};
    for (final c in cases) {
      for (final s in c.allSpecies) {
        animalsReported++;
        final n = _normalizedSpecies(s);
        if (n == null) continue;
        bySpecies[n] = (bySpecies[n] ?? 0) + 1;
      }
    }

    final byStatus = <String, num>{};
    for (final c in cases) {
      byStatus[c.status.label] = (byStatus[c.status.label] ?? 0) + 1;
    }

    final byRescueType = <String, num>{};
    for (final c in cases) {
      final rt = (c.raw['rescueType'] as String?)?.trim();
      if (rt == null || rt.isEmpty) continue;
      byRescueType[rt] = (byRescueType[rt] ?? 0) + 1;
    }

    // Same denormalized counts the Rescue Reports tabs query, so this can
    // never disagree with them.
    final byAnimalStage = <String, num>{};
    for (final c in cases) {
      c.animalStageCounts.forEach((stage, n) {
        final label = switch (stage) {
          'intake' => 'Intake',
          'in_treatment' => 'In Treatment',
          _ => stage,
        };
        byAnimalStage[label] = (byAnimalStage[label] ?? 0) + n;
      });
    }

    final transferred = cases.where((c) => c.status == RescueStatus.referred || c.openForTransfer).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(label: 'Total rescues (cases)', value: total),
            MetricTile(label: 'Animals reported', value: animalsReported),
            MetricTile(label: 'Successful rescues', value: successful),
            MetricTile(label: 'Case resolution rate', valueText: _pct(successful, total)),
            MetricTile(
              label: 'Avg rescue response time',
              valueText: avgResponse == null ? '—' : '${avgResponse.toStringAsFixed(1)} hrs',
              caption: avgResponse == null ? 'No status changes yet' : 'Report to first action',
            ),
            MetricTile(
              label: 'Transfer and refer rate',
              valueText: _pct(transferred, total),
              caption: '$transferred referred or open for transfer',
            ),
          ],
        ),
        _note('All time · $total cases · $animalsReported animals involved'),
        _ChartBlock(
          title: 'Reports and urgency (cases)',
          filterOptions: const ['All time', 'Last 7 days', 'Last 30 days'],
          selectedFilter: _urgencyWindow,
          onFilterChanged: (v) => setState(() => _urgencyWindow = v),
          child: _BarChart(data: byUrgency),
        ),
        const _ChartBlock(
          title: 'Rescues by location',
          height: 64,
          child: _EmptyChart('Not tracked yet: needs a map view over case locations.'),
        ),
        _ChartBlock(
          title: 'Reports by rescue type (cases)',
          child: _BarChart(data: byRescueType),
        ),
        _ChartBlock(
          title: 'Animals by species',
          child: _BarChart(data: bySpecies),
        ),
        _ChartBlock(
          title: 'Report classification split (cases)',
          height: _pieHeight(byStatus),
          child: _PieChart(data: byStatus),
        ),
        _ChartBlock(
          title: 'Animals by current stage',
          child: _BarChart(data: byAnimalStage),
        ),
        const _TransporterReport(),
      ],
    );
  }
}

class _TransporterReport extends ConsumerWidget {
  const _TransporterReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashAsync<List<TransportAssignment>>(
      value: ref.watch(reportAssignmentsProvider),
      what: 'transporter offers',
      builder: (assignments) {
        // Response rate: offers acted on (accepted or rejected) out of every
        // offer that is no longer pending.
        bool isResolved(TransportAssignment a) => const {
          TransportAssignmentStatus.accepted,
          TransportAssignmentStatus.rejected,
          TransportAssignmentStatus.expired,
          TransportAssignmentStatus.cancelled,
        }.contains(a.status);
        final resolved = assignments.where(isResolved).length;
        final responded = assignments
            .where(
              (a) => a.status == TransportAssignmentStatus.accepted || a.status == TransportAssignmentStatus.rejected,
        )
            .length;

        final declineReasons = <String, num>{};
        for (final a in assignments) {
          if (a.status != TransportAssignmentStatus.rejected) continue;
          final reason = (a.rejectionReason ?? '').trim();
          final key = reason.isEmpty ? 'No reason given' : reason;
          declineReasons[key] = (declineReasons[key] ?? 0) + 1;
        }
        final reasonCount = declineReasons.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            MetricTile(
              label: 'Pet transporter response rate',
              valueText: resolved == 0 ? '—' : _pct(responded, resolved),
              caption: resolved == 0 ? 'No answered offers yet' : '$responded of $resolved closed offers answered',
            ),
            _ChartBlock(
              title: 'Pet transporter decline reasons',
              height: (reasonCount * 40 + 16).clamp(60, 220).toDouble(),
              child: _HorizontalBars(data: declineReasons, empty: 'No declines yet.'),
            ),
            _note(
              'Clinic decline reasons aren’t shown: clinic selection has no accept/decline '
                  'step with a reason yet.',
            ),
          ],
        );
      },
    );
  }
}

// ─── Adoptions ───────────────────────────────────────────────────────────

class _AdoptionReport extends ConsumerWidget {
  const _AdoptionReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashAsync<List<AdoptionApplication>>(
      value: ref.watch(allAdoptionsProvider),
      what: 'adoption applications',
      builder: (apps) {
        final total = apps.length;
        final adopted = apps.where((a) => a.adoptedAt != null).toList();

        final days = <double>[
          for (final a in adopted)
            if (a.createdAt != null) a.adoptedAt!.difference(a.createdAt!).inHours / 24.0,
        ];
        final avgDays = days.isEmpty ? null : days.reduce((a, b) => a + b) / days.length;

        // A return is a return request that ended with the animal back in
        // our care (retrieved or re-admitted at intake).
        final returned = adopted.where((a) {
          final s = a.returnRequest?.status;
          return s == ReturnRequestStatus.retrieved || s == ReturnRequestStatus.intake;
        }).length;
        final openReturns = apps.where((a) {
          final s = a.returnRequest?.status;
          return s != null &&
              s != ReturnRequestStatus.retrieved &&
              s != ReturnRequestStatus.intake &&
              s != ReturnRequestStatus.declined &&
              s != ReturnRequestStatus.cancelled;
        }).length;

        final byStatus = <String, num>{};
        for (final a in apps) {
          byStatus[a.status.label] = (byStatus[a.status.label] ?? 0) + 1;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetricGrid(
              tiles: [
                MetricTile(
                  label: 'Adoption rate',
                  valueText: _pct(adopted.length, total),
                  caption: '${adopted.length} of $total applications',
                ),
                MetricTile(
                  label: 'Length of stay',
                  valueText: avgDays == null ? '—' : '${avgDays.toStringAsFixed(1)} days',
                  caption: 'Application to adoption',
                ),
                MetricTile(
                  label: 'Adoption return rate',
                  valueText: _pct(returned, adopted.length),
                  caption: openReturns == 0 ? '$returned returned' : '$returned returned · $openReturns open',
                ),
                MetricTile(label: 'Total applications', value: total),
              ],
            ),
            _note(
              'Length of stay runs from application to adoption, since the intake date '
                  'lives on the rescue case, not the application.',
            ),
            _ChartBlock(
              title: 'Screening and application outcomes',
              child: _BarChart(data: byStatus),
            ),
          ],
        );
      },
    );
  }
}

// ─── Donations ───────────────────────────────────────────────────────────

class _DonationReport extends ConsumerStatefulWidget {
  const _DonationReport();

  @override
  ConsumerState<_DonationReport> createState() => _DonationReportState();
}

class _DonationReportState extends ConsumerState<_DonationReport> {
  String _monthFilter = 'Last 6 months';

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    if (!canManage) {
      return const RestrictedNotice('Donation figures are visible to finance admins only.');
    }
    return DashAsync<List<DonationHistoryRecord>>(
      value: ref.watch(allDonationsProvider),
      what: 'donations',
      builder: _content,
    );
  }

  Widget _content(List<DonationHistoryRecord> all) {
    // Monetary gifts only; in-kind pledges have no peso amount.
    final money = all.where((d) => !d.isInKind).toList();
    final totalAmount = money.fold<double>(0, (s, d) => s + d.amountValue);

    final byChannel = <String, num>{};
    final byMonth = <String, num>{};
    final firstSeen = <String, DateTime>{};
    final campaignsByDonor = <String, Set<String>>{};
    for (final d in money) {
      final method = d.method.trim().isEmpty ? 'Unknown' : d.method.trim();
      byChannel[method] = (byChannel[method] ?? 0) + 1;

      final uid = d.userId;
      if (uid != null && d.campaignId.isNotEmpty) {
        campaignsByDonor.putIfAbsent(uid, () => <String>{}).add(d.campaignId);
      }
      final when = d.when;
      if (when != null) {
        final key = _monthKey(when);
        byMonth[key] = (byMonth[key] ?? 0) + d.amountValue;
        if (uid != null && (firstSeen[uid] == null || when.isBefore(firstSeen[uid]!))) firstSeen[uid] = when;
      }
    }

    // Repeat donor: gave to more than one different campaign.
    final donors = campaignsByDonor.length;
    final repeat = campaignsByDonor.values.where((c) => c.length > 1).length;

    final newDonorsByMonth = <String, num>{};
    for (final t in firstSeen.values) {
      final key = _monthKey(t);
      newDonorsByMonth[key] = (newDonorsByMonth[key] ?? 0) + 1;
    }

    final n = switch (_monthFilter) {
      'Last 3 months' => 3,
      'Last 12 months' => 12,
      _ => 6,
    };
    final now = DateTime.now();
    final months = [for (int i = n - 1; i >= 0; i--) _monthKey(DateTime(now.year, now.month - i))];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(label: 'Total donations', value: money.length),
            MetricTile(
              label: 'Average donation',
              valueText: money.isEmpty ? '—' : formatPeso(totalAmount / money.length),
            ),
            MetricTile(
              label: 'Donor retention rate',
              valueText: _pct(repeat, donors),
              caption: donors == 0 ? 'No signed-in donors yet' : '$repeat of $donors gave to 2+ campaigns',
            ),
          ],
        ),
        _note(
          'Total sponsorships and campaign completion rate aren’t shown yet. '
              '${all.length >= 500 ? 'Based on the latest 500 records. ' : ''}'
              'Anonymous gifts without an account aren’t counted in retention.',
        ),
        _ChartBlock(
          title: 'Donation channels',
          height: _pieHeight(byChannel),
          child: _PieChart(data: byChannel),
        ),
        _ChartBlock(
          title: 'Donations by month',
          filterOptions: const ['Last 3 months', 'Last 6 months', 'Last 12 months'],
          selectedFilter: _monthFilter,
          onFilterChanged: (v) => setState(() => _monthFilter = v),
          child: _BarChart(
            data: {for (final m in months) _monthLabel(m): byMonth[m] ?? 0},
            valueLabel: formatPeso,
            color: AppColors.greenrspwn,
          ),
        ),
        const _ChartBlock(
          title: 'Allocation summary',
          height: 64,
          child: _EmptyChart('Not tracked yet: needs one expense record shared across campaigns.'),
        ),
        _ChartBlock(
          title: 'Donor acquisition',
          child: _BarChart(
            data: {for (final m in months) _monthLabel(m): newDonorsByMonth[m] ?? 0},
            color: AppColors.lavenderrspwn,
          ),
        ),
      ],
    );
  }
}

String _monthKey(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}';

String _monthLabel(String key) {
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[int.parse(key.substring(5)) - 1];
}
