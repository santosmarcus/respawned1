import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/utils/org_list_scope.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_query_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart' show currentOrganizationIdProvider;
import 'package:respawnd1/features/adminhome/dashboard/case_location.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

// ─── Reports by area ────────────────────────────────────────────────────
//
// The Rescue / Adoptions / Donations analytics from the `dev` admin
// dashboard (the old AdminAnalyticsSection, since removed), carried
// into the Analytics tab with the same metrics, charts, filters and notes.
// Changes from that version, all for data honesty:
//  - an empty data set shows "—" / "No data yet", never 0% or 0.0 hrs;
//  - donations read `donations/` (what the app writes today) instead of
//    the `donors` collection group, which nothing writes any more;
//  - the adoption return rate counts real return requests that ended in a
//    retrieval/intake, not `releasedAt`;
//  - donation figures are visible to finance admins only.

enum AreaReport { rescue, adoption, donation, volunteers }

extension AreaReportX on AreaReport {
  String get label => switch (this) {
    AreaReport.rescue => 'Rescue',
    AreaReport.adoption => 'Adoptions',
    AreaReport.donation => 'Donations',
    AreaReport.volunteers => 'Volunteers',
  };
}

/// Every case staff may list (own organization, the unowned pool and
/// referrals; platform staff: all), read once.
final reportCasesProvider = FutureProvider.autoDispose<List<RescueCase>>((ref) async {
  final docs = await RescueCaseQueryRepository(RescueCaseStore(FirebaseFirestore.instance))
      .watchScopedCaseDocs((q) => q, includeReferred: true)
      .first;
  final cases = <RescueCase>[];
  for (final doc in docs) {
    try {
      cases.add(RescueCase.fromFirestore(doc));
    } catch (e) {
      debugPrint('[AreaReports] Skipping unparseable case ${doc.id}: $e');
    }
  }
  return cases;
});

/// Every transporter offer (`cases/{id}/transportAssignments`), read once.
/// Own organization's offers only (platform staff: all).
final reportAssignmentsProvider = FutureProvider.autoDispose<List<TransportAssignment>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance.collectionGroup('transportAssignments'),
    empty: const <TransportAssignment>[],
    (snap) => snap.docs.map((d) => TransportAssignment.fromFirestore(d, d.reference.parent.parent!.id)).toList(),
  ).first;
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
            AreaReport.volunteers => const _VolunteerReport(),
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
  AppColors.error,
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

  /// Legend value format; counts by default.
  final String Function(num)? valueLabel;
  const _PieChart({required this.data, this.valueLabel});

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
                    '${filtered[i].key} (${valueLabel?.call(filtered[i].value) ?? filtered[i].value.toInt()})',
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
  String _locationView = 'By city';

  static Map<String, num> _byPlace(List<RescueCase> cases, {required bool barangay}) {
    final out = <String, num>{};
    for (final c in cases) {
      final p = placeOf(c.address);
      final key = barangay
          ? (p.barangay == null ? null : (p.city == null ? p.barangay! : '${p.barangay}, ${p.city}'))
          : p.city;
      if (key == null) continue;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

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
        // Analytics gap 4: grouped from each report's saved address, or a
        // heat layer over the reported pins.
        _ChartBlock(
          title: 'Rescues by location (cases)',
          filterOptions: const ['By city', 'By barangay', 'Map'],
          selectedFilter: _locationView,
          onFilterChanged: (v) => setState(() => _locationView = v),
          height: _locationView == 'Map' ? 260 : 200,
          child: _locationView == 'Map'
              ? _CaseHeatmap(cases: cases)
              : _HorizontalBars(
                  data: _byPlace(cases, barangay: _locationView == 'By barangay'),
                  empty: 'No report addresses to group yet.',
                ),
        ),
        if (_locationView != 'Map')
          _note('From each report’s address. '
              '${cases.where((c) => (_locationView == 'By barangay' ? placeOf(c.address).barangay : placeOf(c.address).city) == null).length} '
              'without a readable ${_locationView == 'By barangay' ? 'barangay' : 'city'} are left out.'),
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

/// A heat layer over every case's reported pin.
class _CaseHeatmap extends StatelessWidget {
  const _CaseHeatmap({required this.cases});
  final List<RescueCase> cases;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final c in cases)
        if (c.lat case final lat? when lat != 0)
          if (c.lng case final lng? when lng != 0) LatLng(lat, lng),
    ];
    if (points.isEmpty) return const _EmptyChart('No reported locations yet.');
    final lat = points.fold<double>(0, (s, p) => s + p.latitude) / points.length;
    final lng = points.fold<double>(0, (s, p) => s + p.longitude) / points.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 11),
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        zoomControlsEnabled: true,
        // Pan and zoom the map instead of scrolling the page.
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
        heatmaps: {
          Heatmap(
            heatmapId: const HeatmapId('cases'),
            data: [for (final p in points) WeightedLatLng(p)],
            radius: const HeatmapRadius.fromPixels(30),
          ),
        },
      ),
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
        const _FundsBreakdown(),
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

/// Where the money went: per campaign (raised, spent, still available),
/// spending by category, and spending on each sponsored or animal-linked
/// fund. Built from campaign totals and their allocations.
class _FundsBreakdown extends ConsumerWidget {
  const _FundsBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(orgCampaignsProvider);
    final allocationsAsync = ref.watch(orgAllocationsProvider);
    final campaigns = campaignsAsync.asData?.value;
    final allocations = allocationsAsync.asData?.value;
    if (campaignsAsync.hasError || allocationsAsync.hasError) {
      return const _ChartBlock(title: 'Allocation summary', height: 64, child: _EmptyChart('Could not load fund data.'));
    }
    if (campaigns == null || allocations == null) {
      return const _ChartBlock(
        title: 'Allocation summary',
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final listed = campaigns.where((c) => c.type == 'donation' || c.type == 'sponsorship').where((c) => !c.isDraft).toList()
      ..sort((a, b) => b.collected.compareTo(a.collected));
    final known = {for (final c in listed) c.id};

    final byCategory = <String, num>{};
    final spentByCampaign = <String, double>{};
    for (final a in allocations) {
      if (a.entry.isTransfer || !known.contains(a.campaignId)) continue;
      byCategory[a.entry.category] = (byCategory[a.entry.category] ?? 0) + a.entry.amount;
      spentByCampaign[a.campaignId] = (spentByCampaign[a.campaignId] ?? 0) + a.entry.amount;
    }

    final byAnimal = <String, double>{};
    for (final c in listed) {
      final name = c.animalName?.trim() ?? '';
      if (name.isEmpty) continue;
      byAnimal[name] = (byAnimal[name] ?? 0) + (spentByCampaign[c.id] ?? c.allocatedAmount);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartBlock(
          title: 'Funds by campaign',
          height: (listed.length.clamp(1, 6) * 46 + 24).toDouble(),
          child: listed.isEmpty
              ? const _EmptyChart('No campaigns yet.')
              : _FundRows(rows: [
                  for (final c in listed)
                    (
                      label: c.title,
                      raised: c.collected + c.transferredInAmount,
                      spent: c.allocatedAmount,
                      available: c.availableBalance,
                    ),
                ]),
        ),
        _ChartBlock(
          title: 'Spending by category',
          height: _pieHeight(byCategory),
          child: _PieChart(data: byCategory, valueLabel: formatPeso),
        ),
        if (byAnimal.isNotEmpty)
          _ChartBlock(
            title: 'Spending by animal',
            height: (byAnimal.length.clamp(1, 6) * 30 + 8).toDouble(),
            child: _AmountList(data: byAnimal),
          ),
        _note('Spending is what was allocated from each campaign, including bills paid from it. '
            'Money moved to another campaign counts there, not here.'),
      ],
    );
  }
}

/// One row per campaign: title, then raised / spent / available.
class _FundRows extends StatelessWidget {
  final List<({String label, double raised, double spent, double available})> rows;
  const _FundRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: rows.length > 6 ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = rows[i];
        final spentShare = r.raised <= 0 ? 0.0 : (r.spent / r.raised).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dashBody(size: 12, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: spentShare,
                minHeight: 8,
                backgroundColor: AppColors.greenrspwn.withValues(alpha: 0.35),
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Raised ${formatPeso(r.raised)} · Spent ${formatPeso(r.spent)} · Available ${formatPeso(r.available)}',
              style: dashMuted(11),
            ),
          ],
        );
      },
    );
  }
}

/// Name and peso amount per line, largest first.
class _AmountList extends StatelessWidget {
  final Map<String, double> data;
  const _AmountList({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ListView.builder(
      physics: entries.length > 6 ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(entries[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: dashBody(size: 12))),
            Text(formatPeso(entries[i].value), style: dashBody(size: 12, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

// ─── Volunteers ──────────────────────────────────────────────────────────

/// One organization's events and their sign-ups (registrations are readable
/// only by the event organization's staff), read once.
typedef _VolunteerData = ({List<VolunteerEvent> events, Map<String, List<Map<String, dynamic>>> registrations});

final _volunteerReportProvider = FutureProvider.autoDispose<_VolunteerData?>((ref) async {
  final orgId = await ref.watch(currentOrganizationIdProvider.future);
  if (orgId == null || orgId.isEmpty) return null;
  final db = FirebaseFirestore.instance;
  final events = (await db.collection('events').where('organizationId', isEqualTo: orgId).get())
      .docs
      .map(VolunteerEvent.fromFirestore)
      .where((e) => !e.isCancelled)
      .toList();
  final regs = await Future.wait([
    for (final e in events) db.collection('events').doc(e.id).collection('registrations').get(),
  ]);
  return (
    events: events,
    registrations: {
      for (var i = 0; i < events.length; i++) events[i].id: [for (final d in regs[i].docs) {'uid': d.id, ...d.data()}],
    },
  );
});

class _VolunteerReport extends ConsumerStatefulWidget {
  const _VolunteerReport();

  @override
  ConsumerState<_VolunteerReport> createState() => _VolunteerReportState();
}

class _VolunteerReportState extends ConsumerState<_VolunteerReport> {
  String _monthFilter = 'Last 6 months';

  @override
  Widget build(BuildContext context) {
    return DashAsync<_VolunteerData?>(
      value: ref.watch(_volunteerReportProvider),
      what: 'volunteer events',
      builder: (data) => data == null
          ? const RestrictedNotice('Volunteer reports are per organization. Link this account to one to see them.')
          : _content(data),
    );
  }

  Widget _content(_VolunteerData data) {
    final held = data.events.where((e) => e.isPast).toList();
    final upcoming = data.events.length - held.length;
    var signUps = 0;
    var marked = 0;
    var attended = 0;
    final attendedByUid = <String, int>{};
    final nameOf = <String, String>{};
    final byMonth = <String, num>{};
    for (final e in data.events) {
      final regs = data.registrations[e.id] ?? const [];
      signUps += regs.length;
      for (final r in regs) {
        final uid = r['uid'] as String;
        final name = (r['participantName'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) nameOf[uid] = name;
        final came = r['attended'];
        if (came is bool) marked++;
        if (came == true) {
          attended++;
          attendedByUid[uid] = (attendedByUid[uid] ?? 0) + 1;
          final key = _monthKey(e.startAt);
          byMonth[key] = (byMonth[key] ?? 0) + 1;
        }
      }
    }
    final volunteers = {for (final regs in data.registrations.values) for (final r in regs) r['uid'] as String}.length;
    final returning = attendedByUid.values.where((n) => n >= 2).length;

    final n = switch (_monthFilter) {
      'Last 3 months' => 3,
      'Last 12 months' => 12,
      _ => 6,
    };
    final now = DateTime.now();
    final months = [for (int i = n - 1; i >= 0; i--) _monthKey(DateTime(now.year, now.month - i))];
    final top = (attendedByUid.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(label: 'Events held', value: held.length, caption: upcoming == 0 ? null : '$upcoming upcoming'),
            MetricTile(label: 'Sign-ups', value: signUps, caption: '$volunteers volunteer${volunteers == 1 ? '' : 's'}'),
            MetricTile(
              label: 'Attendance rate',
              valueText: _pct(attended, marked),
              caption: marked == 0 ? 'No attendance taken yet' : '$attended of $marked marked',
            ),
            MetricTile(
              label: 'Returning volunteers',
              value: returning,
              caption: 'Came to 2+ of your events',
            ),
          ],
        ),
        _note('Attendance rate counts only sign-ups where staff marked who came. Cancelled events are left out.'),
        _ChartBlock(
          title: 'Volunteers who came, by month',
          filterOptions: const ['Last 3 months', 'Last 6 months', 'Last 12 months'],
          selectedFilter: _monthFilter,
          onFilterChanged: (v) => setState(() => _monthFilter = v),
          child: _BarChart(
            data: {for (final m in months) _monthLabel(m): byMonth[m] ?? 0},
            color: AppColors.greenrspwn,
          ),
        ),
        _ChartBlock(
          title: 'Most events attended',
          height: (top.length.clamp(1, 5) * 24 + 8).toDouble(),
          child: _HorizontalBars(
            data: {for (final e in top) nameOf[e.key] ?? 'Volunteer': e.value},
            empty: 'No attendance marked yet.',
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
