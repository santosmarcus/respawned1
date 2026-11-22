// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/abandonment_fields.dart';
import 'package:respawnd1/features/rescue/widgets/found_animal_card.dart';
import 'package:respawnd1/features/rescue/widgets/neglect_abuse_fields.dart';
import 'package:respawnd1/features/rescue/widgets/neglect_abuse_path_section.dart';
import 'package:respawnd1/features/rescue/widgets/urgency_assessment_card.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/core/utils/validators.dart';

/// Details for every rescue type other than Pet Surrender and Lost Pet:
/// Neglect or Abuse's coverage-based guidance, condition, animals with the live
/// urgency assessment, on-site/access, and (when the organization is asked
/// to act) shelter coordination, witnesses and adoption interest, then
/// anonymity.
class StrayReportFields extends StatelessWidget {
  const StrayReportFields({
    super.key,
    required this.form,
    required this.onChanged,
    this.hasPin = true,
  });

  final RescueFormController form;
  final VoidCallback onChanged;

  /// Whether the location step has a resolved pin (Neglect or Abuse checks
  /// partner coverage there).
  final bool hasPin;

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
        // Neglect or Abuse opens with its guidance note and "What are you
        // seeing?" before the condition and the animals, then the choice
        // between asking the organization for help and reporting it
        // yourself with the guide.
        if (form.isNeglectAbuseType) ...[
          // Where the animal is decides the path: the guidelines first when
          // no partner organization covers it, the rescue form when one does.
          NeglectAbuseCoverageSection(form: form, hasPin: hasPin),
          const SizedBox(height: 20),
          NeglectAbuseIntro(form: form, onChanged: onChanged),
          const SizedBox(height: 20),
        ],

        // Describe Condition
        RescueFieldLabel(form.isNeglectAbuseType ? 'Describe what you saw' : 'Describe Condition', required: true),
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
        FoundAnimalList(
          animals: form.foundAnimals,
          onChanged: onChanged,
          rescueType: form.selectedRescueType,
        ),

        // Urgency is assessed from the answers above, never picked by hand.
        if (form.urgencyAssessment case final assessment?) ...[
          const SizedBox(height: 8),
          UrgencyAssessmentCard(assessment: assessment, isEstimate: true),
        ],

        const SizedBox(height: 20),

        if (form.isNeglectAbuseType) ...[
          NeglectAbuseFields(form: form, onChanged: onChanged),
          const SizedBox(height: 20),
        ],

        if (form.isAbandonmentType) ...[
          AbandonmentFields(form: form, onChanged: onChanged),
          const SizedBox(height: 20),
        ],

        // On-site presence (Neglect or Abuse asks "happening right now?").
        if (form.asksOnSite) ...[
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
        ],

        // Access instructions
        RescueFieldLabel('Access instructions', required: false),
        const SizedBox(height: 6),
        RescueTextField(
          form.accessInstructionsController,
          'e.g. Gated compound, ask guard for entry',
        ),

        const SizedBox(height: 20),

        // Organization coordination, witnesses and adoption interest only
        // apply when the reporter asks the organization to act.
        if (form.asksOrgCoordination) ...[
        // Coordinate with shelter — one answer only, so radio tiles.
        RescueFieldLabel(
          'Would you be willing to coordinate with the shelter to assist in the rescue?',
          required: true,
        ),
        const SizedBox(height: 8),
        RescueRadioOption(
          'Yes, I would.',
          form.coordinateChoice,
          (v) => _set(() => form.coordinateChoice = v),
          value: 'yes',
        ),
        RescueRadioOption(
          'No, but I can refer you to witnesses who can assist.',
          form.coordinateChoice,
          (v) => _set(() => form.coordinateChoice = v),
          value: 'no',
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

        // Willing to adopt — one answer only, so radio tiles.
        RescueFieldLabel(
          'Would you like to adopt the animal once rescued?',
          required: true,
        ),
        const SizedBox(height: 8),
        RescueRadioOption(
          'Yes, I would.',
          form.adoptionChoice,
          (v) => _set(() => form.adoptionChoice = v),
          value: 'yes',
        ),
        RescueRadioOption(
          'No.',
          form.adoptionChoice,
          (v) => _set(() {
            form.adoptionChoice = v;
            form.adoptionCommitmentAccepted = false;
          }),
          value: 'no',
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
                  color: AppColors.error,
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

        ],

        if (form.isNeglectAbuseType) ...[
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
                activeThumbColor: AppColors.textPrimary,
                onChanged: (v) => _set(() => form.reportAnonymously = v),
              ),
            ],
          ),
        ],

        // Analytics gap 5: community (outdoor, unowned) cats.
        if (form.asksCommunityCat) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'This cat lives outdoors in the community, with no owner',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: form.communityCat,
                activeThumbColor: AppColors.textPrimary,
                onChanged: (v) => _set(() => form.communityCat = v),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
