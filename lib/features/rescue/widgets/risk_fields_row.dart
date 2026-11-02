// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';

import 'package:respawnd1/core/utils/rescue_risk.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Bite risk / Escape risk side by side when there's enough width for
/// both dropdowns to stay legible, stacked full-width otherwise — fixes
/// the "RIGHT OVERFLOWED BY 25 PIXELS" this row produced on narrow
/// devices (the long option strings, e.g. "Has attempted to bite", plus
/// two Expanded halves in a Row, didn't leave enough room). Each
/// dropdown also gets isExpanded + ellipsis so a long value never
/// overflows even at the breakpoint boundary or under text scaling.
class RiskFieldsRow extends StatelessWidget {
  const RiskFieldsRow({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final FoundAnimalEntry entry;
  final VoidCallback onChanged;

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    const breakpoint = 340.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bite = RiskDropdown(
          label: 'Bite Risk',
          hintText: 'Select',
          value: entry.biteRisk,
          options: kBiteRiskLevels,
          onChanged: (v) => _set(() => entry.biteRisk = v),
        );
        final escape = RiskDropdown(
          label: 'Escape Risk',
          hintText: 'Select',
          value: entry.escapeRisk,
          options: kEscapeRiskLevels,
          onChanged: (v) => _set(() => entry.escapeRisk = v),
        );
        if (constraints.maxWidth < breakpoint) {
          return Column(children: [bite, const SizedBox(height: 10), escape]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: bite),
            const SizedBox(width: 10),
            Expanded(child: escape),
          ],
        );
      },
    );
  }
}
