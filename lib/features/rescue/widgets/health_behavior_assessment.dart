// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/environment_safety_section.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Health & Behavior Assessment — restored per-animal section, below the
/// base Species/Breed/Sex/Size/Color fields and above Bite/Escape Risk.
/// Every option list/conflict rule comes from the shared
/// core/utils/animal_health_assessment.dart constants — never duplicated
/// here — so this page can't drift from any other reader of the same
/// values.
class HealthBehaviorAssessment extends StatelessWidget {
  const HealthBehaviorAssessment({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Health & Behavior Assessment',
          style: GoogleFonts.zain(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        AssessmentDropdown(
          hintText: 'Body Condition',
          value: entry.bodyCondition,
          options: kBodyConditionOptions,
          onChanged: (v) => _set(() => entry.bodyCondition = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Mobility',
          value: entry.mobility,
          options: kMobilityOptions,
          onChanged: (v) => _set(() => entry.mobility = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Alertness',
          value: entry.alertness,
          options: kAlertnessOptions,
          onChanged: (v) => _set(() => entry.alertness = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Eyes, Nose, Mouth',
          value: entry.eyesNoseMouth,
          options: kEyesNoseMouthOptions,
          onChanged: (v) => _set(() => entry.eyesNoseMouth = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Skin and Coat',
          value: entry.skinAndCoat,
          options: kSkinAndCoatOptions,
          onChanged: (v) => _set(() => entry.skinAndCoat = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Appetite and Hydration',
          value: entry.appetiteHydration,
          options: kAppetiteHydrationOptions,
          onChanged: (v) => _set(() => entry.appetiteHydration = v),
        ),
        const SizedBox(height: 12),
        Text(
          'Behavior',
          style: GoogleFonts.zain(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kBehaviorOptions)
              RescueToggleChip(
                label: option,
                selected: entry.behavior.contains(option),
                onTap: () => _set(() {
                  if (entry.behavior.contains(option)) {
                    entry.behavior.remove(option);
                  } else {
                    entry.behavior.add(option);
                    // Deselect anything this option conflicts with, in
                    // both directions — 'Calm' clears 'Aggressive' and
                    // vice versa.
                    final conflicts = kBehaviorConflicts[option] ?? const {};
                    entry.behavior.removeWhere((b) => conflicts.contains(b));
                    for (final other in List.of(entry.behavior)) {
                      if ((kBehaviorConflicts[other] ?? const {}).contains(
                        option,
                      )) {
                        entry.behavior.remove(other);
                      }
                    }
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        EnvironmentSafetySection(entry: entry, onChanged: () => _set(() {})),
      ],
    );
  }
}
