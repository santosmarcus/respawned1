import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/donation/refund_policy.dart';

import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';

/// Refund request flow, organization side: donors' refund requests, to be
/// checked against the refund policy and approved or declined by a
/// financial administrator. Approving refunds through PayMongo when it can
/// (functions/campaigns.js recordDonationReversal); otherwise the admin
/// refunds by hand first and enters the reference.
class RefundRequestsPage extends ConsumerStatefulWidget {
  const RefundRequestsPage({super.key});

  @override
  ConsumerState<RefundRequestsPage> createState() => _RefundRequestsPageState();
}

class _RefundRequestsPageState extends ConsumerState<RefundRequestsPage> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final async = ref.watch(allDonationsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Refund Requests', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
        error: (e, _) => Center(child: Text('Could not load donations: $e')),
        data: (all) {
          final withRequests = all.where((d) => d.refundRequest != null).toList()
            ..sort((a, b) => (b.refundRequest!.requestedAt ?? DateTime(0)).compareTo(a.refundRequest!.requestedAt ?? DateTime(0)));
          final open = withRequests.where((d) => d.refundRequest!.isOpen).toList();
          final done = withRequests.where((d) => !d.refundRequest!.isOpen).toList();
          final list = _showDone ? done : open;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (!canFinance)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Only financial administrators can approve or decline refunds.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
                ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('To review (${open.length})')),
                  ButtonSegment(value: true, label: Text('Decided (${done.length})')),
                ],
                selected: {_showDone},
                onSelectionChanged: (v) => setState(() => _showDone = v.first),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_showDone ? 'No decided requests yet.' : 'No refund requests to review.',
                      textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
                )
              else
                for (final d in list) _RequestCard(record: d, canDecide: canFinance && !_showDone),
            ],
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.record, required this.canDecide});
  final DonationHistoryRecord record;
  final bool canDecide;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  DonationHistoryRecord get r => widget.record;
  RefundRequestInfo get rr => r.refundRequest!;

  void _show(String title, String message, {bool error = false}) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      icon: Icon(error ? Icons.error_outline : Icons.check_circle,
          color: error ? AppColors.error : AppColors.greenrspwn, size: 40),
      title: Text(title, style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      content: Text(message, style: GoogleFonts.zain(fontSize: 15)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );

  Future<void> _approve() async {
    final input = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApproveDialog(record: r),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await DonationAdminService.approveRefund(r.id, note: input.$1, reference: input.$2);
      if (!mounted) return;
      _show(
        'Refund approved',
        res['method'] == 'paymongo'
            ? 'PayMongo is refunding ${formatPesoExact(r.amountValue)} to the donor\'s original payment method '
            '(refund ${res['paymongoRefundId'] ?? ''}). The donor has been notified.'
            : 'The refund was recorded with reference ${input.$2}. The donor has been notified.',
      );
    } catch (e) {
      if (mounted) _show('Not refunded', DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeclineDialog(record: r),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.declineRefund(r.id, reason: reason);
      if (mounted) _show('Request declined', 'The donor has been told why.');
    } catch (e) {
      if (mounted) _show('Could not decline', DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = r.when;
    final daysSince = paid == null ? null : DateTime.now().difference(paid).inDays;
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))),
        Expanded(child: Text(v, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
      ]),
    );
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${formatPesoExact(r.amountValue)} · ${r.displayName}',
                    style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              ),
              Text(rr.label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            row(r.type == 'sponsorship' ? 'Sponsorship' : 'Campaign', r.campaignName),
            row('Paid', '${formatLongDate(paid)}${daysSince == null ? '' : ' ($daysSince days ago)'} · ${r.method}'),
            row('Reason', rr.reason?.label ?? '-'),
            if (rr.details.isNotEmpty) row('Details', rr.details),
            row('Requested', formatLongDate(rr.requestedAt)),
            if (rr.status == 'failed')
              row('PayMongo', 'Could not refund${rr.failCodes.isEmpty ? '' : ' (${rr.failCodes.join(', ')})'}. Refund by hand and approve with the reference.'),
            if (rr.status == 'declined') row('Declined', rr.declineReason ?? '-'),
            if (rr.status == 'refunded' || rr.status == 'processing')
              row('Refunded', rr.method == 'paymongo' ? 'Through PayMongo ${rr.paymongoRefundId ?? ''}' : 'By hand, ref ${rr.manualReference ?? '-'}'),
            if (widget.canDecide) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _decline,
                    style: AppButtons.outline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _approve,
                    style: AppButtons.primary,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Approve: the checks against the refund policy, what will happen, an
/// optional reference for a refund made by hand, and a confirmation box.
class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.record});
  final DonationHistoryRecord record;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _note = TextEditingController();
  final _reference = TextEditingController();
  bool _checked = false;

  @override
  void dispose() {
    _note.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final rr = r.refundRequest!;
    final paid = r.when;
    final inTime = rr.reason == null || refundReasonInTime(rr.reason!, paid, now: rr.requestedAt);
    final ok = _checked && _note.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Approve refund?', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${formatPesoExact(r.amountValue)} to ${r.displayName} for ${r.campaignName}.',
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('Check against the refund policy', style: GoogleFonts.tiltWarp(fontSize: 14)),
            const SizedBox(height: 4),
            _check(rr.reason != null, 'A reason the policy allows: ${rr.reason?.label ?? 'none'}'),
            _check(inTime, 'Requested within ${rr.reason?.requestDays ?? kRefundRequestDays} days of payment'),
            _check(true, 'The money must not be spent yet. If it is, void the spending record first.'),
            const SizedBox(height: 10),
            Text('What happens', style: GoogleFonts.tiltWarp(fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '• PayMongo refunds the full amount to the donor\'s original payment method when it can. The '
                  'organization covers the payment fees.\n'
                  '• If PayMongo can\'t (offline, QR Ph, test mode or past PayMongo\'s time limit), you will be asked to '
                  'refund by hand first. Then approve again with the reference number below.\n'
                  '• The campaign total goes down, the certificate is voided and the donor is notified.'
                  '${r.type == 'sponsorship' ? '\n• The sponsorship ends.' : ''}',
              style: GoogleFonts.zain(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Note (what you checked)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Reference no. (only if refunded by hand)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: Text('I checked this request against the refund policy.',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: ok ? () => Navigator.pop(context, (_note.text.trim(), _reference.text.trim())) : null,
          style: AppButtons.primary,
          child: const Text('Approve refund'),
        ),
      ],
    );
  }

  Widget _check(bool ok, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
          size: 18, color: ok ? AppColors.greenrspwn : AppColors.warning),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: GoogleFonts.zain(fontSize: 13))),
    ]),
  );
}

/// Decline: a reason the donor will read, confirmed.
class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog({required this.record});
  final DonationHistoryRecord record;

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _reason = TextEditingController();
  bool _checked = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _checked && _reason.text.trim().length >= 5;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Decline refund request?', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.record.displayName} will be told the reason. The request can\'t be sent again.',
                style: GoogleFonts.zain(fontSize: 14)),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason (shown to the donor)',
                hintText: 'e.g. The funds were already used for Mochi\'s surgery on Nov 15.',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: Text('This request does not meet the refund policy.',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
          style: AppButtons.dangerOutline,
          child: const Text('Decline'),
        ),
      ],
    );
  }
}
