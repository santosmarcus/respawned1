import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/donation/refund_policy.dart';

import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';

/// Refund request flow, organization side: donors' refund requests, to be
/// checked against the refund policy and approved or declined by a
/// financial administrator. Approving refunds through PayMongo when it can
/// (functions/campaigns.js recordDonationReversal); otherwise the admin
/// refunds by hand first and enters the reference.
class RefundRequestsTab extends ConsumerStatefulWidget {
  const RefundRequestsTab({super.key});

  @override
  ConsumerState<RefundRequestsTab> createState() => _RefundRequestsTabState();
}

class _RefundRequestsTabState extends ConsumerState<RefundRequestsTab> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final async = ref.watch(allDonationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      error: (e, _) => AdminListMessage('Could not load donations: $e'),
      data: (all) {
        final withRequests = all.where((d) => d.refundRequest != null).toList()
          ..sort((a, b) =>
              (b.refundRequest!.requestedAt ?? DateTime(0)).compareTo(a.refundRequest!.requestedAt ?? DateTime(0)));
        final open = withRequests.where((d) => d.refundRequest!.isOpen).toList();
        final done = withRequests.where((d) => !d.refundRequest!.isOpen).toList();
        final list = _showDone ? done : open;
        Widget chip(String label, bool value) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                selected: _showDone == value,
                showCheckmark: false,
                selectedColor: AppColors.yellowrspwn,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.slaterspwn),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onSelected: (_) => setState(() => _showDone = value),
              ),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              chip('To review (${open.length})', false),
              chip('Decided (${done.length})', true),
            ]),
            const SizedBox(height: 8),
            if (!canFinance)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Only financial administrators can approve or decline refunds.',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
              ),
            if (list.isEmpty)
              AdminListMessage(_showDone ? 'No decided requests yet.' : 'No refund requests to review.')
            else
              for (final d in list) _RequestCard(record: d, canDecide: canFinance && !_showDone),
          ],
        );
      },
    );
  }
}

Color _refundStatusColor(String status) => switch (status) {
      'requested' => AppColors.yellowrspwn,
      'processing' => AppColors.lavenderrspwn,
      'failed' => AppColors.warning,
      'refunded' => AppColors.success,
      'declined' => const Color(0xFF9E9E9E),
      _ => AppColors.slaterspwn,
    };

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

  void _show(String title, String message) =>
      showInfoDialog(context, title: title, message: message, closeLabel: 'OK');

  Future<void> _approve() async {
    final input = await showAdminFormSheet<(String, String)>(context, _ApproveSheet(record: r));
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
      if (mounted) showAdminSnack(context, 'Not refunded: ${DonationAdminService.errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final reason = await showAdminFormSheet<String>(context, _DeclineSheet(record: r));
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.declineRefund(r.id, reason: reason);
      if (mounted) showAdminSnack(context, 'Request declined. The donor has been told why.');
    } catch (e) {
      if (mounted) showAdminSnack(context, 'Could not decline: ${DonationAdminService.errorMessage(e)}', error: true);
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
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
              const SizedBox(width: 8),
              DonationPill(rr.label, _refundStatusColor(rr.status)),
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
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
class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.record});
  final DonationHistoryRecord record;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
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
    return AdminSheetFrame(
      title: 'Approve refund',
      doneLabel: 'Approve',
      onDone: ok ? () => Navigator.pop(context, (_note.text.trim(), _reference.text.trim())) : null,
      children: [
        Text('${formatPesoExact(r.amountValue)} to ${r.displayName} for ${r.campaignName}.',
            style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        const FieldLabel('Check against the refund policy'),
        const SizedBox(height: 4),
        _check(rr.reason != null, 'A reason the policy allows: ${rr.reason?.label ?? 'none'}'),
        _check(inTime, 'Requested within ${rr.reason?.requestDays ?? kRefundRequestDays} days of payment'),
        _check(true, 'The money must not be spent yet. If it is, void the spending record first.'),
        const SizedBox(height: 14),
        const FieldLabel('What happens'),
        const SizedBox(height: 4),
        Text(
          '• PayMongo refunds the full amount to the donor\'s original payment method when it can. The '
              'organization covers the payment fees.\n'
              '• If PayMongo can\'t (offline, QR Ph, test mode or past PayMongo\'s time limit), you will be asked to '
              'refund by hand first. Then approve again with the reference number below.\n'
              '• The campaign total goes down, the certificate is voided and the donor is notified.'
              '${r.type == 'sponsorship' ? '\n• The sponsorship ends.' : ''}',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Note (what you checked)', required: true),
        SheetTextField(controller: _note, hint: 'Enter', onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        const FieldLabel('Reference no.'),
        SheetTextField(controller: _reference, hint: 'Only if refunded by hand'),
        const SizedBox(height: 12),
        CheckRow(
          label: 'I checked this request against the refund policy.',
          value: _checked,
          onChanged: (v) => setState(() => _checked = v),
        ),
      ],
    );
  }

  Widget _check(bool ok, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 18, color: ok ? AppColors.success : AppColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
        ]),
      );
}

/// Decline: a reason the donor will read, confirmed.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet({required this.record});
  final DonationHistoryRecord record;

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
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
    return AdminSheetFrame(
      title: 'Decline refund',
      doneLabel: 'Decline',
      onDone: ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
      children: [
        Text('${widget.record.displayName} will be told the reason. The request can\'t be sent again.',
            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        const FieldLabel('Reason (shown to the donor)', required: true),
        SheetTextField(
          controller: _reason,
          hint: 'e.g. The funds were already used for Mochi\'s surgery on Nov 15.',
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        CheckRow(
          label: 'This request does not meet the refund policy.',
          value: _checked,
          onChanged: (v) => setState(() => _checked = v),
        ),
      ],
    );
  }
}
