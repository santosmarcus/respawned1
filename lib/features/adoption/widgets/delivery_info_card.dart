// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/features/adoption/adoption_formatting.dart';

/// Scheduled delivery date/time (and attempts used) once the organization
/// has released the animal. Renders nothing until a date is set.
class DeliveryInfoCard extends StatelessWidget {
  const DeliveryInfoCard({
    super.key,
    required this.scheduledReleaseDate,
    required this.deliveryAttempts,
    required this.showAttempts,
    required this.useGrayAttempts,
  });

  final DateTime? scheduledReleaseDate;
  final int deliveryAttempts;
  final bool showAttempts;
  final bool useGrayAttempts;

  @override
  Widget build(BuildContext context) {
    if (scheduledReleaseDate == null) return const SizedBox.shrink();

    final attemptsColor = useGrayAttempts
        ? Colors.grey.shade600
        : AppColors.textPrimary.withValues(alpha: 0.75);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderrspwn.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delivery Date',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatAdoptionDate(scheduledReleaseDate!)} at ${formatAdoptionTime(scheduledReleaseDate!)}',
            style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (showAttempts) ...[
            const SizedBox(height: 8),
            Text(
              'Delivery attempts used: $deliveryAttempts of $kMaxDeliveryAttempts',
              style: GoogleFonts.zain(fontSize: 12, color: attemptsColor),
            ),
          ],
        ],
      ),
    );
  }
}
