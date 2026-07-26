import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';

/// Shared high-risk warning banner — same rendering wherever a specific
/// animal's bite/escape risk needs to be surfaced (Rescue Details, Assign
/// Transporter, the transporter's own job-offer screen, Tracking). Renders
/// nothing at all when neither risk is elevated, so call sites can drop
/// this in unconditionally without their own risk check.
class RescueRiskBanner extends StatelessWidget {
  final String? biteRisk;
  final String? escapeRisk;
  final List<String> safetyIndicators;
  final String? handlingNotes;

  const RescueRiskBanner({
    super.key,
    this.biteRisk,
    this.escapeRisk,
    this.safetyIndicators = const [],
    this.handlingNotes,
  });

  bool get isHighRisk => hasHighRescueRisk(biteRisk: biteRisk, escapeRisk: escapeRisk);

  @override
  Widget build(BuildContext context) {
    if (!isHighRisk) return const SizedBox.shrink();
    final summary = rescueRiskSummary(biteRisk: biteRisk, escapeRisk: escapeRisk);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE05353).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE05353)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE05353), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('High-risk animal',
                    style: GoogleFonts.zain(
                        fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFB33A3A))),
                if (summary.isNotEmpty)
                  Text(summary, style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFFB33A3A))),
                if (safetyIndicators.isNotEmpty)
                  Text(safetyIndicators.join(', '),
                      style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFFB33A3A))),
                if ((handlingNotes ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Handling notes: ${handlingNotes!.trim()}',
                        style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFFB33A3A))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blocking confirmation for a high-risk animal — shown before the admin/
/// transporter proceeds (Assign Transporter, accepting a job offer). Only
/// ever called when [RescueRiskBanner.isHighRisk] is already true; an
/// unknown/low-risk animal never triggers this.
Future<bool> confirmHighRiskAcknowledgment(
  BuildContext context, {
  required String? biteRisk,
  required String? escapeRisk,
}) async {
  final summary = rescueRiskSummary(biteRisk: biteRisk, escapeRisk: escapeRisk);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('High-risk animal'),
      content: Text(
        '${summary.isNotEmpty ? '$summary. ' : ''}Confirm you understand the risk and have the '
        'equipment/precautions needed before proceeding.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE05353), foregroundColor: Colors.white),
          child: const Text('I Understand, Proceed'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
