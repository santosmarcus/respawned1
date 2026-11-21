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
    this.rescueType,
    this.showEnvironmentSafety = true,
    this.isOwnedPet = false,
  });

  final FoundAnimalEntry entry;
  final VoidCallback onChanged;

  /// Pet Surrender: hides Environment and Safety (the owner has the pet at
  /// home) and adds the owner's health records, acquisition, length of
  /// stay and compatibility questions for this animal.
  final bool isSurrender;

  /// Injury, Illness and Neglect or Abuse add the animal's visible signs
  /// (choices per type), the living-condition choices in Environment and
  /// Safety, and the medical-attention question.
  final String? rescueType;

  /// False on the lost-pet owner's form: Environment and Safety describes
  /// where the animal is now, which the owner doesn't know.
  final bool showEnvironmentSafety;

  /// True on the lost-pet owner's form: Behavior lists how an owned pet
  /// usually acts (kOwnedPetBehaviorOptions) instead of how a stray behaves
  /// on the street, and the prompts speak to the owner.
  final bool isOwnedPet;

  List<String> get _behaviorOptions =>
      isOwnedPet ? kOwnedPetBehaviorOptions : kBehaviorOptions;
  Map<String, Set<String>> get _behaviorConflicts =>
      isOwnedPet ? kOwnedPetBehaviorConflicts : kBehaviorConflicts;

  List<String>? get _signOptions => visibleSignsOptionsFor(rescueType);

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
        RescueSubsectionHeader(
          'Health assessment',
          subtitle: isOwnedPet
              ? 'How your pet was when it went missing. Choose "Not sure / Not assessed" if you don\'t know.'
              : 'Select what you observed. Choose "Not sure / Not assessed" if you could not check.',
        ),
        const SizedBox(height: 8),
        // Visible injury feeds the urgency assessment. Not asked on a
        // surrender (no urgency) or on the lost-pet owner's form.
        if (!isSurrender && !isOwnedPet) ...[
          AssessmentDropdown(
            hintText: 'Visible injury (how serious?)',
            value: entry.injury,
            options: kInjuryOptions,
            onChanged: (v) => _set(() => entry.injury = v),
          ),
          if (entry.asksInjuryPhotos) ...[
            const SizedBox(height: 10),
            AssessmentDropdown(
              hintText: 'Is the injury visible in your photos?',
              value: entry.injuryVisibleInPhotos,
              options: kInjuryPhotoOptions,
              onChanged: (v) => _set(() => entry.injuryVisibleInPhotos = v),
            ),
          ],
          const SizedBox(height: 10),
        ],
        AssessmentDropdown(
          hintText: 'Body (thin or heavy?)',
          value: entry.bodyCondition,
          options: kBodyConditionOptions,
          onChanged: (v) => _set(() => entry.bodyCondition = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Walking',
          value: entry.mobility,
          options: kMobilityOptions,
          onChanged: (v) => _set(() => entry.mobility = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Awareness (alert or weak?)',
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
          hintText: 'Skin and fur',
          value: entry.skinAndCoat,
          options: kSkinAndCoatOptions,
          onChanged: (v) => _set(() => entry.skinAndCoat = v),
        ),
        const SizedBox(height: 10),
        AssessmentDropdown(
          hintText: 'Eating and drinking',
          value: entry.appetiteHydration,
          options: kAppetiteHydrationOptions,
          onChanged: (v) => _set(() => entry.appetiteHydration = v),
        ),
        if (_signOptions case final signOptions?) ...[
          const SizedBox(height: 12),
          _subLabel(visibleSignsLabelFor(rescueType)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in signOptions)
                RescueToggleChip(
                  label: option,
                  selected: entry.visibleSigns.contains(option),
                  onTap: () => _set(() {
                    final set = entry.visibleSigns;
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
          if (rescueType == kAggressiveAnimalType) ...[
            const SizedBox(height: 10),
            const _BiteSafetyNote(),
          ],
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
            hintText: 'Kapon (spayed or neutered)?',
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
        const SizedBox(height: 16),
        RescueSubsectionHeader(
          'Behavior',
          subtitle: isOwnedPet
              ? 'How your pet usually acts. Select all that apply.'
              : 'Select all that apply.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _behaviorOptions)
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
                    final conflicts = _behaviorConflicts[option] ?? const {};
                    entry.behavior.removeWhere((b) => conflicts.contains(b));
                    for (final other in List.of(entry.behavior)) {
                      if ((_behaviorConflicts[other] ?? const {}).contains(
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
        ] else if (showEnvironmentSafety) ...[
          const SizedBox(height: 16),
          EnvironmentSafetySection(
            entry: entry,
            onChanged: () => _set(() {}),
            extraOptions: environmentExtrasFor(rescueType),
          ),
        ],
        if (_signOptions != null) ...[
          const SizedBox(height: 12),
          _subLabel(medicalQuestionFor(rescueType)),
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

/// Aggressive Animal: keep away from the animal, and first aid for bites
/// and scratches (rabies risk).
class _BiteSafetyNote extends StatelessWidget {
  const _BiteSafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Keep a safe distance and do not try to catch or corner the '
                  'animal. If anyone was bitten or scratched, wash the wound '
                  'right away with soap and running water for at least 15 '
                  'minutes, then go to the nearest Animal Bite Treatment Center '
                  'for rabies care.',
              style: GoogleFonts.zain(
                fontSize: 12.5,
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
