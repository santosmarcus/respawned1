import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_view.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/finance_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_rows.dart';
import 'package:respawnd1/features/adminhome/dashboard/module_analytics.dart';

/// Analytics gap 1: what leaves the app.
///
///  - "Summary PDF": the outcome figures, rescue, adoption and (for
///    financial admins) donation totals for the chosen period, beside the
///    comparison period.
///  - "Rows as CSV": one file each for cases, animal records, adoption
///    applications and (financial admins) donations created or closed in the
///    period, the rows the figures are counted from.
///  - "Monthly accomplishment report": last calendar month for the board
///    and donors, with the five months before it from the stored monthly
///    summaries (functions/analytics_summary_rules.js) where they exist.
///
/// Same pw.Document / Printing / SharePlus pattern as
/// TransferExportService.

// ─── Pure helpers (tested) ───────────────────────────────────────────────

/// The built-in PDF fonts only cover Latin-1; swap the typographic
/// characters the app's labels use for plain ones so nothing renders blank.
String pdfSafe(String s) => s
    .replaceAll('₱', 'PHP ')
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('…', '...')
    .replaceAll('→', '->')
    .replaceAll('≈', '~')
    .replaceAll('≤', '<=');

/// One CSV field: quoted when it holds a comma, quote or line break.
String csvField(Object? v) {
  final s = v == null ? '' : (v is DateTime ? v.toIso8601String() : '$v');
  if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String toCsv(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.map(csvField).join(','));
  for (final r in rows) {
    b.writeln(r.map(csvField).join(','));
  }
  return b.toString();
}

String _peso(num v) => 'PHP ${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
String _pct(double? v) => v == null ? 'no outcomes' : '${(v * 100).round()}%';
String _d(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

class _Section {
  final String title;
  final List<(String, String, String?)> rows; // label, current, previous
  const _Section(this.title, this.rows);
}

class _Data {
  final List<AnimalRecord> records;
  final List<RescueCase> cases;
  final List<AdoptionApplication> apps;
  final List<DonationHistoryRecord>? donations; // null: not a financial admin
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> followUps;
  final List<Expense>? expenses; // null with donations
  const _Data(this.records, this.cases, this.apps, this.donations,
      {this.offers = const [], this.followUps = const [], this.expenses});
}

bool _isMoney(DonationHistoryRecord d) =>
    !d.type.toLowerCase().contains('kind') && !const ['reversed', 'voided', 'void', 'cancelled'].contains(d.status);

List<_Section> _sections(_Data data, Period p) {
  final cur = computeOutcomes(p: p, records: data.records, cases: data.cases);
  final prev = computeOutcomes(p: p.previous, records: data.records, cases: data.cases);
  String n(int v) => '$v';

  int reports(Period x) => data.cases.where((c) => x.has(c.createdAt)).length;
  int critical(Period x) => data.cases.where((c) => x.has(c.createdAt) && c.urgency == 'Critical').length;
  final byType = <String, int>{};
  for (final c in data.cases.where((c) => p.has(c.createdAt))) {
    final t = (c.rescueType ?? '').isEmpty ? 'Unspecified' : c.rescueType!;
    byType[t] = (byType[t] ?? 0) + 1;
  }
  int apps(Period x) => data.apps.where((a) => x.has(a.createdAt)).length;
  int approved(Period x) => data.apps.where((a) => x.has(a.approvedAt)).length;
  int rejected(Period x) => data.apps.where((a) => x.has(a.rejectedAt)).length;

  final sections = [
    _Section('Outcomes (animals whose time in care ended)', [
      ('Live-outcome rate', _pct(cur.liveRate), _pct(prev.liveRate)),
      ('Taken in', n(cur.intake), n(prev.intake)),
      ('Adopted', n(cur.adopted), n(prev.adopted)),
      ('Back with owner', n(cur.returnedToOwner), n(prev.returnedToOwner)),
      ('Transferred out', n(cur.transferStarted), n(prev.transferStarted)),
      ('Released to reporter', n(cur.releasedToReporter), n(prev.releasedToReporter)),
      ('Died in care', n(cur.diedInCare), n(prev.diedInCare)),
      ('Euthanasia', n(cur.euthanasia), n(prev.euthanasia)),
    ]),
    _Section('Rescue', [
      ('Reports received', n(reports(p)), n(reports(p.previous))),
      ('Critical reports', n(critical(p)), n(critical(p.previous))),
      for (final e in (byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
        ('  ${e.key}', n(e.value), null),
    ]),
    _Section('Adoption', [
      ('Applications received', n(apps(p)), n(apps(p.previous))),
      ('Applications approved', n(approved(p)), n(approved(p.previous))),
      ('Applications rejected', n(rejected(p)), n(rejected(p.previous))),
    ]),
  ];
  final dons = data.donations;
  if (dons != null) {
    List<DonationHistoryRecord> money(Period x) => dons.where((d) => _isMoney(d) && x.has(d.createdAt)).toList();
    double total(Period x) => money(x).fold(0, (s, d) => s + d.amountValue);
    sections.add(_Section('Donations (money received)', [
      ('Donations', n(money(p).length), n(money(p.previous).length)),
      ('Total', _peso(total(p)), _peso(total(p.previous))),
    ]));
  }
  return sections;
}

// ─── PDF ─────────────────────────────────────────────────────────────────

Future<Uint8List> _buildPdf({
  required String title,
  required String subtitle,
  required String currentLabel,
  required String previousLabel,
  required List<_Section> sections,
  List<String>? trendHeader,
  List<List<String>>? trendRows,
  String? note,
}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text(pdfSafe(title), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(pdfSafe(subtitle), style: const pw.TextStyle(fontSize: 11)),
        pw.Text('Generated ${_d(now)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Divider(),
        for (final s in sections) ...[
          pw.SizedBox(height: 8),
          pw.Text(pdfSafe(s.title), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['', pdfSafe(currentLabel), pdfSafe(previousLabel)],
            data: [for (final r in s.rows) [pdfSafe(r.$1), pdfSafe(r.$2), pdfSafe(r.$3 ?? '')]],
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),
        ],
        if (trendHeader != null && trendRows != null && trendRows.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('Month by month', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: trendHeader.map(pdfSafe).toList(),
            data: [for (final r in trendRows) r.map(pdfSafe).toList()],
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Text(
          pdfSafe(note ??
              'Counts come from the records in ResPAWnd. Missing data is left out, never counted as zero. '
                  'Rates state their population: animals whose time in care ended in the period.'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return doc.save();
}

// ─── Running an export ───────────────────────────────────────────────────

/// Reads an autoDispose provider's first value, keeping it alive meanwhile.
Future<T> _first<T>(ProviderContainer c, ProviderListenable<Future<T>> p) async {
  final sub = c.listen(p, (_, _) {});
  try {
    return await sub.read();
  } finally {
    sub.close();
  }
}

Future<_Data> _load(ProviderContainer c, {required bool withDonations}) async {
  final records = await _first(c, allAnimalRecordsProvider.future);
  final apps = await _first(c, allAdoptionsProvider.future);
  // analyticsCasesProvider combines two streams; wait for its first value.
  final sub = c.listen(analyticsCasesProvider, (_, _) {});
  try {
    var casesAsync = sub.read();
    for (var i = 0; i < 100 && casesAsync.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      casesAsync = sub.read();
    }
    if (casesAsync.hasError) throw casesAsync.error!;
    if (!casesAsync.hasValue) throw StateError('Rescue cases are still loading. Try again in a moment.');
    final donations = withDonations ? await _first(c, allDonationsProvider.future) : null;
    final offers = await _first(c, orgTransportOffersProvider.future);
    final followUps = await _first(c, orgFollowUpsProvider.future);
    List<Expense>? expenses;
    if (withDonations) {
      // General expenses are readable only by people who manage money.
      final general = await _first(c, myGeneralExpensesProvider.future).catchError((_) => const <Expense>[]);
      expenses = [...await _first(c, allCaseExpensesProvider.future), ...general];
    }
    return _Data(records, casesAsync.requireValue, apps, donations,
        offers: offers, followUps: followUps, expenses: expenses);
  } finally {
    sub.close();
  }
}

Future<void> runAnalyticsExport(BuildContext context, WidgetRef ref, String kind) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing export…'), duration: Duration(seconds: 2)));
  try {
    final canManage = await _first(container, canViewFinancesProvider.future);
    final data = await _load(container, withDonations: canManage);
    final range = container.read(analyticsPeriodProvider);
    final now = DateTime.now();
    switch (kind) {
      case 'pdf':
        final p = range.period(now);
        final bytes = await _buildPdf(
          title: 'ResPAWnd analytics summary',
          subtitle: '${range.label} (${_d(p.from)} to ${_d(p.to)}), compared with the ${range.previousLabel}',
          currentLabel: range.label,
          previousLabel: range.previousLabel == 'previous period' ? 'Previous period' : range.previousLabel,
          sections: _sections(data, p),
        );
        await Printing.sharePdf(bytes: bytes, filename: 'analytics_${range.fileSlug}.pdf');
      case 'csv':
        await _shareCsv(data, range);
      case 'monthly':
        await _monthlyReport(container, data, now);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not export: ${e is StateError ? e.message : e}')));
  }
}

Future<void> _shareCsv(_Data data, AnalyticsRange range) async {
  final p = range.period(DateTime.now());
  bool touches(List<DateTime?> times) => times.any(p.has);

  final files = <String, String>{
    'cases': toCsv(
      ['case_id', 'reported', 'rescue_type', 'urgency', 'status', 'animals', 'closure_reason', 'closed', 'address'],
      [
        for (final c in data.cases)
          if (touches([c.createdAt, tsOf(c.raw['closedAt']), c.dischargedAt, c.deceasedAt]))
            [c.id, c.createdAt, c.rescueType, c.urgency, c.raw['status'], c.animalCount, c.raw['closureReason'],
             tsOf(c.raw['closedAt']), c.address],
      ],
    ),
    'animals': toCsv(
      ['animal_id', 'name', 'species', 'taken_in', 'ready_for_adoption', 'adopted', 'deceased', 'cause', 'status'],
      [
        for (final a in data.records)
          if (touches([a.createdAt, a.adoptedAt, a.deceasedAt, readyForAdoptionAtOf(a.raw)]))
            [a.id, a.name, a.species, a.createdAt, readyForAdoptionAtOf(a.raw), a.adoptedAt, a.deceasedAt,
             a.deceasedCause, a.adoptionStatus],
      ],
    ),
    'adoptions': toCsv(
      ['application_id', 'animal', 'submitted', 'status', 'approved', 'rejected'],
      [
        for (final a in data.apps)
          if (touches([a.createdAt, a.approvedAt, a.rejectedAt]))
            [a.id, a.animalName, a.createdAt, a.status.firestoreValue, a.approvedAt, a.rejectedAt],
      ],
    ),
    'module_metrics': toCsv(
      kMetricRowsHeader,
      moduleMetricRows(
        p,
        cases: [for (final c in data.cases) {...c.raw, 'id': c.id}],
        offers: data.offers,
        adoptions: [for (final a in data.apps) {...a.raw, 'id': a.id}],
        followUps: data.followUps,
        now: DateTime.now(),
        donations: data.donations?.map((d) => DonationRow(
              amount: d.amountValue, type: d.type, status: d.status, source: d.source, method: d.method,
              at: d.when, category: d.category, quantity: d.quantityReceived)).toList(),
        expenses: data.expenses,
      ),
    ),
    if (data.donations != null)
      'donations': toCsv(
        ['donation_id', 'date', 'type', 'amount', 'method', 'source', 'campaign', 'status'],
        [
          for (final d in data.donations!)
            if (p.has(d.createdAt))
              [d.id, d.createdAt, d.type, d.amountValue, d.method, d.source, d.campaignName, d.status],
        ],
      ),
  };
  final dir = await getTemporaryDirectory();
  final xfiles = <XFile>[];
  for (final e in files.entries) {
    final f = File('${dir.path}/analytics_${range.fileSlug}_${e.key}.csv');
    await f.writeAsString(e.value);
    xfiles.add(XFile(f.path, mimeType: 'text/csv'));
  }
  await SharePlus.instance.share(ShareParams(files: xfiles, text: 'ResPAWnd analytics rows · ${range.label}'));
}

Future<void> _monthlyReport(ProviderContainer container, _Data data, DateTime now) async {
  final last = now.month == 1 ? AnalyticsRange.month(now.year - 1, 12) : AnalyticsRange.month(now.year, now.month - 1);
  final p = last.period(now);

  // The five months before it, from the stored summaries where they exist.
  final orgId = await _first(container, dashboardOrgIdProvider.future);
  final trendRows = <List<String>>[];
  if (orgId != null) {
    final keys = [
      for (var i = 0; i < 6; i++)
        () {
          final d = DateTime(last.year, last.index - i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}';
        }(),
    ];
    final col = FirebaseFirestore.instance.collection('organizations').doc(orgId).collection('analyticsSummaries');
    final docs = await Future.wait(keys.map((k) => col.doc(k).get().then((d) => d.data()).catchError((_) => null)));
    for (var i = 0; i < keys.length; i++) {
      final m = docs[i];
      if (m == null) continue;
      String v(String k) => '${m[k] ?? ''}';
      final rate = (m['liveRate'] as num?)?.toDouble();
      trendRows.add([
        keys[i],
        v('reports'),
        v('intake'),
        v('adopted'),
        _pct(rate),
        if (data.donations != null) _peso((m['donationsTotal'] as num?) ?? 0),
      ]);
    }
  }

  final bytes = await _buildPdf(
    title: 'Monthly accomplishment report',
    subtitle: '${last.label}, compared with ${last.previousLabel}',
    currentLabel: last.label,
    previousLabel: last.previousLabel,
    sections: _sections(data, p),
    trendHeader: ['Month', 'Reports', 'Taken in', 'Adopted', 'Live rate', if (data.donations != null) 'Donations'],
    trendRows: trendRows,
    note: 'Prepared from ResPAWnd records for the board and donors. "Month by month" uses the monthly summaries '
        'stored on the 1st of each month; months without one are left out. Missing data is never counted as zero.',
  );
  await Printing.sharePdf(bytes: bytes, filename: 'accomplishment_report_${last.fileSlug}.pdf');
}
