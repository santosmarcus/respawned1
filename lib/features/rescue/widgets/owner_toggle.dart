// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// "Are you the owner?" checkbox option for a Lost Pet report.
class OwnerToggle extends StatelessWidget {
  const OwnerToggle({
    super.key,
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;

  /// The answer this option represents (true = owner).
  final bool value;

  /// The currently selected answer (null = unanswered).
  final bool? selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: selected == value,
                onChanged: (_) => onSelected(value),
                activeColor: AppColors.textPrimary,
                side: const BorderSide(
                  color: AppColors.textPrimary,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
