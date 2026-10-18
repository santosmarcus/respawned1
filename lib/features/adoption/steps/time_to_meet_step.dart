// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_formatting.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';
import 'package:respawnd1/features/adoption/widgets/delivery_info_card.dart';

/// Step 4 — appointment confirmed / reservation and delivery details.
class TimeToMeetStep extends StatelessWidget {
  const TimeToMeetStep({
    super.key,
    required this.form,
    required this.animalName,
    required this.readOnly,
    required this.isSubmitting,
    required this.isReservedForMe,
    required this.scheduledReleaseDate,
    required this.deliveryAttempts,
    required this.onWithdraw,
    required this.onRequestReschedule,
  });

  final AdoptionFormController form;
  final String animalName;

  /// True while reviewing a previous step (read only).
  final bool readOnly;
  final bool isSubmitting;
  final bool isReservedForMe;
  final DateTime? scheduledReleaseDate;
  final int deliveryAttempts;
  final VoidCallback onWithdraw;
  final VoidCallback onRequestReschedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time to meet!',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your adoption application and interview appointment have been '
          'confirmed!',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'ll finalize the remaining requirements and prepare '
          '$animalName for their forever home. We are excited '
          'to get to know you as a potential adopter!',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        if (form.appointmentDate != null) ...[
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
                Text(
                  '${form.appointmentType}  ·  ${formatAdoptionDate(form.appointmentDate!)} ·  ${form.appointmentTime!}',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (isReservedForMe) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.lavenderrspwn.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.favorite,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$animalName has been reserved for you!',
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

        // Delivery — shown once the organization has scheduled a release
        // date/time (see ReleaseDetailsPage, admin-side). Staying on this
        // step (rather than jumping straight to "Adoption Day") until that
        // date/time actually arrives is handled in _loadExistingAdoption.
        if (scheduledReleaseDate != null) ...[
          const SizedBox(height: 16),
          DeliveryInfoCard(
            scheduledReleaseDate: scheduledReleaseDate,
            deliveryAttempts: deliveryAttempts,
            showAttempts: true,
            useGrayAttempts: true,
          ),
          if (!readOnly) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    (isSubmitting || deliveryAttempts >= kMaxDeliveryAttempts)
                    ? null
                    : onRequestReschedule,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: deliveryAttempts >= kMaxDeliveryAttempts
                        ? AppColors.slaterspwn
                        : AppColors.greenrspwn,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  deliveryAttempts >= kMaxDeliveryAttempts
                      ? 'No reschedule attempts remaining'
                      : 'Request Reschedule',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],

        if (!readOnly && scheduledReleaseDate == null) ...[
          const SizedBox(height: 28),
          // The organization completes the actual handoff (Release
          // Animal, from the admin Adoption Application Review module) —
          // this screen just reflects that live once it happens, rather
          // than letting the applicant self-declare adoption complete.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.slaterspwn.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Center(
              child: Text(
                'Waiting for the organization to release the animal to you.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          // Withdrawing stays available until the organization schedules
          // the release; after that the adopter uses Request Reschedule.
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
