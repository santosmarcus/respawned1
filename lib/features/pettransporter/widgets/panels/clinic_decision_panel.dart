// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_swipe_button.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_info_widgets.dart';

/// Arrived at a clinic — Treatment Accepted / Treatment Rejected decision.
class ClinicDecisionPanel extends StatelessWidget {
  const ClinicDecisionPanel({
    super.key,
    required this.address,
    required this.images,
    required this.isActing,
    required this.clinicProfileFuture,
    required this.onImageTap,
    required this.onAccept,
    required this.onReject,
  });

  final String address;
  final List<File?> images;
  final bool isActing;
  final Future<Map<String, dynamic>?> clinicProfileFuture;
  final ValueChanged<int> onImageTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final canDecide = !isActing;

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
            const SizedBox(height: 8),
            ClinicHistoryNote(future: clinicProfileFuture),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Provide images to verify',
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

            const SizedBox(height: 20),

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
                    address,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            TransitSwipeButton(
              label: 'Treatment Accepted',
              onSwiped: canDecide ? onAccept : null,
            ),
            const SizedBox(height: 10),
            TransitSwipeButton(
              label: 'Treatment Rejected',
              onSwiped: canDecide ? onReject : null,
            ),
          ],
        ),
      ),
    );
  }
}
