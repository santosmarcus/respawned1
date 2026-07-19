import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';

typedef RejectionResult = ({RejectionReason reason, String? otherText});

/// Rejection Reason modal. Returns null if the sheet was dismissed without
/// confirming, otherwise the chosen reason (+ free text if [RejectionReason.other]).
Future<RejectionResult?> showRejectionReasonSheet(BuildContext context) {
  return showModalBottomSheet<RejectionResult>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _RejectionReasonSheetBody(),
  );
}

class _RejectionReasonSheetBody extends StatefulWidget {
  const _RejectionReasonSheetBody();

  @override
  State<_RejectionReasonSheetBody> createState() => _RejectionReasonSheetBodyState();
}

class _RejectionReasonSheetBodyState extends State<_RejectionReasonSheetBody> {
  RejectionReason? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      _selected != null &&
      (_selected != RejectionReason.other || _otherController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Rejection Reason',
                  style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 16),
            ...RejectionReason.values.map((reason) {
              final isOther = reason == RejectionReason.other;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _selected == reason,
                        onChanged: (_) => setState(() => _selected = reason),
                        activeColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isOther) ...[
                      Text('Other: ',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                      Expanded(
                        child: TextField(
                          controller: _otherController,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.zain(fontSize: 14),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.only(bottom: 4),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.textPrimary),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.textPrimary, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ] else
                      Text(reason.label,
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canConfirm
                    ? () => Navigator.pop(
                          context,
                          (
                            reason: _selected!,
                            otherText: _selected == RejectionReason.other
                                ? _otherController.text.trim()
                                : null,
                          ),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE05353),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Confirm Rejection', style: GoogleFonts.tiltWarp(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
