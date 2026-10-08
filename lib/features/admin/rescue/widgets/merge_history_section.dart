import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// Merged Cases section on the rescue detail page — duplicate reports that
/// were merged into this case. Neither this case nor any merged case is
/// ever deleted, so these stay tappable references to the original reports.
class MergeHistorySection extends StatelessWidget {
  final RescueCase rescueCase;
  final void Function(String caseId) onOpenCase;

  const MergeHistorySection({
    super.key,
    required this.rescueCase,
    required this.onOpenCase,
  });

  @override
  Widget build(BuildContext context) {
    final mergedIds = rescueCase.mergedCaseIds;
    final mergedInto = rescueCase.mergedIntoCaseId;

    return SectionCard(
      title: 'Merged Cases',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mergedInto != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => onOpenCase(mergedInto),
                child: Text(
                  'This report was merged into CASE ID: ${shortCaseId(mergedInto)}',
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (mergedIds.isEmpty && mergedInto == null)
            Text('No merged duplicates.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
          else
            ...mergedIds.map((id) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => onOpenCase(id),
                    child: Text(
                      'CASE ID: ${shortCaseId(id)}',
                      style: GoogleFonts.zain(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
