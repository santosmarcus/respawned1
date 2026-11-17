import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/refund_policy.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

// The donor side of the refund request flow:
//  * showRefundPolicyConfirmation: before every donation or sponsorship
//    payment, the donor reads the refund policy and agrees to it.
//  * RefundRequestSection: on the History summary of a donation or
//    sponsorship, the request's status or a "Request refund" button.
//  * RefundRequestPage: the request itself: policy, procedure, reason,
//    terms, and a final confirmation before it is sent.

Widget _bullets(List<String> items, {bool numbered = false}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < items.length; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(numbered ? '${i + 1}.' : '•',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            Expanded(child: Text(items[i], style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary, height: 1.3))),
          ],
        ),
      ),
  ],
);

Widget _heading(String t) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Text(t, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
);

/// Shown before every donation or sponsorship payment. Returns true only
/// when the donor ticks the box and taps Agree and continue.
Future<bool> showRefundPolicyConfirmation(BuildContext context, {required bool isSponsorship}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RefundPolicyDialog(isSponsorship: isSponsorship),
  );
  return ok == true;
}

class _RefundPolicyDialog extends StatefulWidget {
  const _RefundPolicyDialog({required this.isSponsorship});
  final bool isSponsorship;

  @override
  State<_RefundPolicyDialog> createState() => _RefundPolicyDialogState();
}

class _RefundPolicyDialogState extends State<_RefundPolicyDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Before you pay', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isSponsorship
                    ? 'Your sponsorship covers 30 days of care. Please read our refund policy.'
                    : 'Your donation goes straight to the animals\' care. Please read our refund policy.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
              ),
              _heading('Refund policy'),
              _bullets(kRefundPolicyPoints),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: Text('I have read and agree to the refund policy.',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
        ),
        ElevatedButton(
          onPressed: _agreed ? () => Navigator.pop(context, true) : null,
          style: AppButtons.primary,
          child: Text('Agree and continue', style: GoogleFonts.tiltWarp(fontSize: 14)),
        ),
      ],
    );
  }
}

/// On the History summary: the refund request's status, or the button to
/// ask for one while the donor still can.
class RefundRequestSection extends StatelessWidget {
  const RefundRequestSection({super.key, required this.donationId});
  final String donationId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('donations').doc(donationId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return const SizedBox.shrink();
        final info = RefundRequestInfo.fromMap(data['refundRequest']);
        if (info != null) return _StatusCard(info: info, method: (data['method'] ?? data['donationMethod'] ?? '').toString());
        final blocker = refundRequestBlocker(data, uid: FirebaseAuth.instance.currentUser?.uid);
        if (blocker != null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RefundRequestPage(donationId: donationId, donation: data)),
              ),
              icon: const Icon(Icons.undo, color: AppColors.textPrimary),
              label: Text('Request refund', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              style: AppButtons.outline,
            ),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.info, required this.method});
  final RefundRequestInfo info;
  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (info.status) {
      'refunded' => AppColors.greenrspwn,
      'declined' => AppColors.error,
      _ => AppColors.warning,
    };
    final lines = <String>[
      if (info.reason != null) 'Reason: ${info.reason!.label}',
      if (info.requestedAt != null) 'Requested on ${formatDate(info.requestedAt!)}',
      switch (info.status) {
        'requested' || 'failed' => 'The organization is reviewing your request.',
        'processing' => 'PayMongo is sending your refund. ${refundTimingFor(method)}',
        'refunded' => info.method == 'paymongo'
            ? 'Refunded to your original payment method. ${refundTimingFor(method)}'
            : 'Refunded by the organization${info.manualReference == null ? '' : ' (reference ${info.manualReference})'}.',
        'declined' => 'Declined: ${info.declineReason ?? 'no reason given'}',
        _ => '',
      },
    ].where((s) => s.isNotEmpty).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.label, style: GoogleFonts.tiltWarp(fontSize: 15, color: color)),
          const SizedBox(height: 4),
          for (final l in lines) Text(l, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// The refund request: policy, procedure, reason and details, terms, and a
/// final confirmation. Writes `donations/{id}.refundRequest` (firestore.rules
/// donorRefundRequest checks it again); the organization decides it.
class RefundRequestPage extends StatefulWidget {
  const RefundRequestPage({super.key, required this.donationId, required this.donation});
  final String donationId;
  final Map<String, dynamic> donation;

  @override
  State<RefundRequestPage> createState() => _RefundRequestPageState();
}

class _RefundRequestPageState extends State<RefundRequestPage> {
  RefundReason? _reason;
  final _details = TextEditingController();
  bool _agreed = false;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Map<String, dynamic> get d => widget.donation;
  bool get _isSponsorship => d['type'] == 'sponsorship';
  DateTime? get _paidAt => d['timestamp'] is Timestamp ? (d['timestamp'] as Timestamp).toDate() : null;
  String get _method => (d['method'] ?? d['donationMethod'] ?? '').toString();
  String get _amount => (d['amountString'] as String?) ?? '₱${(d['amount'] as num).toStringAsFixed(2)}';

  String? get _problem {
    if (_reason == null) return 'Choose why you are asking for a refund.';
    if (!refundReasonInTime(_reason!, _paidAt)) {
      return 'This reason can only be used within ${_reason!.requestDays} days of payment.';
    }
    if (_details.text.trim().length < 10) return 'Tell us a little more (at least 10 characters).';
    if (!_agreed) return 'Agree to the refund terms to continue.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _problem;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(problem, kind: AppMessageKind.error));
      return;
    }
    // Final confirmation, with exactly what is being sent.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Send refund request?', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_amount ${_isSponsorship ? 'sponsorship' : 'donation'} to ${d['campaignName'] ?? 'this campaign'}',
                  style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Reason: ${_reason!.label}', style: GoogleFonts.zain(fontSize: 14)),
              const SizedBox(height: 10),
              _bullets([
                'You can send only one request for this payment, and it can\'t be changed afterwards.',
                'The organization reviews it, usually within 5 working days.',
                refundTimingFor(_method),
                if (_isSponsorship) 'If approved, your sponsorship ends.',
                'If approved, your Certificate of Donation for this payment is voided.',
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: AppButtons.primary,
            child: Text('Send request', style: GoogleFonts.tiltWarp(fontSize: 14)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('donations').doc(widget.donationId).update({
        'refundRequest': {
          'status': 'requested',
          'reason': _reason!.key,
          'details': _details.text.trim(),
          'requestedAt': FieldValue.serverTimestamp(),
          'termsVersion': kRefundTermsVersion,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          'Refund request sent. You will be notified when the organization decides.',
          kind: AppMessageKind.success));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          e is FirebaseException && e.code == 'permission-denied'
              ? 'This payment can no longer be refunded (the time allowed has passed, or a request was already sent).'
              : 'Could not send your request: $e',
          kind: AppMessageKind.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = RefundReason.forType((d['type'] ?? 'donation').toString());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Request refund', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_amount · ${_isSponsorship ? 'Sponsorship' : 'Donation'}',
                    style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                Text((d['campaignName'] ?? '').toString(), style: GoogleFonts.zain(fontSize: 14)),
                if (_paidAt != null)
                  Text('Paid on ${formatDate(_paidAt!)}${_method.isEmpty ? '' : ' · $_method'}',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          _heading('Refund policy'),
          _bullets(kRefundPolicyPoints),
          _heading('What happens next'),
          _bullets(kRefundProcedure, numbered: true),
          _heading('Why are you asking for a refund?'),
          for (final r in reasons)
            RadioListTile<RefundReason>(
              contentPadding: EdgeInsets.zero,
              value: r,
              groupValue: _reason,
              onChanged: refundReasonInTime(r, _paidAt) ? (v) => setState(() => _reason = v) : null,
              title: Text(r.label, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
              subtitle: Text(
                refundReasonInTime(r, _paidAt) ? r.description : 'Only within ${r.requestDays} days of payment.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLines: 3,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Details',
              hintText: 'e.g. I was charged twice on Nov 17 at 3 PM',
              border: OutlineInputBorder(),
            ),
          ),
          _heading('Terms'),
          _bullets(kRefundTerms),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: Text('I have read the refund policy, the procedure and the terms, and I agree to them.',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _sending || _problem != null ? null : _submit,
            style: AppButtons.primary,
            child: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Review and send', style: GoogleFonts.tiltWarp(fontSize: 15)),
          ),
          if (_problem != null && _reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_problem!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}
