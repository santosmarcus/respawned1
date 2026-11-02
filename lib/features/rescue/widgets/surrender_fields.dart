// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/widgets/found_animal_card.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

// Pet Surrender — its own question set, replacing the generic on-site /
// coordinate-with-shelter / willing-to-adopt questions (none of which
// make sense when the owner is voluntarily surrendering their own pet
// and is already right there with it).
class SurrenderFields extends StatelessWidget {
  const SurrenderFields({
    super.key,
    required this.form,
    required this.onChanged,
  });

  final RescueFormController form;
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
      mainAxisSize: MainAxisSize.min,
      children: [
        // Describe Condition — still relevant (helps staff prep for intake).
        RescueFieldLabel('Describe Condition', required: true),
        const SizedBox(height: 6),
        RescueTextField(form.conditionController, 'Enter condition'),
        const SizedBox(height: 20),

        RescueFieldLabel('Type of Animal', required: true),
        const SizedBox(height: 4),
        Text(
          'Surrendering more than one? Add each animal below — they will '
          'be tracked together as one case.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        FoundAnimalList(animals: form.foundAnimals, onChanged: onChanged),
        const SizedBox(height: 20),

        RescueFieldLabel(
          'How long has the pet been staying with you?',
          required: true,
        ),
        const SizedBox(height: 6),
        RescueTextField(
          form.surrenderDurationController,
          'e.g. 2 years, since it was a puppy',
        ),
        const SizedBox(height: 20),

        RescueFieldLabel('Age of the pet', required: true),
        const SizedBox(height: 6),
        RescueTextField(
          form.surrenderAgeController,
          'e.g. 3 years old, 6 months',
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 20),

        RescueFieldLabel('Why are you surrendering this pet?', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: form.surrenderReason,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Select a reason',
            hintStyle: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary),
            ),
          ),
          items: [
            for (final reason in kSurrenderReasonOptions)
              DropdownMenuItem(
                value: reason,
                child: Text(
                  reason,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: (v) => _set(() => form.surrenderReason = v),
        ),
        if (form.surrenderReason == 'Other (please specify)') ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.surrenderReasonOtherController,
            'Please specify',
          ),
        ],
        const SizedBox(height: 20),

        if (form.surrenderNeedsExplanation) ...[
          RescueFieldLabel(
            form.surrenderReason == 'Behavioral issues'
                ? 'Please explain the behavior and what actions you\'ve taken to try to solve it'
                : 'Please explain the medical issue and what actions you\'ve taken to try to solve it',
            required: true,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: form.surrenderExplanationController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Describe the issue and what you\'ve already tried…',
              hintStyle: GoogleFonts.zain(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: AppColors.textPrimary,
                  width: 1.5,
                ),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 20),
        ],

        RescueFieldLabel('Where did you acquire this pet?', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: form.petAcquisitionSource,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Select source',
            hintStyle: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary),
            ),
          ),
          items: [
            for (final source in kAcquisitionSourceOptions)
              DropdownMenuItem(
                value: source,
                child: Text(
                  source,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: (v) => _set(() => form.petAcquisitionSource = v),
        ),

        if (form.isRescueOrgAcquisition) ...[
          const SizedBox(height: 12),
          Container(
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
                    'Please contact the previous organization and inquire to them about return pets.',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
