// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_swipe_button.dart';

// Treatment accepted, interested adopter expected — waits at the clinic.
// The "Adopter Arrived" action only appears once the reporter has
// already tapped their own "Arrived at Treatment" button in
// TrackCasePage (adopterArrivedAtTreatment == true); before that, this
// just shows a waiting state so the transporter knows why they're not
// moving toward the shelter yet.
class AwaitingAdopterPanel extends StatelessWidget {
  const AwaitingAdopterPanel({
    super.key,
    required this.address,
    required this.adopterArrived,
    required this.isActing,
    required this.onAdopterArrived,
  });

  final String address;
  final bool adopterArrived;
  final bool isActing;
  final VoidCallback onAdopterArrived;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Awaiting adopter pickup',
              style: GoogleFonts.tiltWarp(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address.isEmpty ? 'Clinic' : address,
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lavenderrspwn.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The reporter expressed interest in adopting this animal. '
                'Stay at the treatment location — the animal goes home with '
                'them directly instead of continuing to the shelter.',
                style: GoogleFonts.zain(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!adopterArrived) ...[
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Waiting for the adopter to mark their arrival on their end.',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              TransitSwipeButton(
                label: 'Adopter Arrived',
                onSwiped: isActing ? null : onAdopterArrived,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
