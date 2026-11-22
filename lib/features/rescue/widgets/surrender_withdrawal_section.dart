import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/surrender_withdrawal.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';

/// Pet Surrender, for its reporter: "Withdraw Surrender Request" while the
/// request is active, and the withdrawal details once it has been
/// withdrawn (shown to anyone who can open the case). Nothing otherwise.
class SurrenderWithdrawalSection extends StatefulWidget {
  const SurrenderWithdrawalSection({super.key, required this.caseId, required this.data});

  final String caseId;
  final Map<String, dynamic> data;

  @override
  State<SurrenderWithdrawalSection> createState() => _SurrenderWithdrawalSectionState();
}

class _SurrenderWithdrawalSectionState extends State<SurrenderWithdrawalSection> {
  bool _busy = false;

  bool get _isReporter {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == widget.data['reporterId'];
  }

  Future<void> _withdraw() async {
    if (_busy) return;
    final picked = await showReasonPicker<SurrenderWithdrawalReason>(
      context,
      title: 'Withdraw Surrender Request',
      subtitle: 'Please tell us why. Your pet will be taken off Community Adoption.',
      options: [
        for (final r in SurrenderWithdrawalReason.values)
          ReasonOption(r, r.label, isOther: r == SurrenderWithdrawalReason.other),
      ],
      confirmLabel: 'Continue',
      noteLabel: 'Anything else you want to add (optional)',
    );
    if (picked == null || !mounted) return;
    final ok = await showConfirmActionDialog(
      context,
      title: 'Withdraw this surrender request?',
      message: 'Your pet will no longer be listed for Community Adoption, and any open adoption '
          'inquiries will be closed with a note to the people who asked. Your report is kept in '
          'your History. This can\'t be undone; you can file a new request later if you need to.',
      confirmLabel: 'Withdraw Request',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final user = FirebaseAuth.instance.currentUser!;
    try {
      final closed = await CommunityAdoptionRequestRepository().withdrawSurrender(
        caseId: widget.caseId,
        reporterId: user.uid,
        reporterName: (user.displayName ?? '').trim().isEmpty ? 'The owner' : user.displayName!.trim(),
        reason: picked.value,
        otherText: picked.otherText,
        details: picked.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
        closed > 0
            ? 'Surrender request withdrawn. $closed open inquir${closed == 1 ? 'y was' : 'ies were'} closed.'
            : 'Surrender request withdrawn.',
        kind: AppMessageKind.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
        e is StateError ? e.message : 'Could not withdraw the request: $e',
        kind: AppMessageKind.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final withdrawal = SurrenderWithdrawal.fromCase(widget.data);
    final status = (widget.data['status'] as String? ?? '').toLowerCase();
    TextStyle body([FontWeight w = FontWeight.w400]) =>
        GoogleFonts.zain(fontSize: 13, fontWeight: w, color: AppColors.textPrimary);

    if (status == 'withdrawn') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.slaterspwn.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Surrender request withdrawn', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Reason: ${withdrawal?.reasonLabel ?? 'Not stated'}', style: body(FontWeight.w600)),
            if ((withdrawal?.details ?? '').isNotEmpty) Text(withdrawal!.details!, style: body()),
            if (withdrawal?.withdrawnAt != null) Text('Withdrawn on ${formatDateTime(withdrawal!.withdrawnAt!)}', style: body()),
            const SizedBox(height: 4),
            Text('This pet is no longer listed for Community Adoption. The report is kept for your records.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (!_isReporter || !canWithdrawSurrender(widget.data)) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your surrender request is active', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Your pet is listed for Community Adoption and stays in your care until you choose an adopter. '
            'Changed your plans? You can withdraw the request at any time.',
            style: body(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _withdraw,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.undo, size: 18, color: AppColors.textPrimary),
            label: Text('Withdraw Surrender Request', style: body(FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
