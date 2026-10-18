// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_swipe_button.dart';

/// Photo-verification step (arrived at pickup, or final shelter drop-off):
/// title, address, a 2-image grid, the next destination, optional contact
/// rows, the confirm swipe and an optional Close button.
class VerificationPanel extends StatelessWidget {
  const VerificationPanel({
    super.key,
    required this.title,
    required this.address,
    required this.images,
    required this.onImageTap,
    required this.onConfirm,
    required this.confirmLabel,
    required this.isActing,
    this.onEnd,
    this.destinationAddress,
    this.contactRows,
  });

  final String title;
  final String address;
  final List<File?> images;
  final Function(int) onImageTap;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final bool isActing;
  final VoidCallback? onEnd;
  // Where the animal is headed next (e.g. the assigned clinic) — shown
  // in the address row below the image grid. Defaults to [address]
  // itself for panels that only ever have one relevant location (the
  // final shelter drop-off), but the pickup-verification panel passes
  // the clinic address here so it isn't just a second copy of the
  // pickup address above it.
  final String? destinationAddress;

  /// Reporter/organization contact rows to show under the address, or
  /// null to omit them (only the pickup-verification panel shows them).
  final List<Widget>? contactRows;

  @override
  Widget build(BuildContext context) {
    final contactRows = this.contactRows;
    final bottomAddress = destinationAddress ?? address;
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
              title,
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
                    address,
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Provide images and video to verify',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // image grid
            Row(
              children: List.generate(
                2,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                  child: GestureDetector(
                    onTap: () => onImageTap(i),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: images[i] != null
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.tearspwn.withValues(alpha: 0.15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: images[i] != null
                          ? Image.file(images[i]!, fit: BoxFit.cover)
                          : const Center(
                              child: Icon(
                                Icons.add,
                                size: 28,
                                color: AppColors.textSecondary,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Address below images — the NEXT destination, not a repeat
            // of the pickup address above.
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    bottomAddress,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            // Reporter/witness and organization contact rows
            if (contactRows != null) ...[
              const SizedBox(height: 12),
              ...contactRows,
            ],

            const SizedBox(height: 20),

            // Confirm button — swipeable, matching every other
            // progression action in this flow (On the way / Arrived /
            // Treatment Accepted-Rejected all use TransitSwipeButton; this one
            // shouldn't be the lone plain tap button).
            TransitSwipeButton(
              label: confirmLabel,
              onSwiped: isActing ? null : onConfirm,
            ),
            const SizedBox(height: 14),

            if (onEnd != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onEnd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.slaterspwn,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}
