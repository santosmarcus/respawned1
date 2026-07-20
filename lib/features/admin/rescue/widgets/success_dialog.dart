import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Generic success confirmation dialog shown after an admin action commits
/// successfully (accept, reject, merge, referral sent, ...).
Future<void> showSuccessDialog(
  BuildContext context, {
  required String title,
  String? message,
  String buttonLabel = 'OK',
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.greenrspwn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),
        ],
      ),
      content: message == null
          ? null
          : Text(message, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellowrspwn,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(buttonLabel, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
