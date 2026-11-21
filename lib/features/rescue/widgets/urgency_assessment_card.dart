import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/urgency_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// Shows an urgency assessment: the level, why, contradictions and notes.
/// Used live on the report form ([isEstimate]) and read-only on the case
/// screens (reporter's Track Case, staff Rescue Details).
class UrgencyAssessmentCard extends StatefulWidget {
  const UrgencyAssessmentCard({
    super.key,
    required this.assessment,
    this.isEstimate = false,
    this.initiallyExpanded = false,
  });

  final UrgencyAssessment assessment;
  final bool isEstimate;
  final bool initiallyExpanded;

  @override
  State<UrgencyAssessmentCard> createState() => _UrgencyAssessmentCardState();
}

class _UrgencyAssessmentCardState extends State<UrgencyAssessmentCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final a = widget.assessment;
    final color = urgencyColorFor(a.level);
    TextStyle small([Color c = AppColors.textPrimary]) => GoogleFonts.zain(fontSize: 12, color: c);

    Widget bullets(String title, List<String> items, IconData icon) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(item, style: small())),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.isEstimate ? 'Estimated urgency' : 'Assessed urgency'}: ${a.level}',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                if (a.needsStaffVerification)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: 'Needs staff verification',
                      child: const Icon(Icons.fact_check_outlined, size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textPrimary),
              ],
            ),
          ),
          if (a.reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(a.reasons.first, style: small(), maxLines: _expanded ? null : 2, overflow: _expanded ? null : TextOverflow.ellipsis),
          ],
          if (_expanded) ...[
            if (a.reasons.length > 1) bullets('Also considered', a.reasons.skip(1).toList(), Icons.chevron_right),
            if (a.conflicts.isNotEmpty) bullets('Answers that disagree', a.conflicts, Icons.warning_amber_outlined),
            if (a.notes.isNotEmpty) bullets('Notes', a.notes, Icons.info_outline),
            const SizedBox(height: 8),
            Text(
              widget.isEstimate
                  ? 'Worked out from your answers for each animal, and updated as '
                        'you change them. Photos are not analyzed automatically. '
                        'This is not a veterinary assessment: staff review every report.'
                  : 'Worked out from the reporter\'s answers using fixed criteria '
                        '(Low / Medium / Critical). Photos were not analyzed '
                        'automatically. Not a veterinary assessment.',
              style: small(AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
