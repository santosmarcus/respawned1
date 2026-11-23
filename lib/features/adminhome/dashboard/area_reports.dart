import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart' show DashSeverity, RescueStage, isInCare;
import 'package:respawnd1/core/utils/org_list_scope.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_query_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart' show currentOrganizationIdProvider;
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_view.dart' show analyticsPeriodProvider;
import 'package:respawnd1/features/adminhome/dashboard/case_location.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/adoption_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/finance_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/operations_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/rescue_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/donation/models.dart' show DonationListing;

// ─── Reports by area ────────────────────────────────────────────────────
//
// The organization's KPIs by area: Rescue, Adoptions, Donations, Shelter,
// and Volunteers & transporters. Every figure follows the Analytics period
// picker and is computed from stored records by the pure calculators in
// reports/ (each with its definition and denominator there). Rules:
//  - an empty data set shows "—" / "No data yet", never 0% or 0.0 hrs;
//  - rates show their fraction; pending or in-progress records are left out
//    of a rate, not counted as failures;
//  - animals are counted as animals, not case documents;
//  - money, in-kind quantities and counts are never added together;
//  - donation figures are visible to finance staff only.
// The data streams live, so the reports update as records change.

enum AreaReport { rescue, adoption, donation, shelter, people }

extension AreaReportX on AreaReport {
  String get label => switch (this) {
    AreaReport.rescue => 'Rescue',
    AreaReport.adoption => 'Adoptions',
    AreaReport.donation => 'Donations',
    AreaReport.shelter => 'Shelter',
    AreaReport.people => 'Volunteers & transporters',
  };
}

/// Every case staff may list (own organization, the unowned pool and
/// referrals; platform staff: all), kept live.
final reportCasesProvider = StreamProvider.autoDispose<List<RescueCase>>((ref) {
  return RescueCaseQueryRepository(RescueCaseStore(FirebaseFirestore.instance))
      .watchScopedCaseDocs((q) => q, includeReferred: true)
      .map((docs) {
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
});

/// Every transporter offer (`cases/{id}/transportAssignments`), kept live.
/// Own organization's offers only (platform staff: all).
final reportAssignmentsProvider = StreamProvider.autoDispose<List<TransportAssignment>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance.collectionGroup('transportAssignments'),
    empty: const <TransportAssignment>[],
    (snap) => snap.docs.map((d) => TransportAssignment.fromFirestore(d, d.reference.parent.parent!.id)).toList(),
  );
});

/// The same offers as raw documents, for the transport calculators.
final reportOfferDocsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance.collectionGroup('transportAssignments'),
    empty: const <Map<String, dynamic>>[],
    (snap) => [for (final d in snap.docs) {...d.data(), 'caseId': d.data()['caseId'] ?? d.reference.parent.parent?.id}],
  );
});

/// Listing engagement counters (animals/{id}/engagement/{day}).
final reportEngagementProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance.collectionGroup('engagement'),
    empty: const <Map<String, dynamic>>[],
    (snap) => [for (final d in snap.docs) {...d.data(), 'animalId': d.reference.parent.parent?.id}],
  );
});

/// Every follow-up of the organization's adoptions. Filtering on every
/// status uses the existing (organizationId, status) index.
final reportFollowUpsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return OrgListScope.watch(
    FirebaseFirestore.instance
        .collectionGroup('followUps')
        .where('status', whereIn: [for (final s in FollowUpStatus.values) s.name]),
    empty: const <Map<String, dynamic>>[],
    (snap) => [for (final d in snap.docs) d.data()],
  );
});

/// The organization's stock changes (in-kind used), newest 1,000.
final reportStockMovementsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
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
      .limit(1000)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());
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
    final range = ref.watch(analyticsPeriodProvider);
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
          const SizedBox(height: 6),
          Text('${range.label} · compared with ${range.previousLabel}', style: dashMuted(11.5)),
          const SizedBox(height: 8),
          switch (area) {
            AreaReport.rescue => const _RescueReport(),
            AreaReport.adoption => const _AdoptionReport(),
            AreaReport.donation => const _DonationReport(),
            AreaReport.shelter => const _ShelterReport(),
            AreaReport.people => const _PeopleReport(),
          },
        ],
      ),
    );
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────


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

  /// Size to the child (text rows that wrap) instead of a fixed height.
  final bool fitContent;

  const _ChartBlock({
    required this.title,
    required this.child,
    this.filterOptions,
    this.selectedFilter,
    this.onFilterChanged,
    this.height = 170,
    this.fitContent = false,
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
          if (fitContent)
            child
          else
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

  /// Value format (pesos, quantities); whole counts by default.
  final String Function(num)? valueLabel;
  const _HorizontalBars({required this.data, this.empty = 'No data yet.', this.valueLabel});

  @override
  bool get isEmpty => !data.values.any((v) => v > 0);

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _EmptyChart(empty);
    final maxValue = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

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
              width: valueLabel == null ? 28 : 84,
              child: Text(
                valueLabel?.call(e.value) ?? '${e.value.toInt()}',
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

// ─── Report helpers ──────────────────────────────────────────────────────

String _hrs(double? h) => h == null ? '—' : (h < 48 ? '${h.toStringAsFixed(1)} hrs' : '${(h / 24).toStringAsFixed(1)} days');
String _days(double? d) => d == null ? '—' : '${d.toStringAsFixed(d < 10 ? 1 : 0)} days';
String _mins(double? m) => m == null ? '—' : (m < 90 ? '${m.round()} min' : _hrs(m / 60));
String _qty(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

/// "12 of 40 reports" (+ "small sample" under kMinGroupSize, + what it was).
String _of(Ratio r, String what, {Ratio? before}) {
  if (r.whole == 0) return 'None $what yet';
  final was = before == null || before.whole == 0 ? '' : ' · was ${before.percent}';
  return '${r.fraction} $what${r.small ? ' · small sample' : ''}$was';
}

String _wasCount(int before) => 'was $before';

Widget _heading(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 6),
  child: Text(text, style: dashBody(size: 14, weight: FontWeight.w800)),
);

double _barsHeight(Map<String, num> data) =>
    (data.values.where((v) => v > 0).length.clamp(1, 7) * 28 + 8).toDouble();

/// Loading / error for several sources at once.
Widget _whenAll(List<AsyncValue<Object?>> values, String what, Widget Function() build) {
  for (final v in values) {
    if (v.hasError) return DashError(what: what, error: v.error!);
  }
  if (values.any((v) => !v.hasValue)) return DashLoading(label: 'Loading $what…');
  return build();
}

Map<String, dynamic> _caseDoc(RescueCase c) => {...c.raw, 'id': c.id};
Map<String, dynamic> _animalDoc(AnimalRecord a) => {...a.raw, 'id': a.id};
Map<String, dynamic> _adoptionDoc(AdoptionApplication a) => {...a.raw, 'id': a.id, 'animalRecordId': a.animalRecordId ?? ''};

/// Labelled rows of a figure and a note, for stages that aren't all
/// measured the same way (the promotion funnel).
class _StageRows extends StatelessWidget {
  const _StageRows(this.rows);
  final List<({String label, String value, String? note, bool unavailable})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: dashMuted(12))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rows[i].label, style: dashBody(size: 12.5, weight: FontWeight.w700)),
                      if (rows[i].note != null) Text(rows[i].note!, style: dashMuted(11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rows[i].value,
                  style: rows[i].unavailable ? dashMuted(12) : dashBody(size: 13, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One row per item: progress toward an amount.
class _ProgressRows extends StatelessWidget {
  const _ProgressRows(this.rows);
  final List<({String label, double value, double of, String text})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dashBody(size: 12, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                DashProgress(fraction: r.of <= 0 ? 0 : r.value / r.of, semanticsLabel: '${r.label} ${r.text}'),
                const SizedBox(height: 2),
                Text(r.text, style: dashMuted(11)),
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
  String _locationView = 'By city';

  static Map<String, num> _byPlace(Iterable<RescueCase> cases, {required bool barangay}) {
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
    final casesA = ref.watch(reportCasesProvider);
    final offersA = ref.watch(reportOfferDocsProvider);
    return _whenAll([casesA, offersA], 'rescue cases', () => _content(casesA.requireValue, offersA.requireValue));
  }

  Widget _content(List<RescueCase> all, List<Map<String, dynamic>> offers) {
    final p = ref.watch(analyticsPeriodProvider).period(DateTime.now());
    final prev = p.previous;
    final occ = ref.watch(shelterOccupancyProvider).asData?.value;
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final supply = ref.watch(transportSupplyProvider).asData?.value;

    final docs = all.map(_caseDoc).toList();
    final orgCases = [for (var i = 0; i < all.length; i++) if (isOrgCase(docs[i])) all[i]];
    final reported = orgCases.where((c) => p.has(c.createdAt)).toList();
    final reportedBefore = orgCases.where((c) => prev.has(c.createdAt)).length;
    final animalsReported = reported.fold<int>(0, (s, c) => s + c.animalCount);

    final referrals = referralStatsIn(p, docs);
    final referralsBefore = referralStatsIn(prev, docs);
    final outcomes = rescueOutcomesIn(p, docs);
    final outcomesBefore = rescueOutcomesIn(prev, docs);
    final response = responseHoursIn(p, docs);
    final completion = completionHoursIn(p, docs);
    final transport = transportStatsIn(p, offers);
    final transportBefore = transportStatsIn(prev, offers);
    final housed = occ == null ? null : occ.inShelter + occ.isolation;

    final byUrgency = <String, num>{'Critical': 0, 'Medium': 0, 'Low': 0};
    final bySpecies = <String, num>{};
    final byRescueType = <String, num>{};
    for (final c in reported) {
      if (c.urgency != null && byUrgency.containsKey(c.urgency)) byUrgency[c.urgency!] = byUrgency[c.urgency]! + 1;
      for (final s in c.allSpecies) {
        final n = _normalizedSpecies(s);
        if (n != null) bySpecies[n] = (bySpecies[n] ?? 0) + 1;
      }
      final rt = (c.raw['rescueType'] as String?)?.trim();
      if (rt != null && rt.isNotEmpty) byRescueType[rt] = (byRescueType[rt] ?? 0) + 1;
    }
    // Same denormalized counts the Rescue Reports tabs use: where animals
    // are right now, whatever the period.
    final byAnimalStage = <String, num>{};
    for (final c in orgCases) {
      c.animalStageCounts.forEach((stage, n) {
        final label = switch (stage) {
          'intake' => 'Intake',
          'in_treatment' => 'In Treatment',
          _ => stage,
        };
        byAnimalStage[label] = (byAnimalStage[label] ?? 0) + n;
      });
    }
    final outcomeBars = <String, num>{
      for (final o in RescueOutcome.values)
        if (outcomes.byOutcome[o]! > 0) o.label: outcomes.byOutcome[o]!,
    };
    int count(List<RescueOutcome> os) => os.fold(0, (s, o) => s + outcomes.byOutcome[o]!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(
              label: 'Reports received',
              value: reported.length,
              caption: '$animalsReported animals · ${_wasCount(reportedBefore)}',
            ),
            MetricTile(
              label: 'Referral rate',
              valueText: referrals.referralRate.percent,
              caption: _of(referrals.referralRate, 'reviewed reports referred', before: referralsBefore.referralRate),
            ),
            MetricTile(
              label: 'Successful rescue rate',
              valueText: outcomes.successRate.percent,
              caption: _of(outcomes.successRate, 'animals with a decided rescue', before: outcomesBefore.successRate),
            ),
            MetricTile(
              label: 'Treatment rate',
              valueText: outcomes.treatmentRate.percent,
              caption: _of(outcomes.treatmentRate, 'rescued animals saw a vet'),
            ),
            MetricTile(
              label: 'Avg rescue response time',
              valueText: _hrs(response.average),
              caption: response.isEmpty
                  ? 'No report accepted yet'
                  : 'Report to accepted · median ${_hrs(response.median)} · ${response.count} cases',
            ),
            MetricTile(
              label: 'Avg rescue completion time',
              valueText: _hrs(completion.average),
              caption: completion.isEmpty
                  ? 'No rescue completed yet'
                  : 'Report to clinic or shelter · median ${_hrs(completion.median)} · ${completion.count} cases',
            ),
            MetricTile(
              label: 'Transport completion rate',
              valueText: transport.completion.percent,
              caption: _of(transport.completion, 'accepted trips that ended', before: transportBefore.completion),
            ),
            MetricTile(
              label: 'Transporter utilization',
              valueText: supply == null ? '—' : transport.utilization(supply.verified).percent,
              caption: supply == null
                  ? 'Loading transporters'
                  : '${transport.activeTransporters} of ${supply.verified} verified transporters made a trip · '
                      '${transport.tripsCompleted} trips',
            ),
            MetricTile(
              label: 'Shelter capacity utilization',
              valueText: housed == null || settings.capacity == null ? '—' : Ratio(housed, settings.capacity!).percent,
              caption: settings.capacity == null
                  ? 'Set shelter spaces in Shelter settings'
                  : '${housed ?? '—'} of ${settings.capacity} spaces, now',
            ),
            MetricTile(
              label: 'Treatment capacity utilization',
              valueText: occ == null || settings.treatmentCapacity == null
                  ? '—'
                  : Ratio(occ.atVet, settings.treatmentCapacity!).percent,
              caption: settings.treatmentCapacity == null
                  ? 'Set treatment spots in Shelter settings'
                  : '${occ?.atVet ?? '—'} of ${settings.treatmentCapacity} treatment spots, now',
            ),
          ],
        ),
        _note('Referral rate: reports referred out of the reports whose review ended in the period. Successful rescue: '
            'animals picked up, out of animals in cases accepted in the period whose rescue is decided; '
            'rescues still under way, reunions with the owner and cases referred on are left out. Treatment rate: rescued '
            'animals that went to a vet. Shelter use counts animals housed (with isolation), not animals at the vet; '
            'treatment use counts animals at the vet against treatment spots.'),
        _heading('Cases accepted this period'),
        MetricGrid(
          tiles: [
            MetricTile(label: 'Accepted cases', value: outcomes.acceptedCases),
            MetricTile(label: 'Referred cases', value: referrals.referred,
                caption: '${referrals.toOrganization} org · ${referrals.toVolunteer} volunteer · ${referrals.toBarangay} barangay'),
            MetricTile(label: 'Animals rescued', value: outcomes.rescuedAnimals),
            MetricTile(label: 'Under treatment', value: outcomes.byOutcome[RescueOutcome.inTreatment]),
            MetricTile(label: 'Recovered', value: outcomes.recoveredAnimals, caption: 'Discharged alive'),
            MetricTile(label: 'Integrated into the shelter', value: outcomes.byOutcome[RescueOutcome.shelter]),
            MetricTile(
              label: 'Other recorded outcomes',
              value: count([
                RescueOutcome.adopter, RescueOutcome.reporter, RescueOutcome.transferred,
                RescueOutcome.reunited, RescueOutcome.died, RescueOutcome.other,
              ]),
              caption: 'Adopter, reporter, transfer, owner, died',
            ),
          ],
        ),
        _ChartBlock(
          title: 'Rescue outcomes (animals in cases accepted this period)',
          height: _barsHeight(outcomeBars),
          child: _HorizontalBars(data: outcomeBars, empty: 'No case was accepted in this period.'),
        ),
        _ChartBlock(title: 'Reports and urgency (cases)', child: _BarChart(data: byUrgency)),
        _ChartBlock(
          title: 'Rescues by location (cases)',
          filterOptions: const ['By city', 'By barangay', 'Map'],
          selectedFilter: _locationView,
          onFilterChanged: (v) => setState(() => _locationView = v),
          height: _locationView == 'Map' ? 260 : 200,
          child: _locationView == 'Map'
              ? _CaseHeatmap(cases: reported)
              : _HorizontalBars(
                  data: _byPlace(reported, barangay: _locationView == 'By barangay'),
                  empty: 'No report addresses to group yet.',
                ),
        ),
        if (_locationView != 'Map')
          _note('From each report’s address. '
              '${reported.where((c) => (_locationView == 'By barangay' ? placeOf(c.address).barangay : placeOf(c.address).city) == null).length} '
              'without a readable ${_locationView == 'By barangay' ? 'barangay' : 'city'} are left out.'),
        _ChartBlock(title: 'Reports by rescue type (cases)', child: _BarChart(data: byRescueType)),
        _ChartBlock(title: 'Animals by species', child: _BarChart(data: bySpecies)),
        _ChartBlock(title: 'Animals by current stage (now)', child: _BarChart(data: byAnimalStage)),
        _note('Pet Surrender reports go to Community Adoption and are not counted here. '
            'Acceptance and pickup times are recorded from Nov 2026; earlier acceptances are read from the case timeline.'),
      ],
    );
  }
}

/// Animals listed now that may need a push, with their flags.
class _AttentionRows extends StatelessWidget {
  const _AttentionRows(this.rows);
  final List<ListingRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyChart('No listed animal needs attention.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name, style: dashBody(size: 12.5, weight: FontWeight.w800)),
                Text(
                  '${r.daysListed == null ? 'Listing date not recorded' : 'Listed ${r.daysListed} days'} · '
                  '${r.views} views · ${r.saves} saves · ${r.applications} applications',
                  style: dashMuted(11),
                ),
                const SizedBox(height: 3),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final f in r.flags) DashTag(f.label)]),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Adoptions ───────────────────────────────────────────────────────────

class _AdoptionReport extends ConsumerWidget {
  const _AdoptionReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalsA = ref.watch(allAnimalRecordsProvider);
    final appsA = ref.watch(allAdoptionsProvider);
    final followA = ref.watch(reportFollowUpsProvider);
    final engageA = ref.watch(reportEngagementProvider);
    return _whenAll([animalsA, appsA, followA, engageA], 'adoptions', () {
      final now = DateTime.now();
      final p = ref.watch(analyticsPeriodProvider).period(now);
      final prev = p.previous;
      final animals = animalsA.requireValue.map(_animalDoc).toList();
      final appModels = appsA.requireValue;
      final apps = appModels.map(_adoptionDoc).toList();
      final engagement = engageA.requireValue;

      final stay = intakeToAdoptionDaysIn(p, animals);
      final rate = adoptionRateIn(p, animals);
      final rateBefore = adoptionRateIn(prev, animals);
      final follow = followUpStatsIn(p, followA.requireValue, now);
      final returns = returnStatsIn(p, apps, animals, now);
      final funnel = adoptionFunnelIn(p, engagement, apps);
      final flagged = listingRows(p, animals, engagement, apps, now, trackingSince: funnel.trackingSince)
          .where((r) => r.flags.isNotEmpty)
          .take(8)
          .toList();

      final byStatus = <String, num>{};
      for (final a in appModels.where((a) => p.has(a.createdAt))) {
        byStatus[a.status.label] = (byStatus[a.status.label] ?? 0) + 1;
      }
      final tracking = funnel.trackingSince == null
          ? 'Recorded from this update on; nothing recorded yet.'
          : 'Recorded since ${funnel.trackingSince!.month}/${funnel.trackingSince!.day}/${funnel.trackingSince!.year}.';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Intake to adoption',
                valueText: _days(stay.average),
                caption: stay.isEmpty ? 'No adoption in this period' : 'Average · median ${_days(stay.median)} · ${stay.count} animals',
              ),
              MetricTile(
                label: 'Adoption rate',
                valueText: rate.percent,
                caption: _of(rate, 'animals available were adopted', before: rateBefore),
              ),
              MetricTile(
                label: 'Adoption success rate',
                valueText: returns.success.percent,
                caption: returns.success.whole == 0
                    ? 'No adoption here has finished its $kSuccessWindowDays days yet'
                    : '${returns.success.fraction} kept past $kSuccessWindowDays days',
              ),
              MetricTile(
                label: 'Post-adoption response rate',
                valueText: follow.responses.percent,
                caption: _of(follow.responses, 'due check-ins answered by the adopter'),
              ),
              MetricTile(
                label: 'Follow-up completion rate',
                valueText: follow.completion.percent,
                caption: _of(follow.completion, 'due check-ins closed by staff'),
              ),
              MetricTile(
                label: 'Check-ins overdue now',
                value: follow.overdueNow,
                severity: follow.overdueNow > 0 ? DashSeverity.warning : null,
              ),
            ],
          ),
          _note('Adoption rate: animals adopted out of animals available for adoption at some point in the period. '
              'Success: adoptions handed over in the period and not returned within $kSuccessWindowDays days; adoptions '
              'still inside their $kSuccessWindowDays days aren\'t measured yet. Check-ins not yet due are left out.'),
          _ChartBlock(
            title: 'Adoption promotion funnel',
            fitContent: true,
            child: _StageRows([
              (
                label: 'Listing reach',
                value: 'Not available',
                note: 'Needs Facebook Page Insights, which isn\'t connected; ResPAWnd can\'t see how many people a post reached.',
                unavailable: true,
              ),
              (label: 'Listing engagement (profile views)', value: '${funnel.views}', note: 'Passive: people who opened a profile, once a day. $tracking', unavailable: false),
              (label: 'Expressions of interest (saves)', value: '${funnel.saves}', note: '${funnel.viewToSave.percent} of views', unavailable: false),
              (
                label: 'Adoption inquiries',
                value: 'Not tracked',
                note: 'Shelter animals have no "ask about this animal" step; people apply directly.',
                unavailable: true,
              ),
              (label: 'Applications submitted', value: '${funnel.applications}', note: '${funnel.viewToApplication.percent} of views', unavailable: false),
              (label: 'Approved', value: '${funnel.approved}', note: '${funnel.applicationToApproval.percent} of applications', unavailable: false),
              (label: 'Completed adoptions', value: '${funnel.adopted}', note: '${funnel.approvalToAdoption.percent} of approved', unavailable: false),
            ]),
          ),
          _note('Views and saves are passive engagement; only applications count as adoption interest. '
              'Applications, approvals and adoptions follow the applications submitted in this period.'),
          _ChartBlock(
            title: 'Listed animals that need attention',
            fitContent: true,
            child: _AttentionRows(flagged),
          ),
          _note('Flags: $kHighViews+ views or $kHighSaves+ saves with no application, listed $kLongListedDays+ days, or under '
              '$kLowViews views after $kLowViewsAfterDays days listed (only once views were recorded for its whole listing).'),
          _ChartBlock(title: 'Screening and application outcomes', child: _BarChart(data: byStatus)),
          _heading('Returns'),
          MetricGrid(
            tiles: [
              MetricTile(label: 'Total returns', value: returns.total, caption: 'Asked for in this period'),
              MetricTile(
                label: 'Return rate',
                valueText: returns.returnRate.percent,
                caption: returns.returnRate.whole == 0
                    ? 'Measured once adoptions pass $kSuccessWindowDays days'
                    : '${returns.returnRate.fraction} returned within $kSuccessWindowDays days',
              ),
              MetricTile(
                label: 'Avg time before return',
                valueText: _days(returns.daysBeforeReturn.average),
                caption: returns.daysBeforeReturn.isEmpty ? 'No return yet' : 'From handover · median ${_days(returns.daysBeforeReturn.median)}',
              ),
              MetricTile(
                label: 'Rehomed after return',
                valueText: returns.rehomed.percent,
                caption: _of(returns.rehomed, 'returned animals adopted again'),
              ),
            ],
          ),
          _ChartBlock(
            title: 'Why animals were returned',
            height: _barsHeight(returns.reasons),
            child: _HorizontalBars(data: returns.reasons, empty: 'No return in this period.'),
          ),
          _ChartBlock(
            title: 'Where returned animals are now',
            height: _barsHeight(returns.statusNow),
            child: _HorizontalBars(data: returns.statusNow, empty: 'No return in this period.'),
          ),
          _note('A return is a request that went ahead (approved, retrieved or back at intake); requests in review, '
              'declined or cancelled aren\'t counted.'),
        ],
      );
    });
  }
}

// ─── Donations ───────────────────────────────────────────────────────────

DonationRow _donationRow(DonationHistoryRecord d) => DonationRow(
      amount: d.amountValue,
      type: d.type,
      status: d.status,
      method: d.method,
      at: d.when,
      campaignId: d.campaignId,
      campaignName: d.campaignName,
      generalFund: d.generalFund,
      category: d.category,
      quantity: d.quantityReceived,
      reversedAt: d.reversedAt,
    );

FundRow _fundRow(DonationListing c) => (
      title: c.title,
      type: c.type,
      animalName: c.animalName,
      target: c.target,
      collected: c.collected,
      transferredIn: c.transferredInAmount,
      transferredOut: c.transferredOutAmount,
      spent: c.allocatedAmount,
      monthlyAmount: c.monthlyAmount,
      fullyFunded: c.isFullyFunded,
      draft: c.isDraft,
      goalMet: c.isGoalMet,
    );

class _DonationReport extends ConsumerWidget {
  const _DonationReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canViewFinancesProvider).asData?.value ?? false;
    if (!canView) return const RestrictedNotice('Donation figures are visible to finance staff only.');
    final donationsA = ref.watch(allDonationsProvider);
    final caseExpensesA = ref.watch(allCaseExpensesProvider);
    final campaignsA = ref.watch(orgCampaignsProvider);
    return _whenAll([donationsA, caseExpensesA, campaignsA], 'donations and expenses', () {
      final p = ref.watch(analyticsPeriodProvider).period(DateTime.now());
      final prev = p.previous;
      // General expenses are readable only by people who manage money.
      final general = ref.watch(myGeneralExpensesProvider);
      final stock = ref.watch(stockItemsProvider).asData?.value ?? const <StockItem>[];
      final movements = ref.watch(reportStockMovementsProvider).asData?.value ?? const <Map<String, dynamic>>[];

      final records = donationsA.requireValue;
      final rows = records.map(_donationRow).toList();
      final money = moneyReceivedIn(p, rows);
      final moneyBefore = moneyReceivedIn(prev, rows);
      final expenses = [...caseExpensesA.requireValue, ...(general.asData?.value ?? const <Expense>[])];
      final spent = expensesIn(p, expenses);
      final funds = campaignsA.requireValue.map(_fundRow).toList();
      final fundStats = fundStatsOf(funds);
      final sponsor = sponsorshipStatsOf(funds);
      final inKind = inKindStatsIn(
        p,
        donations: rows,
        movements: movements,
        stock: [for (final s in stock) (name: s.name, category: s.category, unit: s.unit, quantity: s.quantity)],
      );

      // Repeat donors among those who gave in the period: gave to 2+ funds.
      final fundsByDonor = <String, Set<String>>{};
      final firstGift = <String, DateTime>{};
      for (final d in records.where((d) => isMoneyReceived(_donationRow(d)))) {
        final uid = d.userId;
        final when = d.when;
        if (uid == null || when == null) continue;
        if (firstGift[uid] == null || when.isBefore(firstGift[uid]!)) firstGift[uid] = when;
        if (p.has(when)) fundsByDonor.putIfAbsent(uid, () => <String>{}).add(d.campaignId);
      }
      final retention = Ratio(fundsByDonor.values.where((c) => c.length > 1).length, fundsByDonor.length);
      final utilization = Ratio((fundStats.utilization.spent * 100).round(), (fundStats.utilization.raised * 100).round());
      final completion = Ratio(
        (fundStats.targetCompletion.raised * 100).round(),
        (fundStats.targetCompletion.target * 100).round(),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Money received',
                valueText: formatPeso(money.total),
                caption: '${money.count} donations · was ${formatPeso(moneyBefore.total)}',
              ),
              MetricTile(
                label: 'Average donation',
                valueText: money.count == 0 ? '—' : formatPeso(money.total / money.count),
              ),
              MetricTile(
                label: 'Not assigned to a fund',
                valueText: formatPeso(money.unallocated),
                caption: 'Given to the general fund',
              ),
              MetricTile(
                label: 'Reversed or refunded',
                valueText: formatPeso(money.reversed),
                caption: '${money.reversedCount} donations · not in money received',
              ),
              MetricTile(
                label: 'Donor retention rate',
                valueText: retention.percent,
                caption: _of(retention, 'signed-in donors gave to 2+ funds'),
              ),
            ],
          ),
          _note('Money received counts each payment or manual entry once; pending, failed, reversed and refunded ones '
              'are left out. In-kind gifts are counted below, in quantities.'
              '${records.length >= 500 ? ' Based on the latest 500 donation records.' : ''}'),
          _ChartBlock(
            title: 'Received by payment channel',
            height: _pieHeight(money.byChannel),
            child: _PieChart(data: money.byChannel, valueLabel: formatPeso),
          ),
          _ChartBlock(
            title: 'Received by fund (campaign or animal)',
            height: _barsHeight(money.byFund),
            child: _HorizontalBars(data: money.byFund, valueLabel: formatPeso, empty: 'No money received in this period.'),
          ),
          _ChartBlock(
            title: 'Money received over the period',
            child: _BarChart(
              data: bucketed<DonationRow>(p, rows.where(isMoneyReceived), (d) => d.at, (d) => d.amount),
              valueLabel: formatPeso,
              color: AppColors.greenrspwn,
            ),
          ),
          _ChartBlock(
            title: 'New donors over the period',
            child: _BarChart(
              data: bucketed<DateTime>(p, firstGift.values, (t) => t, (_) => 1),
              color: AppColors.lavenderrspwn,
            ),
          ),
          _heading('Fundraising'),
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Fundraising target completion',
                valueText: completion.percent,
                caption: completion.whole == 0
                    ? 'No campaign with a target'
                    : '${formatPeso(fundStats.targetCompletion.raised)} of ${formatPeso(fundStats.targetCompletion.target)}',
              ),
              MetricTile(
                label: 'Campaigns that reached their goal',
                valueText: fundStats.goalsReached.percent,
                caption: _of(fundStats.goalsReached, 'campaigns with a target'),
              ),
            ],
          ),
          const _FundsBreakdown(),
          _heading('Expenses'),
          MetricGrid(
            tiles: [
              MetricTile(label: 'Total expenses', valueText: formatPeso(spent.total), caption: 'Recorded in this period'),
              for (final g in ExpenseGroup.values) MetricTile(label: g.label, valueText: formatPeso(spent.byGroup[g]!)),
              MetricTile(
                label: 'Remaining available funds',
                valueText: formatPeso(fundStats.available),
                caption: 'Across all funds, now',
              ),
              MetricTile(
                label: 'Fund utilization rate',
                valueText: utilization.percent,
                caption: utilization.whole == 0
                    ? 'No money raised into funds yet'
                    : '${formatPeso(fundStats.utilization.spent)} spent of ${formatPeso(fundStats.utilization.raised)} raised, all time',
              ),
            ],
          ),
          _note('Expenses are the case and general expense records, so a bill paid from a fund is counted once. '
              'Veterinary: consultation, medication, procedures, laboratory, vaccination, confinement. Rescue: transport. '
              'Shelter: food and supplies, rent, utilities. Operational: staff, administrative, other.'
              '${spent.awaitingApproval > 0 ? ' ${formatPeso(spent.awaitingApproval)} is still waiting for approval.' : ''}'
              '${general.hasError ? ' General expenses are visible only to people who manage money.' : ''}'),
          _heading('In-kind donations'),
          _ChartBlock(
            title: 'Received, by category (quantity)',
            height: _barsHeight(inKind.receivedByCategory),
            child: _HorizontalBars(data: inKind.receivedByCategory, valueLabel: _qty, empty: 'No in-kind donation received in this period.'),
          ),
          _ChartBlock(
            title: 'Used or given out (stock)',
            height: _barsHeight({for (final e in inKind.usedByItem.entries) e.key: e.value.quantity}),
            child: _HorizontalBars(
              data: {for (final e in inKind.usedByItem.entries) '${e.key}${e.value.unit.isEmpty ? '' : ' (${e.value.unit})'}': e.value.quantity},
              valueLabel: _qty,
              empty: 'No stock use recorded in this period.',
            ),
          ),
          _ChartBlock(
            title: 'Remaining inventory (now)',
            height: _barsHeight(inKind.onHandByCategory),
            child: _HorizontalBars(data: inKind.onHandByCategory, valueLabel: _qty, empty: 'Nothing in stock.'),
          ),
          _note('Quantities only, never added to money. Items currently in use and expired or unusable items aren\'t '
              'tracked in Stock, so they can\'t be shown.'),
          _heading('Sponsorship'),
          MetricGrid(
            tiles: [
              MetricTile(label: 'Sponsored animals', value: sponsor.animals),
              MetricTile(label: 'Sponsorship received', valueText: formatPeso(money.sponsorship), caption: 'In this period'),
              MetricTile(label: 'Fully funded', value: sponsor.fullyFunded),
              MetricTile(label: 'Underfunded', value: sponsor.underfunded,
                  severity: sponsor.underfunded > 0 ? DashSeverity.warning : null),
              MetricTile(label: 'Still needed', valueText: formatPeso(sponsor.outstanding), caption: 'This month, across underfunded animals'),
            ],
          ),
          _ChartBlock(
            title: 'Funding progress per animal',
            fitContent: true,
            child: sponsor.progress.isEmpty
                ? const _EmptyChart('No sponsorship with a monthly amount.')
                : _ProgressRows([
                    for (final s in sponsor.progress.take(8))
                      (label: s.name, value: s.available, of: s.monthly, text: '${formatPeso(s.available)} of ${formatPeso(s.monthly)} a month'),
                  ]),
          ),
          if (sponsor.noMonthlyAmount > 0)
            _note('${sponsor.noMonthlyAmount} sponsorship${sponsor.noMonthlyAmount == 1 ? ' has' : 's have'} no monthly '
                'amount, so funded or not can\'t be told.'),
        ],
      );
    });
  }
}

/// Where the money went per fund: raised, spent, still available, and
/// spending on each animal's fund. Built from campaign totals and their
/// allocations (the fund side; expenses above are the ledger side).
class _FundsBreakdown extends ConsumerWidget {
  const _FundsBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(orgCampaignsProvider);
    final allocationsAsync = ref.watch(orgAllocationsProvider);
    final campaigns = campaignsAsync.asData?.value;
    final allocations = allocationsAsync.asData?.value;
    if (campaignsAsync.hasError || allocationsAsync.hasError) {
      return const _ChartBlock(title: 'Funds by campaign', height: 64, child: _EmptyChart('Could not load fund data.'));
    }
    if (campaigns == null || allocations == null) {
      return const _ChartBlock(
        title: 'Funds by campaign',
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final listed = campaigns.where((c) => c.type == 'donation' || c.type == 'sponsorship').where((c) => !c.isDraft).toList()
      ..sort((a, b) => b.collected.compareTo(a.collected));
    final known = {for (final c in listed) c.id};
    final spentByCampaign = <String, double>{};
    for (final a in allocations) {
      if (a.entry.isTransfer || !known.contains(a.campaignId)) continue;
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
        if (byAnimal.isNotEmpty)
          _ChartBlock(
            title: 'Spending by animal fund',
            height: (byAnimal.length.clamp(1, 6) * 30 + 8).toDouble(),
            child: _AmountList(data: byAnimal),
          ),
        _note('Fund totals are all time. Spending is what was allocated from each fund; money moved to another fund counts there.'),
      ],
    );
  }
}

// ─── Shelter ─────────────────────────────────────────────────────────────

class _ShelterReport extends ConsumerWidget {
  const _ShelterReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occA = ref.watch(shelterOccupancyProvider);
    final animalsA = ref.watch(allAnimalRecordsProvider);
    final casesA = ref.watch(reportCasesProvider);
    return _whenAll([occA, animalsA, casesA], 'shelter records', () {
      final p = ref.watch(analyticsPeriodProvider).period(DateTime.now());
      final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
      final occ = occA.requireValue;
      final records = animalsA.requireValue;
      final animals = records.map(_animalDoc).toList();
      final flow = shelterFlowIn(p, animals);
      final flowBefore = shelterFlowIn(p.previous, animals);
      final referrals = referralStatsIn(p, casesA.requireValue.map(_caseDoc).toList());
      final housed = occ.inShelter + occ.isolation;
      final awaiting = records.where((a) => isInCare(a) && a.adoptionStatus == 'adoptable').length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Usable capacity',
                valueText: settings.capacity == null ? 'Not set' : '${settings.capacity}',
                caption: settings.isolationCapacity == null ? null : 'Of which ${settings.isolationCapacity} isolation',
              ),
              MetricTile(label: 'Current occupancy', value: housed, caption: '${occ.isolation} in isolation · now'),
              MetricTile(
                label: 'Available spaces',
                valueText: occ.free == null ? '—' : '${occ.free}',
                caption: occ.free == null ? 'Set shelter spaces in Shelter settings' : 'After ${occ.atVet} held for the vet and ${occ.arriving} arriving',
              ),
              MetricTile(label: 'Animals awaiting adoption', value: awaiting, caption: 'Listed now'),
              MetricTile(
                label: 'Animals under treatment',
                value: occ.atVet,
                caption: settings.treatmentCapacity == null ? 'Space held for their return' : 'Of ${settings.treatmentCapacity} treatment spots',
              ),
            ],
          ),
          _heading('This period'),
          MetricGrid(
            tiles: [
              MetricTile(
                label: 'Admissions',
                value: flow.admissions,
                caption: '${flow.readmissions} back from adoption · ${_wasCount(flowBefore.admissions)}',
              ),
              MetricTile(label: 'Discharges', value: flow.dischargeTotal, caption: _wasCount(flowBefore.dischargeTotal)),
              MetricTile(
                label: 'Avg length of stay',
                valueText: _days(flow.stayDays.average),
                caption: flow.stayDays.isEmpty ? 'No animal left care yet' : 'Animals that left · median ${_days(flow.stayDays.median)}',
              ),
              MetricTile(
                label: 'Turned away for lack of space',
                value: referrals.dueToCapacity,
                caption: '${referrals.capacityReferred} referred · ${referrals.capacityDeclined} declined',
              ),
            ],
          ),
          _ChartBlock(
            title: 'How animals left care',
            height: _barsHeight(flow.discharges),
            child: _HorizontalBars(data: flow.discharges, empty: 'No animal left care in this period.'),
          ),
          _ChartBlock(
            title: 'Admissions over the period',
            child: _BarChart(
              data: bucketed<Map<String, dynamic>>(p, animals.where((a) => a['isDemo'] != true),
                  (a) => dateOf(a['createdAt']) ?? dateOf(a['intakeDate']), (_) => 1),
              color: AppColors.greenrspwn,
            ),
          ),
          _note('Occupancy counts animals housed in the shelter (with isolation); animals at the vet hold a space for '
              'their return but are shown apart. Length of stay here is for animals that left care in the period; '
              '“Who waits longest?” shows animals still in care. Referral reasons are recorded from Nov 2026.'),
        ],
      );
    });
  }
}

// ─── Volunteers & transporters ───────────────────────────────────────────

/// One organization's events and their sign-ups (registrations are readable
/// only by the event organization's staff), read when the tab opens.
typedef VolunteerReportData = ({List<VolunteerEvent> events, Map<String, List<Map<String, dynamic>>> registrations});

final volunteerReportProvider = FutureProvider.autoDispose<VolunteerReportData?>((ref) async {
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

class _PeopleReport extends ConsumerWidget {
  const _PeopleReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashAsync<VolunteerReportData?>(
          value: ref.watch(volunteerReportProvider),
          what: 'volunteer events',
          builder: (data) => data == null
              ? const RestrictedNotice('Volunteer reports are per organization. Link this account to one to see them.')
              : _volunteers(ref, data),
        ),
        _heading('Pet transporters'),
        _whenAll([ref.watch(reportOfferDocsProvider), ref.watch(reportAssignmentsProvider)], 'transporter offers',
            () => _transporters(ref, ref.watch(reportOfferDocsProvider).requireValue, ref.watch(reportAssignmentsProvider).requireValue)),
      ],
    );
  }

  Widget _volunteers(WidgetRef ref, VolunteerReportData data) {
    final p = ref.watch(analyticsPeriodProvider).period(DateTime.now());
    final events = [
      for (final e in data.events) (startAt: e.startAt, isPast: e.isPast, registrations: data.registrations[e.id] ?? const <Map<String, dynamic>>[]),
    ];
    final s = volunteerStatsIn(p, events);
    final before = volunteerStatsIn(p.previous, events);
    final attendedByUid = <String, int>{};
    final nameOf = <String, String>{};
    final came = <DateTime>[];
    for (final e in data.events.where((e) => p.has(e.startAt))) {
      for (final r in data.registrations[e.id] ?? const <Map<String, dynamic>>[]) {
        final uid = r['uid'] as String;
        final name = (r['participantName'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) nameOf[uid] = name;
        if (r['attended'] == true) {
          attendedByUid[uid] = (attendedByUid[uid] ?? 0) + 1;
          came.add(e.startAt);
        }
      }
    }
    final top = (attendedByUid.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(label: 'Registered volunteers', value: s.registered, caption: 'Ever signed up for your events'),
            MetricTile(label: 'Active volunteers', value: s.active, caption: 'Came to an event · ${_wasCount(before.active)}'),
            MetricTile(label: 'Participation rate', valueText: s.participation.percent, caption: _of(s.participation, 'registered came')),
            MetricTile(label: 'Events held', value: s.eventsHeld, caption: '${s.signUps} sign-ups'),
            MetricTile(label: 'Event attendance', valueText: s.attendance.percent, caption: _of(s.attendance, 'marked sign-ups came')),
          ],
        ),
        _note('Attendance counts only sign-ups where staff marked who came. Cancelled events are left out. '
            'Event data is read when this tab opens.'),
        _ChartBlock(
          title: 'Volunteers who came, over the period',
          child: _BarChart(data: bucketed<DateTime>(p, came, (t) => t, (_) => 1), color: AppColors.greenrspwn),
        ),
        _ChartBlock(
          title: 'Most events attended',
          height: (top.length.clamp(1, 5) * 24 + 8).toDouble(),
          child: _HorizontalBars(
            data: {for (final e in top) nameOf[e.key] ?? 'Volunteer': e.value},
            empty: 'No attendance marked in this period.',
          ),
        ),
      ],
    );
  }

  Widget _transporters(WidgetRef ref, List<Map<String, dynamic>> offers, List<TransportAssignment> assignments) {
    final p = ref.watch(analyticsPeriodProvider).period(DateTime.now());
    final supply = ref.watch(transportSupplyProvider).asData?.value;
    final waiting = ref.watch(dashboardRescueSnapshotProvider).asData?.value.count(RescueStage.transporter);
    final t = transportStatsIn(p, offers);
    final answered = Ratio(t.offersAccepted + t.offersDeclined, t.offersAccepted + t.offersDeclined + t.offersExpired);
    final declineReasons = <String, num>{};
    for (final a in assignments) {
      if (a.isDemo || a.status != TransportAssignmentStatus.rejected || !p.has(a.offeredAt)) continue;
      final reason = (a.rejectionReason ?? '').trim();
      final key = reason.isEmpty ? 'No reason given' : reason;
      declineReasons[key] = (declineReasons[key] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          tiles: [
            MetricTile(label: 'Verified transporters', valueText: supply == null ? '—' : '${supply.verified}',
                caption: supply == null ? null : '${supply.registered} registered'),
            MetricTile(label: 'Available now', valueText: supply == null ? '—' : '${supply.free}',
                caption: supply == null ? null : 'Online and not on a trip · ${supply.onAssignment} on one'),
            MetricTile(label: 'Offer response rate', valueText: answered.percent, caption: _of(answered, 'offers answered before expiring')),
            MetricTile(
              label: 'Avg response time',
              valueText: _mins(t.responseMinutes.average),
              caption: t.responseMinutes.isEmpty ? 'No answered offer yet' : 'Offer to answer · median ${_mins(t.responseMinutes.median)}',
            ),
            MetricTile(
              label: 'Waiting for a transporter',
              valueText: waiting == null ? '—' : '$waiting',
              caption: 'Cases now',
              severity: (waiting ?? 0) > 0 ? DashSeverity.warning : null,
            ),
            MetricTile(label: 'No transporter took it', value: t.casesWithNoTaker, caption: 'Every offer declined or expired'),
          ],
        ),
        _note('${t.offersSent} offers sent in this period: ${t.offersAccepted} accepted, ${t.offersDeclined} declined, '
            '${t.offersExpired} expired. Trip completion and transporter use are on the Rescue tab.'),
        _ChartBlock(
          title: 'Pet transporter decline reasons',
          height: (declineReasons.length * 40 + 16).clamp(60, 220).toDouble(),
          child: _HorizontalBars(data: declineReasons, empty: 'No declines in this period.'),
        ),
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
