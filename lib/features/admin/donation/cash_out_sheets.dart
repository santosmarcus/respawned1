import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/cash_out.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';

// Cash-outs: money taken out of PayMongo, the bank, an e-wallet or the cash
// box (functions/campaigns.js, functions/paymongo.js). Written for people
// who aren't used to accounting words: "Where did this money go?" means
// "which fund did it come from and what was it for", and the answer becomes
// ordinary spending records on those funds (Fund Tracking).

bool _isGeneralFund(DonationListing l) => l.id.startsWith('general_') || l.fundKind == 'general';

String _fundName(DonationListing l) => _isGeneralFund(l) ? 'General fund' : (l.title.isEmpty ? 'Untitled fund' : l.title);

/// Funds money can come from: the organization's listings that aren't
/// drafts or archived, General fund first, then those with the most money.
List<DonationListing> cashOutFunds(List<DonationListing> all) {
  final list = all.where((l) => !l.isArchived && l.status != 'draft').toList()
    ..sort((a, b) {
      final g = (_isGeneralFund(b) ? 1 : 0) - (_isGeneralFund(a) ? 1 : 0);
      return g != 0 ? g : b.availableBalance.compareTo(a.availableBalance);
    });
  return list;
}

/// One "this much from this fund, for this" row being edited.
class FundSplitLine {
  FundSplitLine({this.campaignId, this.category = 'Other', String amount = ''})
      : amount = TextEditingController(text: amount);

  String? campaignId;
  String category;
  final TextEditingController label = TextEditingController();
  final TextEditingController amount;

  double? get parsedAmount => parsePesoInput(amount.text);

  void dispose() {
    label.dispose();
    amount.dispose();
  }

  Map<String, dynamic> toMap() => {
        'campaignId': campaignId,
        'category': category,
        'label': label.text.trim(),
        'amount': parsedAmount,
      };
}

/// What's wrong with [lines] in plain words, or null when they can be sent.
String? fundSplitProblem(List<FundSplitLine> lines, Map<String, DonationListing> funds, {required double limit}) {
  var total = 0.0;
  final perFund = <String, double>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final n = lines.length > 1 ? ' (part ${i + 1})' : '';
    if (l.campaignId == null) return 'Choose which fund the money came from$n.';
    final a = l.parsedAmount;
    if (a == null) return 'Enter how much$n.';
    if (l.label.text.trim().isEmpty) return 'Write a short description$n, for example "Dog food for November".';
    total += a;
    perFund[l.campaignId!] = (perFund[l.campaignId!] ?? 0) + a;
  }
  if (total > limit + 0.001) return 'That adds up to ${formatPesoExact(total)}, more than the ${formatPesoExact(limit)} taken out.';
  for (final e in perFund.entries) {
    final f = funds[e.key];
    if (f != null && e.value > f.availableBalance + 0.001) {
      return '${_fundName(f)} only has ${formatPesoExact(f.availableBalance)} available.';
    }
  }
  return null;
}

double fundSplitTotal(List<FundSplitLine> lines) => lines.fold(0.0, (s, l) => s + (l.parsedAmount ?? 0));

/// The fund/purpose/amount rows with "Split into another fund".
class FundSplitEditor extends StatelessWidget {
  final List<FundSplitLine> lines;
  final List<DonationListing> funds;
  final double limit;
  final VoidCallback onChanged;
  final bool enabled;

  const FundSplitEditor({
    super.key,
    required this.lines,
    required this.funds,
    required this.limit,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final left = limit - fundSplitTotal(lines);
    final small = GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary);
    if (funds.isEmpty) {
      return _box('Your organization has no fund to take this from yet. Record the donation it came from first '
          '(menu → Record donation), or use "It was already recorded".');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slaterspwn),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(lines.length > 1 ? 'Part ${i + 1}' : 'Taken from',
                          style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    if (lines.length > 1)
                      IconButton(
                        tooltip: 'Remove this part',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: enabled
                            ? () {
                                lines.removeAt(i).dispose();
                                onChanged();
                              }
                            : null,
                      ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  initialValue: lines[i].campaignId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Which fund did it come from?', isDense: true),
                  items: [
                    for (final f in funds)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text('${_fundName(f)} · ${formatPesoExact(f.availableBalance)} available',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled
                      ? (v) {
                          lines[i].campaignId = v;
                          onChanged();
                        }
                      : null,
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: lines[i].category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'What was it for?', isDense: true),
                  items: [for (final c in kAllocationCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: enabled
                      ? (v) {
                          lines[i].category = v ?? lines[i].category;
                          onChanged();
                        }
                      : null,
                ),
                SheetTextField(controller: lines[i].label, hint: 'Short description, e.g. "Dog food for November"'),
                SheetTextField(
                  controller: lines[i].amount,
                  hint: 'How much',
                  prefix: '₱ ',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                left > 0.004
                    ? 'Left without a fund: ${formatPesoExact(left)}'
                    : left < -0.004
                        ? 'Over by ${formatPesoExact(-left)}'
                        : 'All of it has a fund ✓',
                style: GoogleFonts.zain(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: left < -0.004
                      ? AppColors.error
                      : left > 0.004
                          ? AppColors.warning
                          : AppColors.success,
                ),
              ),
            ),
            if (lines.length < 10)
              TextButton.icon(
                onPressed: enabled
                    ? () {
                        lines.add(FundSplitLine(amount: left > 0.004 ? _plain(left) : ''));
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Split into another fund'),
              ),
          ],
        ),
        Text('Each part is saved as spending on that fund, so its balance and Fund Tracking stay correct.', style: small),
      ],
    );
  }
}

String _plain(double v) => (v * 100).round() % 100 == 0 ? v.round().toString() : v.toStringAsFixed(2);

Widget _box(String text, {Color color = AppColors.tearspwn}) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
    );

String cashOutHeadline(CashOut c) {
  final when = c.occurredAt ?? c.createdAt;
  final date = when == null ? '' : ' on ${formatDate(when)}';
  return c.source == 'paymongo'
      ? '${formatPesoExact(c.amount)} was paid out from PayMongo$date'
      : '${formatPesoExact(c.amount)} was taken out (${c.sourceLabel.toLowerCase()})$date';
}

Map<String, DonationListing> _byId(List<DonationListing> funds) => {for (final f in funds) f.id: f};

String? _defaultFund(List<DonationListing> funds, double amount) {
  for (final f in funds) {
    if (f.availableBalance + 0.001 >= amount) return f.id;
  }
  return funds.isEmpty ? null : funds.first.id;
}

// ─── Where did this money go? ─────────────────────────────────────────────────

Future<void> showAssignCashOutSheet(BuildContext context, CashOut cashOut) =>
    showAdminFormSheet<void>(context, AssignCashOutSheet(cashOut: cashOut));

class AssignCashOutSheet extends ConsumerStatefulWidget {
  final CashOut cashOut;
  const AssignCashOutSheet({super.key, required this.cashOut});

  @override
  ConsumerState<AssignCashOutSheet> createState() => _AssignCashOutSheetState();
}

class _AssignCashOutSheetState extends ConsumerState<AssignCashOutSheet> {
  // One id per opened sheet: a retried Save can't record the spending twice.
  final String _requestId = DonationAdminService.newRequestId();
  final List<FundSplitLine> _lines = [];
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _seed(List<DonationListing> funds) {
    if (_seeded || funds.isEmpty) return;
    _seeded = true;
    final left = widget.cashOut.remaining;
    _lines.add(FundSplitLine(campaignId: _defaultFund(funds, left), amount: _plain(left)));
  }

  Future<void> _save(List<DonationListing> funds) async {
    final left = widget.cashOut.remaining;
    final problem = fundSplitProblem(_lines, _byId(funds), limit: left);
    if (problem != null) {
      showAdminSnack(context, problem, error: true);
      return;
    }
    final unassigned = left - fundSplitTotal(_lines);
    if (unassigned > 0.004) {
      final ok = await confirmAction(
        context,
        title: 'Save part of it?',
        message: '${formatPesoExact(unassigned)} will still have no fund. It stays on the Donations screen until '
            'someone chooses one.',
        confirmLabel: 'Save this part',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await DonationAdminService.assignCashOut(
        cashOutId: widget.cashOut.id,
        requestId: _requestId,
        lines: [for (final l in _lines) l.toMap()],
      );
      if (!mounted) return;
      showAdminSnack(context, 'Saved. The others who manage money were told.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _alreadyRecorded() async {
    final note = await showTextInputDialog(
      context,
      title: 'Already recorded?',
      message: 'Use this when the spending is already in the app, for example as a general expense or a campaign '
          'allocation, so it isn\'t counted twice.',
      label: 'Where was it recorded?',
      hint: 'e.g. General expenses: November electricity bill',
      confirmLabel: 'Mark as recorded',
      required: true,
    );
    if (note == null || note.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.settleCashOut(cashOutId: widget.cashOut.id, note: note.trim());
      if (!mounted) return;
      showAdminSnack(context, 'Marked as already recorded.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cashOut;
    final fundsAsync = ref.watch(orgCampaignsProvider);
    final funds = cashOutFunds(fundsAsync.asData?.value ?? const []);
    _seed(funds);
    return AdminSheetFrame(
      title: 'Where did this money go?',
      doneLabel: 'Save',
      busy: _busy,
      onDone: fundsAsync.isLoading ? null : () => _save(funds),
      children: [
        _box(
          [
            '${cashOutHeadline(c)}.',
            if (c.assignedAmount > 0) '${formatPesoExact(c.assignedAmount)} already has a fund; ${formatPesoExact(c.remaining)} is left.',
            if ((c.note ?? '').isNotEmpty) c.note!,
          ].join('\n'),
          color: AppColors.yellowrspwn,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Tell us which fund this money came from and what it was for. If it paid for different things, split it.',
            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
          ),
        ),
        if (fundsAsync.isLoading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else
          FundSplitEditor(
            lines: _lines,
            funds: funds,
            limit: c.remaining,
            enabled: !_busy,
            onChanged: () => setState(() {}),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _alreadyRecorded,
          child: const Text('It was already recorded somewhere else'),
        ),
      ],
    );
  }
}

// ─── Record money taken out ───────────────────────────────────────────────────

Future<void> showRecordCashOutSheet(BuildContext context) =>
    showAdminFormSheet<void>(context, const RecordCashOutSheet());

class RecordCashOutSheet extends ConsumerStatefulWidget {
  const RecordCashOutSheet({super.key});

  @override
  ConsumerState<RecordCashOutSheet> createState() => _RecordCashOutSheetState();
}

class _RecordCashOutSheetState extends ConsumerState<RecordCashOutSheet> {
  final String _requestId = DonationAdminService.newRequestId();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final List<FundSplitLine> _lines = [FundSplitLine()];
  String _source = 'bank';
  DateTime _date = DateTime.now();
  bool _decideLater = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(List<DonationListing> funds) async {
    final amount = parsePesoInput(_amount.text);
    if (amount == null) {
      showAdminSnack(context, 'Enter how much was taken out.', error: true);
      return;
    }
    final lines = _decideLater ? const <FundSplitLine>[] : _lines;
    if (lines.isNotEmpty) {
      final problem = fundSplitProblem(lines, _byId(funds), limit: amount);
      if (problem != null) {
        showAdminSnack(context, problem, error: true);
        return;
      }
      final left = amount - fundSplitTotal(lines);
      if (left > 0.004) {
        final ok = await confirmAction(
          context,
          title: 'Part of it has no fund yet',
          message: '${formatPesoExact(left)} will stay on the Donations screen until someone chooses a fund.',
          confirmLabel: 'Save',
        );
        if (!ok || !mounted) return;
      }
    }
    setState(() => _busy = true);
    try {
      await DonationAdminService.recordCashOut(
        requestId: _requestId,
        source: _source,
        amount: amount,
        occurredAt: _date,
        note: _note.text,
        lines: [for (final l in lines) l.toMap()],
      );
      if (!mounted) return;
      showAdminSnack(context, 'Recorded. The others who manage money were told.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fundsAsync = ref.watch(orgCampaignsProvider);
    final funds = cashOutFunds(fundsAsync.asData?.value ?? const []);
    final amount = parsePesoInput(_amount.text) ?? 0;
    if (_lines.length == 1 && _lines.first.campaignId == null && funds.isNotEmpty) {
      _lines.first.campaignId = _defaultFund(funds, amount);
    }
    return AdminSheetFrame(
      title: 'Record money taken out',
      doneLabel: 'Save',
      busy: _busy,
      onDone: fundsAsync.isLoading ? null : () => _save(funds),
      children: [
        Text('Use this whenever money leaves PayMongo, the bank, GCash or the cash box.',
            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
        SheetTextField(
          controller: _amount,
          hint: 'How much was taken out',
          prefix: '₱ ',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            // Keep a single part in step with the total until it's edited.
            if (_lines.length == 1) {
              final a = parsePesoInput(v);
              _lines.first.amount.text = a == null ? '' : _plain(a);
            }
          }),
        ),
        const SizedBox(height: 10),
        Text('Taken from', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in kCashOutSources.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _source == e.key,
                onSelected: _busy ? null : (_) => setState(() => _source = e.key),
              ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('Date: ${formatDate(_date)}', style: GoogleFonts.zain(fontSize: 16)),
          trailing: const Text('Change'),
          onTap: _busy ? null : _pickDate,
        ),
        SheetTextField(controller: _note, hint: 'Note (optional), e.g. "Withdrawn by Ana at BPI Taft"'),
        const SizedBox(height: 14),
        Text('Where will this money go?', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        CheckRow(
          label: 'I\'ll decide later (it stays on the Donations screen as a reminder)',
          value: _decideLater,
          onChanged: (v) => setState(() => _decideLater = v),
        ),
        if (!_decideLater)
          if (fundsAsync.isLoading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else
            FundSplitEditor(
              lines: _lines,
              funds: funds,
              limit: amount,
              enabled: !_busy,
              onChanged: () => setState(() {}),
            ),
      ],
    );
  }
}

// ─── Reminder on the Donations screen ─────────────────────────────────────────

/// Shown above the Donations tabs while any cash-out has no fund. Everyone
/// who can see the money sees it; only those who manage money can answer.
class CashOutReminderBanner extends ConsumerWidget {
  const CashOutReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openCashOutsProvider);
    if (open.isEmpty) return const SizedBox.shrink();
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final first = open.first;
    final total = open.fold(0.0, (s, c) => s + c.remaining);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open.length == 1 ? 'Where did this money go?' : '${open.length} cash-outs need a fund',
                  style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                Text(
                  open.length == 1
                      ? '${cashOutHeadline(first)}.${canManage ? '' : ' Someone who manages money needs to choose its fund.'}'
                      : '${formatPesoExact(total)} in total has no fund yet.'
                          '${canManage ? '' : ' Someone who manages money needs to choose.'}',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => open.length == 1 && canManage
                ? showAssignCashOutSheet(context, first)
                : Navigator.push(context, MaterialPageRoute(builder: (_) => const CashOutsPage())),
            child: Text(open.length == 1 && canManage ? 'Choose fund' : 'View'),
          ),
        ],
      ),
    );
  }
}

/// Cash-outs already asked about in this app session (the pop-up appears
/// once each; the banner stays until they're sorted out).
final Set<String> _askedCashOutIds = {};

/// A pop-up the first time someone who manages money opens Donations while
/// a cash-out has no fund. Call from a build method.
void listenForUnassignedCashOuts(BuildContext context, WidgetRef ref) {
  ref.listen<List<CashOut>>(openCashOutsProvider, (previous, next) async {
    final canManage = ref.read(canManageFinancesProvider).asData?.value ?? false;
    if (!canManage) return;
    final fresh = next.where((c) => !_askedCashOutIds.contains(c.id)).toList();
    if (fresh.isEmpty) return;
    _askedCashOutIds.addAll(fresh.map((c) => c.id));
    final c = fresh.first;
    final go = await showConfirmActionDialog(
      context,
      title: 'Where did this money go?',
      message: '${cashOutHeadline(c)}.'
          '${fresh.length > 1 ? ' (${fresh.length - 1} more also need a fund.)' : ''}\n\n'
          'Choose which fund it came from and what it was for, so your fund balances and reports stay correct.',
      confirmLabel: 'Choose fund',
      cancelLabel: 'Later',
    );
    if (go && context.mounted) await showAssignCashOutSheet(context, c);
  });
}

// ─── Money taken out (history) ────────────────────────────────────────────────

class CashOutsPage extends ConsumerStatefulWidget {
  /// Opened from a notification: open this one's sheet once it loads.
  final String? openId;
  const CashOutsPage({super.key, this.openId});

  @override
  ConsumerState<CashOutsPage> createState() => _CashOutsPageState();
}

class _CashOutsPageState extends ConsumerState<CashOutsPage> {
  bool _openedFromNotice = false;

  void _open(CashOut c, bool canManage) {
    if (c.isOpen && canManage) {
      showAssignCashOutSheet(context, c);
      return;
    }
    showAdminFormSheet<void>(context, _CashOutDetails(cashOut: c));
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final async = ref.watch(cashOutsProvider);
    final list = async.asData?.value ?? const <CashOut>[];
    if (!_openedFromNotice && widget.openId != null && async.hasValue) {
      _openedFromNotice = true;
      final match = list.where((c) => c.id == widget.openId);
      if (match.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _open(match.first, canManage));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Money taken out')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showRecordCashOutSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Record money taken out'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load the cash-outs.')),
        data: (_) => list.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Nothing recorded yet. When money is paid out from PayMongo, or someone records money taken '
                    'out, it shows here and the app asks which fund it came from.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CashOutCard(cashOut: list[i], onTap: () => _open(list[i], canManage)),
              ),
      ),
    );
  }
}

class _CashOutCard extends StatelessWidget {
  final CashOut cashOut;
  final VoidCallback onTap;
  const _CashOutCard({required this.cashOut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = cashOut;
    final when = c.occurredAt ?? c.createdAt;
    final color = c.isOpen ? AppColors.warning : AppColors.success;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatPesoExact(c.amount),
                        style: GoogleFonts.zain(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    Text([c.sourceLabel, if (when != null) formatDate(when)].join(' · '),
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    if (c.lines.isNotEmpty)
                      Text(
                        c.lines.map((l) => '${formatPesoExact(l.amount)} ${l.campaignTitle}').join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text(c.statusLabel, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashOutDetails extends StatelessWidget {
  final CashOut cashOut;
  const _CashOutDetails({required this.cashOut});

  @override
  Widget build(BuildContext context) {
    final c = cashOut;
    final text = GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary);
    final small = GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${cashOutHeadline(c)}.', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Recorded by ${c.recordedByName.isEmpty ? 'someone' : c.recordedByName} · ${c.statusLabel}', style: small),
            if ((c.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.note!, style: text)),
            const SizedBox(height: 12),
            for (final l in c.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${formatPesoExact(l.amount)} from ${l.campaignTitle} · ${l.category}\n'
                  '${l.label}${l.byName == null ? '' : ' (by ${l.byName})'}',
                  style: text,
                ),
              ),
            if (c.status == 'already_recorded')
              Text('Already recorded: ${c.settleNote ?? ''}', style: text),
            if (c.isOpen)
              Text('${formatPesoExact(c.remaining)} still needs a fund. Someone who manages money can choose it.',
                  style: text.copyWith(color: AppColors.warning)),
          ],
        ),
      ),
    );
  }
}
