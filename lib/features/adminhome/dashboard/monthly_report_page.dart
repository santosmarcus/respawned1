import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart' show canViewFinancesProvider;
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart' show currentOrganizationIdProvider;
import 'package:respawnd1/features/adminhome/dashboard/financial_report_export.dart';

/// Opens the Monthly Report screen. One call, so the screen can be linked
/// from the admin menu today and from a dashboard card (or anywhere else)
/// later without touching the screen itself.
Future<void> openMonthlyReport(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthlyReportPage()));

/// The monthly financial report, readable in the app: money received,
/// refunds, bills paid, how campaign funds were used and in-kind items, for
/// a month the user picks. Download PDF and CSV share the same report
/// (functions in financial_report_export.dart). Finance staff only
/// (financeView or financeManage), matching the restricted-finance rule.
class MonthlyReportPage extends ConsumerStatefulWidget {
  const MonthlyReportPage({super.key});

  @override
  ConsumerState<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends ConsumerState<MonthlyReportPage> {
  late final List<DateTime> _months = () {
    final now = DateTime.now();
    return [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i)];
  }();

  /// Last month by default: the usual one to report on.
  late DateTime _month = _months[1];
  Future<({MonthlyFinanceReport report, String orgName})>? _load;
  String? _loadedFor;
  bool _sharing = false;

  Future<({MonthlyFinanceReport report, String orgName})> _fetch(String orgId, DateTime month) async {
    final results = await Future.wait([loadMonthlyFinanceReport(orgId, month), organizationNameFor(orgId)]);
    return (report: results[0] as MonthlyFinanceReport, orgName: results[1] as String);
  }

  Future<void> _share(Future<void> Function() action) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not export the report: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canView = ref.watch(canViewFinancesProvider).asData?.value;
    final orgId = ref.watch(currentOrganizationIdProvider).asData?.value;
    final key = '$orgId|${_month.year}-${_month.month}';
    if (canView == true && orgId != null && orgId.isNotEmpty && _loadedFor != key) {
      _loadedFor = key;
      _load = _fetch(orgId, _month);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.background,
        title: Text('Monthly Report', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: switch (canView) {
        null => const Center(child: CircularProgressIndicator()),
        false => _message('Only finance staff can see the monthly report.'),
        true when orgId == null || orgId.isEmpty => _message('Your account is not linked to an organization.'),
        true => FutureBuilder<({MonthlyFinanceReport report, String orgName})>(
            future: _load,
            builder: (context, snap) {
              final loading = snap.connectionState != ConnectionState.done;
              final data = snap.data;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: DropdownButtonFormField<DateTime>(
                      initialValue: _month,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), isDense: true),
                      items: [
                        for (final m in _months)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m == _months.first ? '${monthLabel(m)} (so far)' : monthLabel(m)),
                          ),
                      ],
                      onChanged: (m) => setState(() => _month = m ?? _month),
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : snap.hasError
                            ? _message('Could not load the report: ${snap.error}')
                            : _ReportBody(report: data!.report),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: AppButtons.primary,
                              onPressed: data == null || _sharing
                                  ? null
                                  : () => _share(() => shareFinancialReportPdf(data.report, organizationName: data.orgName)),
                              icon: const Icon(Icons.download_outlined, size: 18),
                              label: Text('Download PDF', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: AppButtons.outline,
                              onPressed: data == null || _sharing ? null : () => _share(() => shareFinancialReportCsv(data.report)),
                              icon: const Icon(Icons.table_chart_outlined, size: 18),
                              label: Text('CSV', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      },
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
}

class _ReportBody extends StatelessWidget {
  final MonthlyFinanceReport report;
  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final pendingTotal = r.awaitingApproval.fold<double>(0, (s, e) => s + e.amount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _Card(
          title: 'Summary',
          children: [
            _row('Money received', peso(r.totalIn)),
            _row('Refunded or reversed', peso(-r.totalRefunded)),
            _row('Bills paid', peso(-r.totalBills)),
            const Divider(),
            _row('Net for the month', peso(r.net), bold: true),
            if (r.awaitingApproval.isNotEmpty)
              _note('${r.awaitingApproval.length} bill(s) (${peso(pendingTotal)}) are waiting for approval and are not counted.'),
            if (!r.generalExpensesIncluded)
              _note('General running costs are left out: only staff who manage finances can see them.', warn: true),
          ],
        ),
        _lines('Money received by type', r.inByType),
        _lines('By payment method', r.inByMethod),
        _lines('By fund or campaign', r.inByFund),
        _Card(
          title: 'Refunds and reversals',
          children: r.refunds.isEmpty
              ? [_empty()]
              : [
                  for (final d in r.refunds)
                    _row('${d.displayName}${d.campaignName.isEmpty ? '' : ' · ${d.campaignName}'}', peso(d.amountValue)),
                ],
        ),
        _lines('Bills paid by category', r.billsByCategory),
        _lines('Bills paid by kind', r.billsByKind),
        _lines('How campaign funds were used', r.campaignUseByCategory,
            note: 'Bills paid from a campaign are already in "Bills paid", so these are not subtracted again.'),
        _Card(
          title: 'In-kind items received',
          children: [
            if (r.inKindLines.isEmpty) _empty(),
            for (final l in r.inKindLines)
              _row('${l.item}${l.category.isEmpty ? '' : ' · ${l.category}'}',
                  l.quantity == 0 ? '${l.records}×' : '${l.quantity}'),
            if (r.inKindPledgesOpen > 0) _note('${r.inKindPledgesOpen} pledge(s) from this month are not received yet.'),
          ],
        ),
      ],
    );
  }

  Widget _lines(String title, List<MoneyLine> lines, {String? note}) => _Card(
        title: title,
        children: [
          if (lines.isEmpty) _empty(),
          for (final l in lines) _row('${l.label} (${l.count})', peso(l.amount)),
          if (note != null && lines.isNotEmpty) _note(note),
        ],
      );

  static Widget _row(String label, String value, {bool bold = false}) {
    final style = GoogleFonts.zain(
        fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value.replaceFirst('PHP ', '₱'), style: style),
        ],
      ),
    );
  }

  static Widget _note(String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: GoogleFonts.zain(fontSize: 12, color: warn ? AppColors.error : AppColors.textSecondary)),
      );

  static Widget _empty() =>
      Text('None this month.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
