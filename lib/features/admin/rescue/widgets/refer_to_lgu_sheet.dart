import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// Refer to LGU/Barangay modal. Suggests a barangay from the report's
/// address (best-effort text heuristic — there's no barangay-boundary
/// lookup service wired up), allows manual override/search, a reason
/// dropdown, a detailed explanation, and optionally attaching the report's
/// existing media. Sending always adds a statusHistory entry the reporter's
/// own tracker reads, which is how they get notified.
Future<bool> showReferToLguSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required RescueCaseRepository caseRepository,
  required String actorUid,
  required String actorName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReferToLguSheetBody(
      rescueCase: rescueCase,
      caseRepository: caseRepository,
      actorUid: actorUid,
      actorName: actorName,
    ),
  );
  return result ?? false;
}

String _suggestBarangay(String? address) {
  if (address == null || address.trim().isEmpty) return '';
  final parts = address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  // Best-effort: PH addresses are typically "Street, Barangay/City, Province ZIP".
  // The second segment is the closest approximation available without a real
  // barangay-boundary lookup.
  if (parts.length >= 2) return parts[1];
  return parts.isNotEmpty ? parts.first : '';
}

class _ReferToLguSheetBody extends StatefulWidget {
  final RescueCase rescueCase;
  final RescueCaseRepository caseRepository;
  final String actorUid;
  final String actorName;

  const _ReferToLguSheetBody({
    required this.rescueCase,
    required this.caseRepository,
    required this.actorUid,
    required this.actorName,
  });

  @override
  State<_ReferToLguSheetBody> createState() => _ReferToLguSheetBodyState();
}

class _ReferToLguSheetBodyState extends State<_ReferToLguSheetBody> {
  late final TextEditingController _barangayController =
      TextEditingController(text: _suggestBarangay(widget.rescueCase.address));
  final _explanationController = TextEditingController();
  LguReferralReason? _reason;
  bool _attachMedia = true;
  bool _sending = false;

  @override
  void dispose() {
    _barangayController.dispose();
    _explanationController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _barangayController.text.trim().isNotEmpty &&
      _reason != null &&
      _explanationController.text.trim().isNotEmpty;

  Future<void> _send() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Refer to ${_barangayController.text.trim()}?',
      message: 'The reporter will be notified that this case was referred to the '
          'LGU/barangay.',
      confirmLabel: 'Send Referral',
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    try {
      await widget.caseRepository.referToLgu(
        caseId: widget.rescueCase.id,
        barangay: _barangayController.text.trim(),
        reason: _reason!,
        explanation: _explanationController.text.trim(),
        attachReportMedia: _attachMedia,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send referral: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggested = _suggestBarangay(widget.rescueCase.address);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Refer to LGU / Barangay',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            Text('Barangay', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
            if (suggested.isNotEmpty)
              Text('Suggested based on report location: "$suggested"',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _barangayController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search or enter barangay',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 18),

            Text('Reason', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<LguReferralReason>(
              initialValue: _reason,
              hint: Text('Select a reason',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.only(bottom: 8),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
              ),
              items: LguReferralReason.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (val) => setState(() => _reason = val),
            ),
            const SizedBox(height: 18),

            Text('Detailed Explanation',
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _explanationController,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Explain why this case is being referred…',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _attachMedia,
                    onChanged: (v) => setState(() => _attachMedia = v ?? true),
                    activeColor: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Attach report details and media',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_canSend && !_sending) ? _send : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Send Referral & Notify Reporter',
                        style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
