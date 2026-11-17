import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_service.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';

/// Online (PayMongo) payments whose paid amount differed from the amount
/// priced, so they were not credited (status needs_review). Reached from the
/// dashboard's "donation to verify" alert. Financial admins of the owning
/// organization accept one for the amount actually paid (credited like any
/// verified payment) or void it with a reason (functions/paymongo.js
/// settleFlaggedPayment, which also refuses everyone else).
class FlaggedPaymentsPage extends ConsumerStatefulWidget {
  const FlaggedPaymentsPage({super.key});

  @override
  ConsumerState<FlaggedPaymentsPage> createState() => _FlaggedPaymentsPageState();
}

class _FlaggedPaymentsPageState extends ConsumerState<FlaggedPaymentsPage> {
  final _busy = <String>{};

  Future<void> _run(PaymentAttempt p, Future<String> Function() action) async {
    if (_busy.contains(p.id)) return;
    setState(() => _busy.add(p.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await action();
      messenger.showSnackBar(appSnackBar(done, kind: AppMessageKind.success));
    } catch (e) {
      messenger.showSnackBar(appSnackBar(DonationAdminService.errorMessage(e), kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _check(PaymentAttempt p) => _run(p, () async {
        final res = await DonationAdminService.settleFlaggedPayment(p.id, 'check');
        final paid = res['paidAmount'];
        return paid is num ? 'PayMongo received ${formatPesoExact(paid)}.' : 'Checked with PayMongo.';
      });

  Future<void> _accept(PaymentAttempt p) async {
    final paid = p.paidAmount;
    final ok = await showConfirmActionDialog(
      context,
      title: 'Accept for the amount paid?',
      message: paid == null
          ? 'The amount PayMongo actually received will be credited to "${p.campaignName}" '
              '(it is checked with PayMongo first). The donor gets their certificate for that amount.'
          : '${formatPesoExact(paid)} (paid) will be credited to "${p.campaignName}" instead of the '
              '${formatPesoExact(p.amount)} priced. The donor gets their certificate for ${formatPesoExact(paid)}.',
      confirmLabel: 'Accept',
    );
    if (!ok || !mounted) return;
    await _run(p, () async {
      final res = await DonationAdminService.settleFlaggedPayment(p.id, 'accept');
      final credited = res['creditedAmount'];
      return credited is num ? '${formatPesoExact(credited)} credited.' : 'Payment accepted.';
    });
  }

  Future<void> _void(PaymentAttempt p) async {
    final reason = await showTextInputDialog(
      context,
      title: 'Void this payment?',
      message: 'Nothing is credited and the alert is cleared. Any refund to the donor is done in the PayMongo dashboard.',
      label: 'Reason',
      hint: 'e.g. duplicate payment, refunded in PayMongo',
      confirmLabel: 'Void',
      required: true,
      destructive: true,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await _run(p, () async {
      await DonationAdminService.settleFlaggedPayment(p.id, 'void', reason: reason);
      return 'Payment voided.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final orgId = ref.watch(currentOrganizationIdProvider).asData?.value;
    final campaigns = ref.watch(orgCampaignsProvider).asData?.value;
    final paymentsAsync = ref.watch(paymentAttemptsProvider);

    Widget body;
    if (!canFinance) {
      body = _message('Only financial administrators can review flagged payments.');
    } else {
      body = paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _message('Could not load payments: $e'),
        data: (all) {
          // Only this organization's campaigns (platform admins see all).
          final mine = campaigns?.map((c) => c.id).toSet();
          final flagged = all
              .where((p) => p.status == 'needs_review')
              .where((p) =>
                  orgId == null || p.organizationId == orgId || (mine != null && mine.contains(p.campaignId)))
              .toList();
          if (flagged.isEmpty) return _message('No payments are waiting for review.');
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: flagged.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _PaymentCard(
              payment: flagged[i],
              busy: _busy.contains(flagged[i].id),
              onCheck: () => _check(flagged[i]),
              onAccept: () => _accept(flagged[i]),
              onVoid: () => _void(flagged[i]),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AdminAppBar(title: 'Payments to Verify', showDrawerButton: false),
      body: body,
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
        ),
      );
}

class _PaymentCard extends StatelessWidget {
  final PaymentAttempt payment;
  final bool busy;
  final VoidCallback onCheck;
  final VoidCallback onAccept;
  final VoidCallback onVoid;
  const _PaymentCard({
    required this.payment,
    required this.busy,
    required this.onCheck,
    required this.onAccept,
    required this.onVoid,
  });

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: SelectableText(value,
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.campaignName.isEmpty ? 'Donation' : p.campaignName,
              style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          _row('Priced amount', formatPesoExact(p.amount)),
          _row('Paid amount', p.paidAmount == null ? 'Not recorded yet' : formatPesoExact(p.paidAmount!)),
          _row('PayMongo payment', p.paymongoPaymentId ?? '—'),
          _row('Checkout session', p.checkoutSessionId ?? '—'),
          _row('Method', p.methodLabel.isEmpty ? '—' : p.methodLabel),
          if (p.createdAt != null) _row('Started', formatDateTime(p.createdAt!)),
          const SizedBox(height: 10),
          if (busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (p.paidAmount == null)
                  OutlinedButton(onPressed: onCheck, child: const Text('Check with PayMongo')),
                OutlinedButton(
                  onPressed: onVoid,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Void'),
                ),
                FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary),
                  child: Text('Accept amount paid',
                      style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.background)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
