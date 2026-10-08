import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';

/// Shared high-risk warning banner — same rendering wherever a case's
/// animals' bite/escape risk needs to be surfaced (Rescue Details, Assign
/// Transporter, the transporter's own job-offer screen, Tracking). A case
/// can cover more than one animal, so this takes the full list of flagged
/// animals (see [highRiskAnimalsIn]/[RescueCase.highRiskAnimals]) and lists
/// each one by name — never collapses a multi-animal warning into a single
/// undifferentiated line. Renders nothing when the list is empty, so call
/// sites can drop this in unconditionally without their own risk check.
class RescueRiskBanner extends StatelessWidget {
  final List<HighRiskAnimal> highRiskAnimals;

  const RescueRiskBanner({super.key, this.highRiskAnimals = const []});

  @override
  Widget build(BuildContext context) {
    if (highRiskAnimals.isEmpty) return const SizedBox.shrink();
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
                Text(
                  highRiskAnimals.length > 1 ? 'High-risk animals' : 'High-risk animal',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFB33A3A)),
                ),
                for (final animal in highRiskAnimals)
                  Text('${animal.label} — ${animal.summary}',
                      style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFFB33A3A))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blocking confirmation for one or more high-risk animals — shown before
/// the admin/transporter proceeds (Assign Transporter, accepting a job
/// offer). Only ever called with a non-empty list; an unknown/low-risk
/// animal never triggers this.
Future<bool> confirmHighRiskAcknowledgment(
  BuildContext context, {
  required List<HighRiskAnimal> highRiskAnimals,
}) async {
  final summary = highRiskAnimals.map((a) => '${a.label} — ${a.summary}').join('\n');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(highRiskAnimals.length > 1 ? 'High-risk animals' : 'High-risk animal'),
      content: Text(
        '${summary.isNotEmpty ? '$summary\n\n' : ''}Confirm you understand the risk and have the '
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
