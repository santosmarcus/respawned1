import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Refer to Rescue Volunteer modal.
/// TODO: no volunteer matching/assignment logic yet — this is UI only.
/// RescueCaseRepository.referToVolunteer() exists and records a referral
/// doc, but nothing calls it until this flow is designed (who gets
/// notified, how a volunteer accepts, etc).
Future<void> showReferToVolunteerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Refer to Rescue Volunteer',
              style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Text(
            'Volunteer matching is coming soon. This referral type isn\'t wired up yet.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Close', style: GoogleFonts.tiltWarp(fontSize: 15)),
            ),
          ),
        ],
      ),
    ),
  );
}
