// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// "Treatment Rejected" reason picker shown at the clinic. Resolves to the
/// chosen reason (or the typed text for "Other"), or null if cancelled.
Future<String?> showTreatmentRejectDialog(BuildContext context) async {
  final reasons = [
    'Clinic at full capacity',
    'Insufficient Medication/Treatment Supplies',
    'Require specialist care/equipment this clinic does not have',
    'Animal Deceased',
    'No Veterinarian/Specialist Available',
    'Other',
  ];
  String? selectedReason;
  String? other;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => Dialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      'Treatment Rejected',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...reasons.map(
                (r) => RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: r,
                  groupValue: selectedReason,
                  activeColor: AppColors.textPrimary,
                  title: Text(
                    r,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  onChanged: (v) => setDlg(() => selectedReason = v),
                ),
              ),
              if (selectedReason == 'Other') ...[
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => other = v,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe reason…',
                    hintStyle: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.slaterspwn),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: selectedReason == null
                      ? null
                      : () {
                          final reasonStr = selectedReason == 'Other'
                              ? (other != null && other!.isNotEmpty
                                    ? other!
                                    : 'Other')
                              : selectedReason!;
                          Navigator.pop(ctx, reasonStr);
                        },
                  child: Text(
                    'Confirm',
                    style: GoogleFonts.zain(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selectedReason == null
                          ? AppColors.textSecondary
                          : Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
