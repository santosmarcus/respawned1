// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_terms_page.dart';
import 'package:respawnd1/features/adoption/widgets/delivery_info_card.dart';

/// Step 5 — Adoption Day (success).
class AdoptionDayStep extends StatelessWidget {
  const AdoptionDayStep({
    super.key,
    required this.animalName,
    required this.scheduledReleaseDate,
    required this.deliveryAttempts,
  });

  final String animalName;
  final DateTime? scheduledReleaseDate;
  final int deliveryAttempts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adoption Day!',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Congratulations on your new furry companion!',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'The organization will safely deliver your pet to your generalhome. You\'ll also receive an adoption agreement outlining terms and conditions, post-adoption guidelines, and return policies. For your convenience, you may review the Terms and Conditions in advance below.',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'re so happy for you and your new best friend!',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        if (scheduledReleaseDate != null) ...[
          const SizedBox(height: 16),
          DeliveryInfoCard(
            scheduledReleaseDate: scheduledReleaseDate,
            deliveryAttempts: deliveryAttempts,
            showAttempts: true,
            useGrayAttempts: true,
          ),
        ],

        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AdoptionTermsAndConditionsPage(animalName: animalName),
                ),
              );
            },
            child: Text(
              'View Terms and Conditions',
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        AdoptionPrimaryButton(
          label: 'Close',
          onTap: () {
            // Pop back to root (adoption list)
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
