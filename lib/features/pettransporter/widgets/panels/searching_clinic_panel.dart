// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_swipe_button.dart';

/// A clinic just rejected treatment — auto-searching for the next one.
class SearchingClinicPanel extends StatelessWidget {
  const SearchingClinicPanel({
    super.key,
    required this.lastAddress,
    required this.rejectionReason,
    required this.isSearching,
    required this.onRetry,
  });

  final String lastAddress;

  /// The case's `lastRejectionReason` (raw Firestore value, '' if unset).
  final Object rejectionReason;
  final bool isSearching;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arrived at drop off location',
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
                    lastAddress,
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Treatment has been rejected - $rejectionReason',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: isSearching
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textSecondary,
                        )
                      : const SizedBox.shrink(),
                ),
                if (isSearching) const SizedBox(width: 8),
                Text(
                  isSearching
                      ? 'Finding nearby clinics'
                      : 'Search paused — tap Retry to try again',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (!isSearching) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            TransitSwipeButton(
              label: 'Treatment Rejected',
              onSwiped: null, // locked — reflects the last decision made
            ),
          ],
        ),
      ),
    );
  }
}
