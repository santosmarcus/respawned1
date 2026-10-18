// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';

/// Step 5 — application withdrawn by the adopter.
class WithdrawnStep extends StatelessWidget {
  const WithdrawnStep({
    super.key,
    required this.animalName,
    required this.readOnly,
    required this.onStartOver,
  });

  final String animalName;

  /// True while reviewing a previous step (read only).
  final bool readOnly;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Withdrawn',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'You\'ve withdrawn your adoption application for $animalName.',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'No further action is needed on your end. If you change your mind, you\'re welcome to submit a new application for this pet or explore other rescues looking for their forever home.',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 28),

        AdoptionPrimaryButton(
          label: 'Okay',
          onTap: readOnly
              ? null
              : () {
                  // Confirming the withdrawal notice resets the whole process
                  onStartOver();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AdoptionPage()),
                    (route) => false,
                  );
                },
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
