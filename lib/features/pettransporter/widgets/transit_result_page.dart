// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

// Shown after a transit reaches a terminal outcome — either delivered to
// the shelter (completed) or ended via the End Reason flow (cancelled,
// with the chosen reason). Replaces the old MaterialBanner-on-completion /
// silent-pop-on-cancellation behavior with one consistent result screen
// for both outcomes.
class TransitResultPage extends StatelessWidget {
  final bool completed;
  final String? reason;

  const TransitResultPage({super.key, required this.completed, this.reason});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.rescuerTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: AppColors.textPrimary,
              size: 28,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Pet Transporter Requirements',
            style: GoogleFonts.tiltWarp(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  completed ? 'Transit Completed' : 'Transit Canceled',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tiltWarp(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!completed) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This transit has been cancelled.'
                    '${(reason != null && reason!.isNotEmpty) ? '\nReason: $reason' : ''}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
