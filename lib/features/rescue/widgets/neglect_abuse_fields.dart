import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Shared helpers for the two Neglect or Abuse sections.
abstract class _NeglectSection extends StatelessWidget {
  const _NeglectSection({
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

  Widget _heading(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: GoogleFonts.tiltWarp(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: AppColors.slaterspwn),
      ],
    );
  }

  Widget _hint(String text) {
    return Text(
      text,
      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

/// Top of the Neglect or Abuse form, before Describe Condition: the
/// guidance note, then "What are you seeing?".
///
/// The guidance follows PAWS (Philippine Animal Welfare Society): cruelty
/// is a crime under RA 8485 as amended by RA 10631, it must be reported to
/// barangay officials or the police (911) rather than only posted online,
/// and a case is built on evidence — the animal itself, photos and videos,
/// witnesses, a blotter and a veterinarian's affidavit.
class NeglectAbuseIntro extends _NeglectSection {
  const NeglectAbuseIntro({
    super.key,
    required super.form,
    required super.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final observed = form.neglectObserved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _GuidanceBox(),
        const SizedBox(height: 20),

        RescueFieldLabel('What are you seeing?', required: true),
        const SizedBox(height: 4),
        _hint('Select all that apply.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kNeglectObservedOptions)
              RescueToggleChip(
                label: option,
                selected: observed.contains(option),
                onTap: () => _set(() {
                  if (!observed.remove(option)) observed.add(option);
                }),
              ),
          ],
        ),
        if (observed.contains(kNeglectObservedOther)) ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.neglectObservedOtherController,
            'Please describe what you are seeing',
          ),
        ],
      ],
    );
  }
}

/// The rest of the Neglect or Abuse questions, after the animal cards:
/// whether it is happening now, the owner, how often, whether authorities
/// were told, and whether the reporter would stand as a witness.
class NeglectAbuseFields extends _NeglectSection {
  const NeglectAbuseFields({
    super.key,
    required super.form,
    required super.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading('Neglect or Abuse Details'),
        const SizedBox(height: 14),

        RescueFieldLabel('Is the harm happening right now?', required: true),
        const SizedBox(height: 4),
        _radios(
          kYesNoOptions,
          form.neglectHappeningNow,
              (v) => form.neglectHappeningNow = v,
        ),
        if (form.neglectHappeningNow == 'Yes') ...[
          const SizedBox(height: 10),
          const _UrgentBanner(),
        ],
        const SizedBox(height: 20),

        RescueFieldLabel(
          'Does the animal have an owner you know of?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kYesNoNotSureOptions,
          form.neglectOwnerKnown,
              (v) => form.neglectOwnerKnown = v,
        ),
        if (form.neglectOwnerKnown == 'Yes') ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.neglectOwnerDetailsController,
            "Owner's name or address (optional)",
          ),
        ],
        const SizedBox(height: 20),

        RescueFieldLabel(
          'How long or how often have you seen this?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kNeglectFrequencyOptions,
          form.neglectFrequency,
              (v) => form.neglectFrequency = v,
        ),
        const SizedBox(height: 28),

        _heading('Reporting to Authorities'),
        const SizedBox(height: 14),

        RescueFieldLabel(
          'Have you reported this to your barangay or the police?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kYesNoOptions,
          form.neglectReportedToAuthorities,
              (v) => form.neglectReportedToAuthorities = v,
        ),
        if (form.neglectReportedToAuthorities == 'Yes') ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.neglectReportReferenceController,
            'Blotter or report reference number (optional)',
          ),
        ],
        if (form.neglectReportedToAuthorities == 'No') ...[
          const SizedBox(height: 6),
          _hint(
            'Please report it to your barangay officials or the police as '
                'soon as you can. A barangay blotter or police report is needed '
                'before a case can be filed, and we can guide you through it.',
          ),
        ],
        const SizedBox(height: 20),

        RescueFieldLabel(
          'If a case is filed, are you willing to give a sworn statement '
              '(affidavit) as a witness?',
          required: true,
        ),
        const SizedBox(height: 4),
        _radios(
          kYesNoOptions,
          form.neglectWillingWitness,
              (v) => form.neglectWillingWitness = v,
        ),
        const SizedBox(height: 4),
        _hint(
          'Cruelty cases rely on witnesses who are willing to execute an '
              'affidavit and appear in court. Your identity can still be kept '
              'confidential from the alleged owner (see the option below).',
        ),
      ],
    );
  }
}

/// Shown when the cruelty is happening right now.
class _UrgentBanner extends StatelessWidget {
  const _UrgentBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_phone, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Call your barangay officials or the police at 911 now. An '
                  'act of cruelty in progress should be stopped by the '
                  'authorities immediately. Do not confront the person '
                  'yourself or put yourself in danger.',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What to do, what evidence to gather, and what the organization can and
/// cannot do. Based on PAWS's published guidance on reporting cruelty.
class _GuidanceBox extends StatelessWidget {
  const _GuidanceBox();

  @override
  Widget build(BuildContext context) {
    TextStyle body([FontWeight w = FontWeight.w400]) => GoogleFonts.zain(
      fontSize: 12.5,
      fontWeight: w,
      color: AppColors.textPrimary,
    );

    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: body()),
          Expanded(child: Text(text, style: body())),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.gavel_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Please read before you continue',
                style: body(FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Animal cruelty and neglect are crimes under the Animal Welfare '
                'Act (Republic Act No. 8485, as amended by Republic Act No. '
                '10631). Please report this to your barangay officials or the '
                'police (911) as soon as possible. Posting about it on social '
                'media alone is not a report and does not stop the abuse.',
            style: body(),
          ),
          const SizedBox(height: 10),
          Text(
            'Gather as much evidence as you safely can:',
            style: body(FontWeight.w700),
          ),
          bullet(
            'Clear photos and videos of the animal, its injuries and '
                'surroundings, and the location. The animal itself is the '
                'strongest evidence.',
          ),
          bullet('The date, time and exact address of each incident.'),
          bullet(
            'Names and contact details of other witnesses who saw what '
                'happened.',
          ),
          bullet(
            'A copy of the barangay blotter or police report, and a '
                "veterinarian's findings on the animal if available.",
          ),
          const SizedBox(height: 10),
          Text(
            'What organizations can and cannot do',
            style: body(FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'Animal welfare organizations are private groups. They cannot '
                'legally confiscate an animal from its owner or file a criminal '
                'case on your behalf; only law enforcement and the courts can '
                'act on a cruelty complaint. What we can do is help you report '
                'the case to the proper authorities, guide you in preparing '
                'your evidence and affidavits, and assist with the animal\'s '
                'rescue and veterinary care once it is safe and lawful to do so.',
            style: body(),
          ),
          const SizedBox(height: 10),
          Text(
            'Never confront the suspected abuser or enter private property. '
                'Your safety comes first.',
            style: body(FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
