import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Generic confirmation dialog for destructive/irreversible admin actions
/// (reject, merge, refer, etc.). Returns true only if the user tapped the
/// confirm button.
Future<bool> showConfirmActionDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
      content: Text(message,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel,
              style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: destructive ? const Color(0xFFE05353) : AppColors.yellowrspwn,
            foregroundColor: destructive ? Colors.white : AppColors.textPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(confirmLabel, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result ?? false;
}
