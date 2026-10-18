// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/widgets/found_animal_card.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/core/utils/validators.dart';

/// Details for every rescue type other than Pet Surrender and Lost Pet:
/// urgency, condition, animals, on-site/access, shelter coordination,
/// witnesses, adoption interest and anonymity.
class StrayReportFields extends StatelessWidget {
  const StrayReportFields({
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
        if (form.selectedRescueType != null) ...[
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: urgencyColorFor(form.selectedUrgency),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Urgency level: ${form.selectedUrgency ?? 'N/A'}',
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Set automatically based on the rescue type you chose.',
            style: GoogleFonts.zain(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
        ],
        // Describe Condition
        RescueFieldLabel('Describe Condition', required: true),
        const SizedBox(height: 6),
        TextField(
          controller: form.conditionController,
          decoration: InputDecoration(
            hintText: 'Enter condition',
            hintStyle: GoogleFonts.zain(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8),
          ),
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),

        const SizedBox(height: 20),

        RescueFieldLabel('Type of Animal', required: true),
        const SizedBox(height: 4),
        Text(
          'Found more than one? Add each animal below — they will '
          'be tracked together as one case.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        FoundAnimalList(animals: form.foundAnimals, onChanged: onChanged),

        const SizedBox(height: 20),

        // On-site presence
        RescueFieldLabel(
          'Are you currently on-site with the animal?',
          required: true,
        ),
        const SizedBox(height: 8),
        RescueRadioOption(
          'Yes, I am on-site',
          form.onSiteChoice,
          (val) => _set(() => form.onSiteChoice = val),
        ),
        RescueRadioOption(
          'No, I am reporting remotely',
          form.onSiteChoice,
          (val) => _set(() => form.onSiteChoice = val),
        ),

        const SizedBox(height: 20),

        // Access instructions
        RescueFieldLabel('Access instructions', required: false),
        const SizedBox(height: 6),
        RescueTextField(
          form.accessInstructionsController,
          'e.g. Gated compound, ask guard for entry',
        ),

        const SizedBox(height: 20),

        // Coordinate with shelter
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Would you be willing to coordinate with the shelter to assist in the rescue?',
                style: GoogleFonts.zain(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: form.coordinateChoice == 'yes',
                onChanged: (val) => _set(() => form.coordinateChoice = 'yes'),
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
            Text(
              'Yes, I would.',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: form.coordinateChoice == 'no',
                onChanged: (val) => _set(() => form.coordinateChoice = 'no'),
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
                'No, but I can refer you to witnesses who can assist.',
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (form.coordinateChoice == 'no') ...[
          const SizedBox(height: 6),
          RescueFieldLabel('Witness name', required: true),
          const SizedBox(height: 6),
          TextField(
            controller: form.witnessNameController,
            inputFormatters: [AppInputFormatters.nameOnly],
            decoration: InputDecoration(
              hintText: 'Enter name of witness',
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
          const SizedBox(height: 12),
          RescueFieldLabel('Witness mobile number', required: true),
          const SizedBox(height: 6),
          TextField(
            controller: form.witnessNumberController,
            keyboardType: TextInputType.phone,
            inputFormatters: AppInputFormatters.phoneFlexible,
            decoration: InputDecoration(
              hintText: 'Enter mobile number of witness',
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
        ],
        const SizedBox(height: 20),

        if (form.coordinateChoice == 'yes') ...[
          // Best time to contact
          RescueFieldLabel('Best time to reach you', required: false),
          const SizedBox(height: 6),
          RescueTextField(
            form.bestTimeContactController,
            'e.g. Anytime after 3PM',
          ),

          const SizedBox(height: 20),
        ],

        // Willing to adopt
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Would you like to adopt the animal once rescued?',
                style: GoogleFonts.zain(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: form.adoptionChoice == 'yes',
                onChanged: (val) => _set(() => form.adoptionChoice = 'yes'),
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
            Text(
              'Yes, I would.',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: form.adoptionChoice == 'no',
                onChanged: (val) => _set(() {
                  form.adoptionChoice = 'no';
                  form.adoptionCommitmentAccepted = false;
                }),
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
            Text(
              'No.',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),

        // Only shown once the reporter has expressed interest in
        // adopting — a plain "yes I'd like to adopt" isn't
        // enough on its own; this makes the actual obligations
        // explicit (cost, interview, agreement, follow-ups)
        // before staff treat them as a real candidate at
        // discharge. Separate from (and not automatic approval
        // for) the removed Community Adoption Details path.
        if (form.adoptionChoice == 'yes') ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'By agreeing to this, you confirm that you are '
                  'willing to cover any necessary veterinary '
                  'expenses, participate in the adoption interview '
                  'process, comply with the adoption agreement, and '
                  'provide post-adoption updates as required.',
                  style: GoogleFonts.zain(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Once the animal is in treatment, the organization will '
            'visit you at the veterinary clinic to discuss the '
            'adoption process with you.',
            style: GoogleFonts.zain(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _set(
              () => form.adoptionCommitmentAccepted =
                  !form.adoptionCommitmentAccepted,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: form.adoptionCommitmentAccepted,
                    onChanged: (val) => _set(
                      () => form.adoptionCommitmentAccepted = val ?? false,
                    ),
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
                    'I agree.',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (form.selectedRescueType == 'Neglect or Abuse') ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Keep my identity confidential from the alleged owner',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: form.reportAnonymously,
                activeColor: AppColors.textPrimary,
                onChanged: (v) => _set(() => form.reportAnonymously = v),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
