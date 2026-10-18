// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';

/// Step 5 — Application Update (rejected).
class ApplicationUpdateStep extends StatelessWidget {
  const ApplicationUpdateStep({super.key, required this.animalName});

  final String animalName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Update',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Thank you for your interest in adopting $animalName.',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'After careful review, we feel this may not be the best match at this time.\n\nWe truly appreciate your willingness to give a rescue a loving generalhome, and we encourage you to consider other pets in need — your perfect companion could be waiting!',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 28),

        AdoptionPrimaryButton(
          label: 'Close',
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
