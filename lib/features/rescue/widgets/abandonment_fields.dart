import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Follow-up questions for the Abandonment rescue type: how long and where
/// the animal was left, whether it has food and water, who left it, and
/// whether anything was left with it. Staff use these to judge how soon
/// the animal needs a response.
class AbandonmentFields extends StatelessWidget {
  const AbandonmentFields({
    super.key,
    required this.form,
    required this.onChanged,
  });

  final RescueFormController form;
  final VoidCallback onChanged;

  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  Widget _radios(
      List<String> options,
      String? selected,
      ValueChanged<String> onSelect,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in options)
          RescueRadioOption(option, selected, (v) => _set(() => onSelect(v))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Abandonment Details',
          style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: AppColors.slaterspwn),
        const SizedBox(height: 14),

        RescueFieldLabel(
          'How long has the animal been at this location?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kAbandonmentDurationOptions,
          form.abandonmentDuration,
              (v) => form.abandonmentDuration = v,
        ),
        const SizedBox(height: 20),

        RescueFieldLabel('Where was the animal left?', required: true),
        const SizedBox(height: 4),
        _radios(
          kAbandonmentLocationOptions,
          form.abandonmentLocation,
              (v) => form.abandonmentLocation = v,
        ),
        if (form.abandonmentLocation == kAbandonmentLocationOther) ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.abandonmentLocationOtherController,
            'Please specify where the animal was left',
          ),
        ],
        const SizedBox(height: 20),

        RescueFieldLabel(
          'Does the animal have access to food and water?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kAbandonmentFoodWaterOptions,
          form.abandonmentFoodWater,
              (v) {
            form.abandonmentFoodWater = v;
            if (!form.asksAbandonmentCanProvideFood) {
              form.abandonmentCanProvideFood = null;
            }
          },
        ),
        if (form.asksAbandonmentCanProvideFood) ...[
          const SizedBox(height: 20),
          RescueFieldLabel(
            'Can you safely provide food and water while waiting for help?',
            required: true,
          ),
          const SizedBox(height: 4),
          _radios(
            kYesNoOptions,
            form.abandonmentCanProvideFood,
                (v) => form.abandonmentCanProvideFood = v,
          ),
          if (form.abandonmentCanProvideFood == 'No') ...[
            const SizedBox(height: 8),
            Text(
              'That\'s okay. Please do not enter a locked property or put '
                  'yourself at risk. Our team will take this into account.',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),

        RescueFieldLabel('Did you see who left the animal?', required: true),
        const SizedBox(height: 4),
        _radios(
          kAbandonmentWitnessOptions,
          form.abandonmentWitness,
              (v) => form.abandonmentWitness = v,
        ),
        const SizedBox(height: 6),
        RescueTextField(
          form.abandonmentWitnessDetailsController,
          'Details, e.g. vehicle, time, description (optional)',
        ),
        const SizedBox(height: 20),

        RescueFieldLabel(
          'Were any belongings left with the animal (collar, food, a note)?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kYesNoOptions,
          form.abandonmentBelongings,
              (v) => form.abandonmentBelongings = v,
        ),
        if (form.abandonmentBelongings == 'Yes') ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.abandonmentBelongingsDetailsController,
            'Describe what was left (optional)',
          ),
        ],
      ],
    );
  }
}
