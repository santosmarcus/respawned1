// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_formatting.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';

/// Step 3 — application under review.
class ApplicationReviewStep extends StatelessWidget {
  const ApplicationReviewStep({
    super.key,
    required this.form,
    required this.animalName,
    required this.readOnly,
    required this.isSubmitting,
    required this.onPickDate,
    required this.onWithdraw,
  });

  final AdoptionFormController form;
  final String animalName;

  /// True while reviewing a previous step (read only).
  final bool readOnly;
  final bool isSubmitting;
  final VoidCallback onPickDate;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application review',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve received your interest in adopting $animalName.',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Please allow us time to review your form and confirm your appointment. If you need to reschedule, kindly update your meeting date at least 3 days before your appointment.',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        // The actual booked interview date/time, so "confirm your
        // appointment" above isn't the only information the applicant sees
        // about a slot they already picked.
        if (form.appointmentDate != null && form.appointmentTime != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_available,
                  color: AppColors.greenrspwn,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$form.appointmentType  ·  ${formatAdoptionDate(form.appointmentDate!)}  ·  $form.appointmentTime',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (!readOnly) ...[
          const SizedBox(height: 28),
          AdoptionPrimaryButton(
            label: 'Change date',
            onTap: isSubmitting ? null : onPickDate,
          ),

          const SizedBox(height: 12),
          AdoptionSecondaryButton(
            label: 'Withdraw Application',
            onTap: isSubmitting ? null : onWithdraw,
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }
}
