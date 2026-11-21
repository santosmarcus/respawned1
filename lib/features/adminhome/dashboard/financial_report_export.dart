import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_export.dart' show pdfSafe, toCsv;

/// Monthly financial report for the organization's finance staff
/// (financeView or financeManage): money in, refunds, bills paid, how
/// campaign funds were used, and in-kind items received, for one calendar
/// month. Opened from the Analytics export menu and the Donations menu.
///
/// Bills (case and general expenses) are the money out. Campaign
/// allocations are shown on their own as "how campaign funds were used":
/// many of them pay those same bills, so adding them again would count the
/// spending twice.

// ─── Pure calculation (tested) ───────────────────────────────────────────

const _notMoneyStatuses = ['reversed', 'voided', 'void', 'cancelled'];

/// A credited cash donation or sponsorship payment.
bool isMoneyIn(DonationHistoryRecord d) => !d.isInKind && !_notMoneyStatuses.contains(d.status);

/// A bill that counts as spent: not waiting for approval and not rejected.
bool isSettledExpense(Expense e) => e.approvalStatus != 'pending' && e.approvalStatus != 'rejected';

DateTime? expenseDate(Expense e) => e.incurredAt ?? e.createdAt;

class MoneyLine {
  final String label;
  final int count;
  final double amount;
  const MoneyLine(this.label, this.count, this.amount);
}

class InKindLine {
  final String item;
  final String category;
  final int quantity;
  final int records;
  const InKindLine(this.item, this.category, this.quantity, this.records);
}

class MonthlyFinanceReport {
  final DateTime from;
  final DateTime to;
  final List<DonationHistoryRecord> moneyIn;
  final List<DonationHistoryRecord> refunds;
  final List<Expense> bills;
  final List<Expense> awaitingApproval;
  final List<({String campaign, AllocationEntry entry})> campaignUse;
  final List<DonationHistoryRecord> inKindReceived;
  final int inKindPledgesOpen;

  /// False when the reader may not see general running costs (financeView
  /// without financeManage); the report says they are left out.
  final bool generalExpensesIncluded;

  const MonthlyFinanceReport({
    required this.from,
    required this.to,
    required this.moneyIn,
    required this.refunds,
    required this.bills,
    required this.awaitingApproval,
    required this.campaignUse,
    required this.inKindReceived,
    required this.inKindPledgesOpen,
    this.generalExpensesIncluded = true,
  });

  double get totalIn => moneyIn.fold(0, (s, d) => s + d.amountValue);
  double get totalRefunded => refunds.fold(0, (s, d) => s + d.amountValue);
  double get totalBills => bills.fold(0, (s, e) => s + e.amount);
  double get net => totalIn - totalRefunded - totalBills;

  List<MoneyLine> get inByType => _group(moneyIn, (d) => d.type == 'sponsorship' ? 'Sponsorships' : 'Donations',
      (d) => d.amountValue);
  List<MoneyLine> get inByMethod =>
      _group(moneyIn, (d) => d.method.trim().isEmpty ? 'Not recorded' : d.method.trim(), (d) => d.amountValue);
  List<MoneyLine> get inByFund => _group(
      moneyIn,
      (d) => d.generalFund || d.campaignId.isEmpty
          ? 'General fund'
          : (d.campaignName.trim().isEmpty ? 'Campaign ${d.campaignId}' : d.campaignName.trim()),
      (d) => d.amountValue);
  List<MoneyLine> get billsByCategory => _group(bills, (e) => e.category.label, (e) => e.amount);
  List<MoneyLine> get billsByKind =>
      _group(bills, (e) => e.caseId.isEmpty ? 'General running costs' : 'Rescue case bills', (e) => e.amount);
  List<MoneyLine> get campaignUseByCategory => _group(
      campaignUse, (a) => a.entry.isTransfer ? 'Moved to another listing' : a.entry.category, (a) => a.entry.amount);

  List<InKindLine> get inKindLines {
    final byKey = <String, InKindLine>{};
    for (final d in inKindReceived) {
      final item = d.itemDescription.trim().isEmpty ? 'Unspecified item' : d.itemDescription.trim();
      final key = '${item.toLowerCase()}|${d.category}';
      final prev = byKey[key];
      byKey[key] = InKindLine(item, d.category, (prev?.quantity ?? 0) + (d.quantityReceived ?? 0),
          (prev?.records ?? 0) + 1);
    }
    return byKey.values.toList()..sort((a, b) => a.item.toLowerCase().compareTo(b.item.toLowerCase()));
  }

  static List<MoneyLine> _group<T>(Iterable<T> items, String Function(T) key, double Function(T) amount) {
    final counts = <String, int>{};
    final sums = <String, double>{};
    for (final i in items) {
      final k = key(i);
      counts[k] = (counts[k] ?? 0) + 1;
      sums[k] = (sums[k] ?? 0) + amount(i);
    }
    return [for (final k in sums.keys) MoneyLine(k, counts[k]!, sums[k]!)]
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }
}

/// Builds the report for [from]–[to] (end exclusive) from everything
/// loaded for the organization; each list is filtered to the month here.
MonthlyFinanceReport buildMonthlyFinanceReport({
  required DateTime from,
  required DateTime to,
  required List<DonationHistoryRecord> donations,
  required List<DonationHistoryRecord> reversed,
  required List<Expense> expenses,
  required List<({String campaign, AllocationEntry entry})> allocations,
  bool generalExpensesIncluded = true,
}) {
  bool inMonth(DateTime? t) => t != null && !t.isBefore(from) && t.isBefore(to);
  final monthDonations = donations.where((d) => inMonth(d.createdAt)).toList();
  final monthExpenses = expenses.where((e) => inMonth(expenseDate(e))).toList();
  final refunds = {
    for (final d in reversed)
      if (d.isReversed && !d.isInKind && inMonth(d.reversedAt ?? d.createdAt)) d.id: d,
  }.values.toList();
  return MonthlyFinanceReport(
    from: from,
    to: to,
    moneyIn: monthDonations.where(isMoneyIn).toList()..sort(_byDate),
    refunds: refunds..sort(_byDate),
    bills: monthExpenses.where(isSettledExpense).toList(),
    awaitingApproval: monthExpenses.where((e) => e.approvalStatus == 'pending').toList(),
    campaignUse: allocations.where((a) => inMonth(a.entry.createdAt)).toList(),
    inKindReceived: monthDonations.where((d) => d.isCompletedInKind).toList(),
    inKindPledgesOpen: monthDonations.where((d) => d.isPendingInKind).length,
    generalExpensesIncluded: generalExpensesIncluded,
  );
}

int _byDate(DonationHistoryRecord a, DonationHistoryRecord b) =>
    (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthLabel(DateTime m) => '${_monthNames[m.month - 1]} ${m.year}';

String peso(num v) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}PHP $s';
}

String _d(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

// ─── PDF ─────────────────────────────────────────────────────────────────

Future<Uint8List> buildFinancialReportPdf(MonthlyFinanceReport r, {required String organizationName}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(pdfSafe(t), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );
  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> rightAligned = const {}}) =>
      rows.isEmpty
          ? pw.Text('None this month.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
          : pw.TableHelper.fromTextArray(
              headers: headers.map(pdfSafe).toList(),
              data: [for (final row in rows) row.map(pdfSafe).toList()],
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              cellAlignments: {for (final i in rightAligned) i: pw.Alignment.centerRight},
              border: null,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            );
  List<List<String>> lines(List<MoneyLine> l) => [for (final m in l) [m.label, '${m.count}', peso(m.amount)]];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text(pdfSafe('Monthly financial report'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(pdfSafe('$organizationName · ${monthLabel(r.from)}'), style: const pw.TextStyle(fontSize: 11)),
        pw.Text('Generated ${_d(now)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Divider(),
        heading('Summary'),
        table(['', 'Amount'], [
          ['Money received (donations and sponsorships)', peso(r.totalIn)],
          ['Refunded or reversed', peso(-r.totalRefunded)],
          ['Bills paid (rescue cases and running costs)', peso(-r.totalBills)],
          ['Net for the month', peso(r.net)],
        ], rightAligned: {1}),
        if (!r.generalExpensesIncluded)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              pdfSafe('General running costs are not included: only staff who manage finances can see them.'),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
            ),
          ),
        if (r.awaitingApproval.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              pdfSafe('${r.awaitingApproval.length} bill(s) totalling '
                  '${peso(r.awaitingApproval.fold<double>(0, (s, e) => s + e.amount))} are waiting for approval '
                  'and are not counted above.'),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        heading('Money received by type'),
        table(['Type', 'Count', 'Amount'], lines(r.inByType), rightAligned: {1, 2}),
        heading('Money received by payment method'),
        table(['Method', 'Count', 'Amount'], lines(r.inByMethod), rightAligned: {1, 2}),
        heading('Money received by fund'),
        table(['Fund or campaign', 'Count', 'Amount'], lines(r.inByFund), rightAligned: {1, 2}),
        heading('Refunds and reversals'),
        table(['Date', 'Donor', 'Campaign', 'Reason', 'Amount'], [
          for (final d in r.refunds)
            [_d(d.reversedAt ?? d.createdAt), d.displayName, d.campaignName, d.reversalReason ?? '', peso(d.amountValue)],
        ], rightAligned: {4}),
        heading('Bills paid by category'),
        table(['Category', 'Count', 'Amount'], lines(r.billsByCategory), rightAligned: {1, 2}),
        pw.SizedBox(height: 4),
        table(['Kind', 'Count', 'Amount'], lines(r.billsByKind), rightAligned: {1, 2}),
        heading('How campaign funds were used'),
        pw.Text(
          pdfSafe('Spending recorded against campaigns this month. Bills paid from a campaign are already in '
              '"Bills paid" above, so these amounts are not added again.'),
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        table(['Category', 'Count', 'Amount'], lines(r.campaignUseByCategory), rightAligned: {1, 2}),
        heading('In-kind items received'),
        table(['Item', 'Category', 'Quantity', 'Records'], [
          for (final l in r.inKindLines) [l.item, l.category, l.quantity == 0 ? '' : '${l.quantity}', '${l.records}'],
        ], rightAligned: {2, 3}),
        if (r.inKindPledgesOpen > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('${r.inKindPledgesOpen} in-kind pledge(s) from this month are not received yet.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          pdfSafe('Prepared from ResPAWnd records. Money received counts confirmed online payments and offline '
              'donations recorded by a financial administrator, by the date they were recorded. In-kind items '
              'have no peso value here.'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return doc.save();
}

// ─── CSV ─────────────────────────────────────────────────────────────────

Map<String, String> financialReportCsv(MonthlyFinanceReport r) => {
      'money_in': toCsv(
        ['donation_id', 'date', 'type', 'amount', 'method', 'fund', 'donor', 'source'],
        [
          for (final d in r.moneyIn)
            [d.id, d.createdAt, d.type, d.amountValue, d.method,
             d.generalFund || d.campaignId.isEmpty ? 'General fund' : d.campaignName, d.displayName, d.source],
        ],
      ),
      'refunds': toCsv(
        ['donation_id', 'reversed', 'amount', 'campaign', 'donor', 'reason'],
        [for (final d in r.refunds) [d.id, d.reversedAt ?? d.createdAt, d.amountValue, d.campaignName, d.displayName, d.reversalReason]],
      ),
      'bills': toCsv(
        ['expense_id', 'date', 'kind', 'case_id', 'title', 'category', 'amount', 'funded_by', 'approval'],
        [
          for (final e in [...r.bills, ...r.awaitingApproval])
            [e.id, expenseDate(e), e.caseId.isEmpty ? 'general' : 'case', e.caseId, e.title, e.category.label, e.amount,
             e.fundingLabel, e.approvalStatus ?? ''],
        ],
      ),
      'campaign_funds_used': toCsv(
        ['allocation_id', 'date', 'campaign', 'kind', 'label', 'category', 'amount'],
        [for (final a in r.campaignUse) [a.entry.id, a.entry.createdAt, a.campaign, a.entry.kind, a.entry.label, a.entry.category, a.entry.amount]],
      ),
      'in_kind_received': toCsv(
        ['donation_id', 'date', 'item', 'category', 'quantity', 'campaign', 'donor'],
        [for (final d in r.inKindReceived) [d.id, d.createdAt, d.itemDescription, d.category, d.quantityReceived, d.campaignName, d.displayName]],
      ),
    };

// ─── Loading ─────────────────────────────────────────────────────────────

Future<MonthlyFinanceReport> loadMonthlyFinanceReport(String orgId, DateTime month) async {
  final db = FirebaseFirestore.instance;
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);

  // General running costs are readable only with financeManage
  // (firestore.rules); finance viewers get the report without them.
  final generalExpensesFuture = db
      .collection('orgExpenses')
      .where('organizationId', isEqualTo: orgId)
      .get()
      .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
      .catchError((Object e) => e is FirebaseException && e.code == 'permission-denied' ? null : throw e);

  final results = await Future.wait([
    // Donor records for the month (index: organizationId + createdAt).
    db
        .collection('donations')
        .where('organizationId', isEqualTo: orgId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThan: Timestamp.fromDate(to))
        .orderBy('createdAt', descending: true)
        .get(),
    // Reversals of any month's donations; filtered to this month below.
    db.collection('donations').where('organizationId', isEqualTo: orgId).where('status', isEqualTo: 'reversed').get(),
    db.collectionGroup('expenses').where('organizationId', isEqualTo: orgId).get(),
    db.collectionGroup('allocations').where('organizationId', isEqualTo: orgId).get(),
    db.collection('campaigns').where('organizationId', isEqualTo: orgId).get(),
  ]);
  final generalExpenses = await generalExpensesFuture;

  final campaignNames = {
    for (final d in results[4].docs) d.id: (d.data()['title'] as String?)?.trim() ?? d.id,
  };
  final expenses = <Expense>[];
  for (final d in results[2].docs) {
    final parent = d.reference.parent.parent;
    if (parent == null || parent.parent.id != 'cases') continue;
    try {
      expenses.add(Expense.fromFirestore(d, parent.id));
    } catch (_) {}
  }
  for (final d in generalExpenses?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    try {
      expenses.add(Expense.fromFirestore(d, ''));
    } catch (_) {}
  }
  final allocations = [
    for (final d in results[3].docs)
      if (d.data()['status'] != 'voided' && d.reference.parent.parent?.parent.id == 'campaigns')
        (
          campaign: campaignNames[d.reference.parent.parent!.id] ?? d.reference.parent.parent!.id,
          entry: AllocationEntry.fromFirestore(d),
        ),
  ];

  return buildMonthlyFinanceReport(
    from: from,
    to: to,
    donations: results[0].docs.map(DonationHistoryRecord.fromFirestore).toList(),
    reversed: results[1].docs.map(DonationHistoryRecord.fromFirestore).toList(),
    expenses: expenses,
    allocations: allocations,
    generalExpensesIncluded: generalExpenses != null,
  );
}

// ─── Entry point ─────────────────────────────────────────────────────────

/// Asks for a month and a format, then builds and shares the report.
/// Finance staff only; the menus that call this are already gated, and
/// firestore.rules decides what can be read.
Future<void> runMonthlyFinancialReport(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final canView = await container.read(canViewFinancesProvider.future);
  if (!canView) {
    messenger.showSnackBar(const SnackBar(content: Text('Only finance staff can open the financial report.')));
    return;
  }
  if (!context.mounted) return;
  final choice = await _pickMonthAndFormat(context);
  if (choice == null) return;

  messenger.showSnackBar(const SnackBar(content: Text('Preparing the financial report…'), duration: Duration(seconds: 2)));
  try {
    final orgId = await container.read(currentOrganizationIdProvider.future);
    if (orgId == null || orgId.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Your account is not linked to an organization.')));
      return;
    }
    final report = await loadMonthlyFinanceReport(orgId, choice.month);
    final orgSnap = await FirebaseFirestore.instance.collection('organizations').doc(orgId).get();
    final orgName = (orgSnap.data()?['name'] as String?)?.trim();
    final slug = '${choice.month.year}-${choice.month.month.toString().padLeft(2, '0')}';
    if (choice.pdf) {
      final bytes = await buildFinancialReportPdf(report,
          organizationName: (orgName == null || orgName.isEmpty) ? 'Organization' : orgName);
      await Printing.sharePdf(bytes: bytes, filename: 'financial_report_$slug.pdf');
    } else {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (final e in financialReportCsv(report).entries) {
        final f = File('${dir.path}/financial_report_${slug}_${e.key}.csv');
        await f.writeAsString(e.value);
        files.add(XFile(f.path, mimeType: 'text/csv'));
      }
      await SharePlus.instance.share(ShareParams(files: files, text: 'Financial report · ${monthLabel(choice.month)}'));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not build the financial report: $e')));
  }
}

Future<({DateTime month, bool pdf})?> _pickMonthAndFormat(BuildContext context) {
  final now = DateTime.now();
  // This month and the 11 before it; last month is the usual pick.
  final months = [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i)];
  var selected = months.length > 1 ? months[1] : months.first;
  return showModalBottomSheet<({DateTime month, bool pdf})>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Monthly financial report', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Money received, refunds, bills paid and in-kind items for one month.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              DropdownButtonFormField<DateTime>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Month'),
                items: [
                  for (final m in months)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m == months.first ? '${monthLabel(m)} (so far)' : monthLabel(m)),
                    ),
                ],
                onChanged: (v) => setSheet(() => selected = v ?? selected),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: AppButtons.primary,
                onPressed: () => Navigator.pop(ctx, (month: selected, pdf: true)),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text('Share PDF', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: AppButtons.outline,
                onPressed: () => Navigator.pop(ctx, (month: selected, pdf: false)),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: Text('Share CSV files', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
