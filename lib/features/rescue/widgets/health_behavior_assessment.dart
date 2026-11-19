// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
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
    this.isSurrender = false,
    this.isNeglectAbuse = false,
  });

  final FoundAnimalEntry entry;
  final VoidCallback onChanged;

  /// Pet Surrender: hides Environment and Safety (the owner has the pet at
  /// home) and adds the owner's health records, acquisition, length of
  /// stay and compatibility questions for this animal.
  final bool isSurrender;

  /// Neglect or Abuse: adds visible signs of harm, the living-condition
  /// choices in Environment and Safety, and the medical-attention question.
  final bool isNeglectAbuse;

  Widget _subLabel(String text) => Text(
    text,
    style: GoogleFonts.zain(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  // "Not sure" and the specific compatibility answers exclude each other.
  void _toggleCompatibility(String option) {
    final set = entry.compatibility;
    if (set.remove(option)) return;
    if (option == kSurrenderCompatibilityUnknown) {
      set.clear();
    } else {
      set.remove(kSurrenderCompatibilityUnknown);
    }
    set.add(option);
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
        if (isNeglectAbuse) ...[
          const SizedBox(height: 12),
          _subLabel('Visible signs of harm'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in kNeglectAnimalSignsOptions)
                RescueToggleChip(
                  label: option,
                  selected: entry.harmSigns.contains(option),
                  onTap: () => _set(() {
                    final set = entry.harmSigns;
                    if (set.remove(option)) return;
                    // "No visible signs" and the specific signs exclude
                    // each other.
                    if (option == kNeglectSignsNone) {
                      set.clear();
                    } else {
                      set.remove(kNeglectSignsNone);
                    }
                    set.add(option);
                  }),
                ),
            ],
          ),
        ],
        if (isSurrender) ...[
          const SizedBox(height: 10),
          AssessmentDropdown(
            hintText: 'Vaccination status',
            value: entry.vaccination,
            options: kSurrenderVaccinationOptions,
            onChanged: (v) => _set(() => entry.vaccination = v),
          ),
          const SizedBox(height: 10),
          AssessmentDropdown(
            hintText: 'Spayed / Neutered',
            value: entry.spayNeuter,
            options: kSurrenderSpayNeuterOptions,
            onChanged: (v) => _set(() => entry.spayNeuter = v),
          ),
          const SizedBox(height: 10),
          AssessmentDropdown(
            hintText: 'Where did you acquire this pet?',
            value: entry.acquisitionSource,
            options: kAcquisitionSourceOptions,
            onChanged: (v) => _set(() => entry.acquisitionSource = v),
          ),
          if (entry.isRescueOrgAcquisition) ...[
            const SizedBox(height: 10),
            const _RescueOrgNotice(),
          ],
          const SizedBox(height: 10),
          RescueTextField(
            entry.stayDurationController,
            'How long has the pet stayed with you? (e.g. 2 years)',
          ),
        ],
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
        if (isSurrender) ...[
          const SizedBox(height: 12),
          Text(
            'Gets along with',
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
              for (final option in kSurrenderCompatibilityOptions)
                RescueToggleChip(
                  label: option,
                  selected: entry.compatibility.contains(option),
                  onTap: () => _set(() => _toggleCompatibility(option)),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 12),
          EnvironmentSafetySection(
            entry: entry,
            onChanged: () => _set(() {}),
            extraOptions: isNeglectAbuse
                ? kNeglectEnvironmentOptions
                : const [],
          ),
        ],
        if (isNeglectAbuse) ...[
          const SizedBox(height: 12),
          _subLabel('Does the animal need immediate medical attention?'),
          const SizedBox(height: 2),
          for (final option in kYesNoNotSureOptions)
            RescueRadioOption(
              option,
              entry.needsMedical,
                  (v) => _set(() => entry.needsMedical = v),
            ),
        ],
      ],
    );
  }
}

/// Shown when the pet came from another rescue organization.
class _RescueOrgNotice extends StatelessWidget {
  const _RescueOrgNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.textPrimary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pets adopted from a rescue organization are usually covered '
                  'by a return agreement. Please contact the organization you '
                  'adopted from so they can arrange the return directly.',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
