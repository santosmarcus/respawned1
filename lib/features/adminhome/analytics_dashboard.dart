import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';

// ─── Admin Analytics building blocks ────────────────────────────────────────
//
// Lives inline on the Admin home screen (adminhome_screen.dart), which owns
// the Rescue / Adoptions / Donations / Shelter category picker and simply
// renders whichever of the four public view widgets below is selected.
//
// Every metric is computed live from the same Firestore collections the
// rest of the app already writes to (cases, adoptions, the donation
// donor/sponsor records) — nothing here is hardcoded. Where the current data
// model genuinely has no field for something yet (e.g. a transporter's
// decline reason, or RTO/RTF outcome distinctions), the chart says so
// plainly instead of showing a fabricated number.

/// The four categories the admin home screen lets you switch between.
// Analytics/Audit Cleanup spec §2 — `shelter` deliberately removed from
// this enum (not just hidden in the UI): the category picker on
// adminhome_screen.dart is driven directly off `AdminAnalyticsCategory.
// values`, so removing it here is what actually removes the tab, with no
// leftover index/blank-tab risk since that picker matches by enum
// equality, never by numeric index. Shelter-specific data (live/non-live
// outcome counts) was computed only inside `_ShelterAnalyticsView` below
// (also removed) from its own `cases`/`adoptions` queries — never a shared
// data source. Shelter occupancy/capacity (TopMetricsRow's Capacity card,
// `shelterMaxCapacityProvider`) and Organization Profile's shelter capacity
// field live in admin_dashboard_home_widgets.dart / organization_repository.dart
// respectively — untouched by this removal.
enum AdminAnalyticsCategory { rescue, adoption, donation }

extension AdminAnalyticsCategoryX on AdminAnalyticsCategory {
  String get label => switch (this) {
    AdminAnalyticsCategory.rescue => 'Rescue',
    AdminAnalyticsCategory.adoption => 'Adoptions',
    AdminAnalyticsCategory.donation => 'Donations',
  };
}

/// Renders the selected category's analytics — the single entry point
/// adminhome_screen.dart needs.
class AdminAnalyticsSection extends StatelessWidget {
  final AdminAnalyticsCategory category;
  final String? orgId;

  const AdminAnalyticsSection({super.key, required this.category, this.orgId});

  @override
  Widget build(BuildContext context) {
    switch (category) {
      case AdminAnalyticsCategory.rescue:
        return _RescueAnalyticsView(orgId: orgId);
      case AdminAnalyticsCategory.adoption:
        return const _AdoptionAnalyticsView();
      case AdminAnalyticsCategory.donation:
        return const _DonationAnalyticsView();
    }
  }
}

// ─── Shared building blocks ──────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title,
          style: GoogleFonts.tiltWarp(
              fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: AppColors.slaterspwn, blurRadius: 1, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Text(value,
              style: GoogleFonts.tiltWarp(
                  fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final List<Widget> cards;
  const _MetricsGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: cards,
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  final List<String>? filterOptions;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;
  // Dashboard Chart Overflow spec §4 — most charts fit the original fixed
  // 180 height, but a horizontal-bar chart with many/long categories needs
  // more room (and to scroll internally rather than clip) — callers with
  // that need pass a taller value instead of every card growing.
  final double height;

  const _ChartCard({
    required this.title,
    required this.child,
    this.filterOptions,
    this.selectedFilter,
    this.onFilterChanged,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: AppColors.slaterspwn, blurRadius: 1, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title,
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
              if (filterOptions != null)
                DropdownButton<String>(
                  value: selectedFilter,
                  underline: const SizedBox(),
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                  items: filterOptions!
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onFilterChanged?.call(v);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

class _NotTrackedChart extends StatelessWidget {
  final String note;
  const _NotTrackedChart({
    this.note = 'Not tracked yet — this needs a new field in the data model.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(note,
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
      ),
    );
  }
}

/// Rescue Analytics spec §2/§5 — the shared normalization step for
/// species aggregation only (never mutates species_summary.dart's own
/// display casing, which case cards/search elsewhere reuse as-is).
/// Groups "dog"/"Dog"/"DOG" together under one canonical "Dog" bucket,
/// and returns null for a blank/placeholder value (species_summary.dart's
/// own "Unknown species" filler included) so charts never invent a
/// misleading category for animals with no real species on file.
String? _normalizedSpeciesForAnalytics(String raw) {
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
];

class _SimpleBarChart extends StatelessWidget {
  final Map<String, num> data;
  const _SimpleBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    if (entries.isEmpty || entries.every((e) => e.value == 0)) {
      return const _NotTrackedChart(note: 'No data yet.');
    }
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: entries[i].value.toDouble(),
                color: _chartPalette[i % _chartPalette.length],
                width: 18,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(entries[i].key,
                      style: GoogleFonts.zain(fontSize: 9, color: AppColors.textPrimary)),
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

/// Dashboard Chart Overflow spec §4 — "Pet Transporter Decline Reason" used
/// _SimpleBarChart's vertical bars with bottom-axis labels, which overlapped
/// into an unreadable mess once reasons were full sentences ("Handling
/// another rescue", "Pickup location too far", ...) rather than the short
/// single-word categories (Critical/Medium/Low, species names) every other
/// _SimpleBarChart user has. A horizontal layout puts the label to the
/// left of its own bar instead of competing for space with its neighbors,
/// so it scales with however many distinct reasons actually exist instead
/// of clipping/overlapping. Read-only over whatever `data` it's given — the
/// underlying decline-reason tally in _RescueAnalyticsViewState is
/// untouched.
class _DeclineReasonBarChart extends StatelessWidget {
  final Map<String, num> data;
  const _DeclineReasonBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const _NotTrackedChart(note: 'No decline data yet.');
    }
    final maxValue = entries.first.value.toDouble();

    // Real category count only — never pads with invented zero-value
    // reasons just to fill the card.
    return ListView.separated(
      physics: entries.length > 5
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final entry = entries[i];
        final fraction = maxValue == 0 ? 0.0 : entry.value / maxValue;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                entry.key,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.slaterspwn.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.05, 1.0),
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: _chartPalette[i % _chartPalette.length],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              child: Text(
                '${entry.value.toInt()}',
                textAlign: TextAlign.right,
                style: GoogleFonts.zain(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SimplePieChart extends StatelessWidget {
  final Map<String, num> data;
  const _SimplePieChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final filtered = data.entries.where((e) => e.value > 0).toList();
    if (filtered.isEmpty) {
      return const _NotTrackedChart(note: 'No data yet.');
    }
    final total = filtered.fold<num>(0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 26,
              sections: [
                for (int i = 0; i < filtered.length; i++)
                  PieChartSectionData(
                    value: filtered[i].value.toDouble(),
                    color: _chartPalette[i % _chartPalette.length],
                    title: '${(filtered[i].value / total * 100).round()}%',
                    radius: 42,
                    titleStyle: GoogleFonts.zain(
                        fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
                  child: Row(
                    children: [
                      Container(
                          width: 8, height: 8, color: _chartPalette[i % _chartPalette.length]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${filtered[i].key} (${filtered[i].value.toInt()})',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Rescue Analytics ─────────────────────────────────────────────────────

class _RescueAnalyticsView extends StatefulWidget {
  final String? orgId;
  const _RescueAnalyticsView({required this.orgId});

  @override
  State<_RescueAnalyticsView> createState() => _RescueAnalyticsViewState();
}

class _RescueAnalyticsViewState extends State<_RescueAnalyticsView> {
  late Future<List<RescueCase>> _casesFuture;
  late Future<List<TransportAssignment>> _assignmentsFuture;
  String _urgencyWindow = 'All time';

  @override
  void initState() {
    super.initState();
    _casesFuture = _loadCases();
    _assignmentsFuture = _loadAssignments();
  }

  // Rescue Analytics Regression fix — this used to filter
  // `cases.where('organizationId', isEqualTo: widget.orgId)` whenever an
  // org id was available. No write path anywhere in this app
  // (rescue_page.dart's report submission, RescueCaseRepository) ever sets
  // `organizationId` on a case document — confirmed by grep, and already
  // documented next to _loadAssignments() below ("cases.organizationId
  // itself is sparse/unreliable today"). Once the Organization Invitations
  // work elsewhere in this app started actually populating
  // `users/{uid}.organizationId` for real admin accounts, this dashboard's
  // own org-resolution (adminhome_screen.dart's `_resolveOrg`) began
  // returning a non-null orgId far more often than before — which flipped
  // this filter on for most admins, and since no case ever has that field
  // set, the query matched zero documents. That is the actual root cause
  // of "Rescue Analytics shows no data" — not the animals[] schema change
  // (allSpecies/speciesList already tolerate both shapes fine). Left
  // unscoped, matching the sibling method's own established reasoning,
  // until case documents reliably carry a real organizationId.
  Future<List<RescueCase>> _loadCases() async {
    final q = FirebaseFirestore.instance.collection('cases');
    final snap = await q.get();
    final cases = <RescueCase>[];
    for (final doc in snap.docs) {
      try {
        cases.add(RescueCase.fromFirestore(doc));
      } catch (e) {
        debugPrint('[AnalyticsDashboard] Skipping unparseable case ${doc.id}: $e');
      }
    }
    return cases;
  }

  // Dashboard Improvement spec — the "Pet Transporter Response Rate"/
  // "Decline Reason" charts below used to claim these fields don't exist;
  // TransportAssignment (transport_assignment.dart) already has
  // acceptedAt/rejectedAt/rejectionReason/an `expired` status, just never
  // wired into this dashboard. No org filter here — transportAssignments
  // are a subcollection of `cases`, and `cases.organizationId` itself is
  // sparse/unreliable today (see the Dashboard Gap Analysis), so this
  // stays honestly unscoped rather than pretending to filter by org.
  Future<List<TransportAssignment>> _loadAssignments() async {
    final snap = await FirebaseFirestore.instance.collectionGroup('transportAssignments').get();
    return snap.docs
        .map((d) => TransportAssignment.fromFirestore(d, d.reference.parent.parent!.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Rescue Analytics'),
        FutureBuilder<List<RescueCase>>(
          future: _casesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              );
            }
            final cases = snapshot.data!;
            return _buildContent(cases);
          },
        ),
      ],
    );
  }

  Widget _buildContent(List<RescueCase> cases) {
    final total = cases.length;
    final successful = cases.where((c) => c.status == RescueStatus.completed).length;
    final resolutionRate = total == 0 ? 0.0 : successful / total * 100;

    final responseHours = <double>[];
    for (final c in cases) {
      if (c.createdAt == null) continue;
      final firstMove = c.statusHistory
          .where((h) => h.timestamp != null && h.status != 'pending')
          .toList()
        ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      if (firstMove.isNotEmpty) {
        responseHours
            .add(firstMove.first.timestamp!.difference(c.createdAt!).inMinutes / 60.0);
      }
    }
    final avgResponseHours =
    responseHours.isEmpty ? 0.0 : responseHours.reduce((a, b) => a + b) / responseHours.length;

    final now = DateTime.now();
    final windowStart = switch (_urgencyWindow) {
      'Last 7 days' => now.subtract(const Duration(days: 7)),
      'Last 30 days' => now.subtract(const Duration(days: 30)),
      _ => null,
    };
    final windowedCases = windowStart == null
        ? cases
        : cases.where((c) => c.createdAt != null && c.createdAt!.isAfter(windowStart)).toList();

    final byUrgency = <String, num>{'Critical': 0, 'Medium': 0, 'Low': 0};
    for (final c in windowedCases) {
      if (c.urgency != null && byUrgency.containsKey(c.urgency)) {
        byUrgency[c.urgency!] = byUrgency[c.urgency]! + 1;
      }
    }

    // Rescue Analytics Regression spec §3/§5 — case count vs animal count
    // are different units and must never be conflated. `total`/`successful`/
    // `byStatus`/`byRescueType` all count one document per case (a
    // two-animal report is still 1 case); `animalsReported`/`bySpecies`/
    // `byAnimalStage` flatten every case's `allSpecies`/`animalStageCounts`
    // (a case with two cats is 2 animals).
    var animalsReported = 0;
    final bySpecies = <String, num>{};
    for (final c in cases) {
      for (final s in c.allSpecies) {
        animalsReported++;
        final normalized = _normalizedSpeciesForAnalytics(s);
        if (normalized == null) continue; // blank/placeholder — not a real species
        bySpecies[normalized] = (bySpecies[normalized] ?? 0) + 1;
      }
    }

    final byStatus = <String, num>{};
    for (final c in cases) {
      byStatus[c.status.label] = (byStatus[c.status.label] ?? 0) + 1;
    }

    // Rescue Type is its own case-level field (e.g. Stray/Neglect/
    // Surrender/Lost Pet) — separate from species. Previously this chart
    // was mislabeled "Rescue Type" while actually charting species; kept
    // as two distinct charts now, each reading its own real source field.
    final byRescueType = <String, num>{};
    for (final c in cases) {
      final rt = c.rescueType?.trim();
      if (rt == null || rt.isEmpty) continue;
      byRescueType[rt] = (byRescueType[rt] ?? 0) + 1;
    }

    // Animal-level workflow stage (a case can have animals in different
    // stages at once — e.g. one animal already in Treatment while another
    // is still at Intake). Reuses the SAME denormalized
    // `animalStageCounts` RescueCaseRepository already maintains for the
    // Intake tab's own query (animal_treatment_state.dart's
    // activeStagesOf), so this chart can never disagree with the Rescue
    // Reports tabs. Deliberately separate from `byStatus` above, which is
    // the case's own single canonical workflow status.
    final byAnimalStage = <String, num>{};
    for (final c in cases) {
      c.animalStageCounts.forEach((stage, count) {
        final label = switch (stage) {
          'intake' => 'Intake',
          'in_treatment' => 'In Treatment',
          _ => stage,
        };
        byAnimalStage[label] = (byAnimalStage[label] ?? 0) + count;
      });
    }

    final transferred =
        cases.where((c) => c.status == RescueStatus.referred || c.openForTransfer).length;
    final transferRate = total == 0 ? 0.0 : transferred / total * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricsGrid(cards: [
          _MetricCard(label: 'Total Rescues (Cases)', value: '$total'),
          _MetricCard(label: 'Animals Reported', value: '$animalsReported'),
          _MetricCard(label: 'Successful Rescues', value: '$successful'),
          _MetricCard(
              label: 'Case Resolution Rate', value: '${resolutionRate.toStringAsFixed(0)}%'),
          _MetricCard(
              label: 'Average Rescue Response Time',
              value: '${avgResponseHours.toStringAsFixed(1)} hrs'),
        ]),
        const SizedBox(height: 6),
        Text('$total active cases · $animalsReported animals involved',
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        _ChartCard(
          title: 'Rescue Reports and Urgency Levels (Cases)',
          filterOptions: const ['All time', 'Last 7 days', 'Last 30 days'],
          selectedFilter: _urgencyWindow,
          onFilterChanged: (v) => setState(() => _urgencyWindow = v),
          child: _SimpleBarChart(data: byUrgency),
        ),
        const SizedBox(height: 14),
        const _ChartCard(
          title: 'Rescues by Location',
          child: _NotTrackedChart(
              note: 'Needs a map view over case lat/lng — not built yet.'),
        ),
        const SizedBox(height: 14),
        _ChartCard(title: 'Reports by Rescue Type (Cases)', child: _SimpleBarChart(data: byRescueType)),
        const SizedBox(height: 14),
        _ChartCard(title: 'Animals by Species', child: _SimpleBarChart(data: bySpecies)),
        const SizedBox(height: 14),
        _ChartCard(title: 'Report Classification Split (Cases)', child: _SimplePieChart(data: byStatus)),
        const SizedBox(height: 14),
        _ChartCard(title: 'Animals by Current Stage', child: _SimpleBarChart(data: byAnimalStage)),
        const SizedBox(height: 14),
        _MetricCard(
            label: 'Rescue Transfer and Refer Rate',
            value: '${transferRate.toStringAsFixed(0)}%'),
        const SizedBox(height: 14),
        FutureBuilder<List<TransportAssignment>>(
          future: _assignmentsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ChartCard(
                title: 'Pet Transporter Response Rate',
                child: _NotTrackedChart(note: 'Could not load transporter offer data: ${snapshot.error}'),
              );
            }
            if (!snapshot.hasData) {
              return const _ChartCard(
                title: 'Pet Transporter Response Rate',
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              );
            }
            final assignments = snapshot.data!;
            // Response rate: offers the transporter actually acted on
            // (accepted or rejected) out of every offer that's no longer
            // pending — excludes still-open offers, which haven't had a
            // chance to be answered yet.
            final resolved = assignments.where((a) =>
                a.status == TransportAssignmentStatus.accepted ||
                a.status == TransportAssignmentStatus.rejected ||
                a.status == TransportAssignmentStatus.expired ||
                a.status == TransportAssignmentStatus.cancelled);
            final responded = assignments.where((a) =>
                a.status == TransportAssignmentStatus.accepted || a.status == TransportAssignmentStatus.rejected);
            final responseRate = resolved.isEmpty ? null : responded.length / resolved.length * 100;

            final declineReasons = <String, num>{};
            for (final a in assignments) {
              if (a.status != TransportAssignmentStatus.rejected) continue;
              final reason = (a.rejectionReason ?? '').trim();
              final key = reason.isEmpty ? 'No reason given' : reason;
              declineReasons[key] = (declineReasons[key] ?? 0) + 1;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricCard(
                  label: 'Pet Transporter Response Rate',
                  value: responseRate == null ? 'No offers yet' : '${responseRate.toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 14),
                _ChartCard(
                  title: 'Pet Transporter Decline Reason',
                  // Enough height to show up to 5 reasons without scrolling;
                  // beyond that the ListView itself scrolls within a capped
                  // card height rather than growing the card indefinitely or
                  // clipping/overlapping labels.
                  height: (declineReasons.values.where((v) => v > 0).length * 40 + 16)
                      .clamp(80, 220)
                      .toDouble(),
                  child: _DeclineReasonBarChart(data: declineReasons),
                ),
                const SizedBox(height: 6),
                Text(
                  'Clinic decline reasons aren\'t shown — clinic selection has no accept/decline '
                      'flow with a reason field in the current data model.',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}


// ─── Adoption Analytics ───────────────────────────────────────────────────

class _AdoptionAnalyticsView extends StatelessWidget {
  const _AdoptionAnalyticsView();

  Future<Map<String, dynamic>> _loadMetrics() async {
    final snap = await FirebaseFirestore.instance.collection('adoptions').get();
    final apps = snap.docs.map(AdoptionApplication.fromFirestore).toList();

    final total = apps.length;
    final adoptedApps = apps.where((a) => a.adoptedAt != null).toList();
    final adopted = adoptedApps.length;
    final adoptionRate = total == 0 ? 0.0 : adopted / total * 100;

    final durations = <double>[];
    for (final a in adoptedApps) {
      if (a.createdAt != null) {
        durations.add(a.adoptedAt!.difference(a.createdAt!).inHours / 24.0);
      }
    }
    final avgDays =
    durations.isEmpty ? 0.0 : durations.reduce((a, b) => a + b) / durations.length;

    final returned = adoptedApps.where((a) => a.releasedAt != null).length;
    final returnRate = adopted == 0 ? 0.0 : returned / adopted * 100;

    final byStatus = <String, num>{};
    for (final a in apps) {
      byStatus[a.status.label] = (byStatus[a.status.label] ?? 0) + 1;
    }

    return {
      'total': total,
      'adoptionRate': adoptionRate,
      'avgDays': avgDays,
      'returnRate': returnRate,
      'byStatus': byStatus,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Adoption Analytics'),
        FutureBuilder<Map<String, dynamic>>(
          future: _loadMetrics(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              );
            }
            final m = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricsGrid(cards: [
                  _MetricCard(
                      label: 'Adoption Rate',
                      value: '${(m['adoptionRate'] as double).toStringAsFixed(0)}%'),
                  _MetricCard(
                      label: 'Length of Shelter Stay',
                      value: '${(m['avgDays'] as double).toStringAsFixed(1)} days'),
                  _MetricCard(
                      label: 'Adoption Return Rate',
                      value: '${(m['returnRate'] as double).toStringAsFixed(0)}%'),
                  _MetricCard(label: 'Total Applications', value: '${m['total']}'),
                ]),
                const SizedBox(height: 8),
                Text(
                  '"Length of Shelter Stay" is measured as application → adoption, since '
                      'intake date lives on the rescue case, not the adoption application.',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                _ChartCard(
                  title: 'Screening/Application Volume Outcomes',
                  child: _SimpleBarChart(data: m['byStatus'] as Map<String, num>),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Donation & Sponsorship Analytics ─────────────────────────────────────

class _DonationAnalyticsView extends StatefulWidget {
  const _DonationAnalyticsView();

  @override
  State<_DonationAnalyticsView> createState() => _DonationAnalyticsViewState();
}

class _DonationAnalyticsViewState extends State<_DonationAnalyticsView> {
  late Future<Map<String, dynamic>> _metricsFuture;
  String _monthFilter = 'Last 6 months';

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  // NOTE: the donation feature currently stores one donor doc per
  // (donationId, uid) pair — `donations/{id}/donors/{uid}` — so a person
  // can't donate twice to the *same* campaign, and there's no Firestore
  // record of sponsorships at all (sponsoring a pet is just a local
  // favorite toggle right now). Metrics below only use what's actually
  // written: amount, paymentMethod, donatedAt, uid, donationId.
  Future<Map<String, dynamic>> _loadMetrics() async {
    final donorsSnap = await FirebaseFirestore.instance.collectionGroup('donors').get();
    final donorDocs = donorsSnap.docs;
    final totalDonations = donorDocs.length;

    double totalAmount = 0;
    final byChannel = <String, num>{};
    final byMonth = <String, double>{};
    final firstSeenByUid = <String, DateTime>{};
    final campaignsByUid = <String, Set<int>>{};

    for (final d in donorDocs) {
      final data = d.data();
      final amount = ((data['amount'] as num?) ?? 0).toDouble();
      totalAmount += amount;

      final method = (data['paymentMethod'] as String?) ?? 'Unknown';
      byChannel[method] = (byChannel[method] ?? 0) + 1;

      final uid = data['uid'] as String?;
      final donationId = data['donationId'] as int?;
      if (uid != null && donationId != null) {
        campaignsByUid.putIfAbsent(uid, () => <int>{}).add(donationId);
      }

      final ts = data['donatedAt'];
      final dt = ts is Timestamp ? ts.toDate() : null;
      if (dt != null) {
        final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        byMonth[key] = (byMonth[key] ?? 0) + amount;

        if (uid != null) {
          final existing = firstSeenByUid[uid];
          if (existing == null || dt.isBefore(existing)) firstSeenByUid[uid] = dt;
        }
      }
    }

    final averageAmount = totalDonations == 0 ? 0.0 : totalAmount / totalDonations;

    // "Repeat donor" here means someone who has donated to more than one
    // *different* campaign — since a person can't donate twice to the same
    // one under the current data model.
    final distinctDonors = campaignsByUid.length;
    final repeatDonors = campaignsByUid.values.where((campaigns) => campaigns.length > 1).length;
    final retentionRate = distinctDonors == 0 ? 0.0 : repeatDonors / distinctDonors * 100;

    final newDonorsByMonth = <String, num>{};
    for (final entry in firstSeenByUid.entries) {
      final key = '${entry.value.year}-${entry.value.month.toString().padLeft(2, '0')}';
      newDonorsByMonth[key] = (newDonorsByMonth[key] ?? 0) + 1;
    }

    return {
      'totalDonations': totalDonations,
      'retentionRate': retentionRate,
      'averageAmount': averageAmount,
      'byChannel': byChannel,
      'byMonth': byMonth,
      'newDonorsByMonth': newDonorsByMonth,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Donation and Sponsorship Analytics'),
        FutureBuilder<Map<String, dynamic>>(
          future: _metricsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              );
            }
            final m = snapshot.data!;
            final byMonth = (m['byMonth'] as Map<String, double>);
            final newDonorsByMonth = (m['newDonorsByMonth'] as Map<String, num>);

            final months = <String>{...byMonth.keys, ...newDonorsByMonth.keys}.toList()..sort();
            final windowedMonths = switch (_monthFilter) {
              'Last 3 months' => months.length > 3 ? months.sublist(months.length - 3) : months,
              'Last 12 months' =>
              months.length > 12 ? months.sublist(months.length - 12) : months,
              _ => months.length > 6 ? months.sublist(months.length - 6) : months,
            };

            final donationsByMonthWindowed = <String, num>{
              for (final k in windowedMonths) k: byMonth[k] ?? 0,
            };
            final newDonorsWindowed = <String, num>{
              for (final k in windowedMonths) k: newDonorsByMonth[k] ?? 0,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricsGrid(cards: [
                  _MetricCard(label: 'Total Donations', value: '${m['totalDonations']}'),
                  _MetricCard(
                      label: 'Average Donation Amount',
                      value: '₱${(m['averageAmount'] as double).toStringAsFixed(0)}'),
                  _MetricCard(
                      label: 'Donor Retention Rate',
                      value: '${(m['retentionRate'] as double).toStringAsFixed(0)}%'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Total Sponsorships and Campaign Completion Rate aren\'t shown — '
                      'sponsoring a pet is currently just a local favorite toggle with no '
                      'Firestore record, and campaigns have no "target reached" flag yet.',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                _ChartCard(
                    title: 'Average Donation Channel',
                    child: _SimplePieChart(data: m['byChannel'] as Map<String, num>)),
                const SizedBox(height: 14),
                _ChartCard(
                  title: 'Donations by',
                  filterOptions: const ['Last 3 months', 'Last 6 months', 'Last 12 months'],
                  selectedFilter: _monthFilter,
                  onFilterChanged: (v) => setState(() => _monthFilter = v),
                  child: _SimpleBarChart(data: donationsByMonthWindowed),
                ),
                const SizedBox(height: 14),
                const _ChartCard(
                  title: 'Allocation Summary',
                  child: _NotTrackedChart(
                      note: 'Needs a shared expense collection across all campaigns — '
                          'each donation\'s Fund Tracking entries are currently sample data only.'),
                ),
                const SizedBox(height: 14),
                _ChartCard(
                  title: 'Donor Acquisition',
                  child: _SimpleBarChart(data: newDonorsWindowed),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}