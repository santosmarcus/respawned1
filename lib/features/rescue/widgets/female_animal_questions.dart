import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/litter_details_fields.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Litter and suspected-pregnancy questions. Shown only while the animal's
/// sex is Female; [FoundAnimalEntry.sex] clears both answers when the sex
/// changes, so nothing stale is saved.
class FemaleAnimalQuestions extends StatelessWidget {
  const FemaleAnimalQuestions({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final FoundAnimalEntry entry;
  final VoidCallback onChanged;

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
          'Female animal',
          style: GoogleFonts.zain(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        AssessmentDropdown(
          hintText: 'Does she currently have a litter?',
          value: entry.hasLitter,
          options: kLitterOptions,
          onChanged: (v) => _set(() => entry.hasLitter = v),
        ),
        // Female dog with a litter: count, places, condition. Not for cats,
        // and not for a suspected pregnancy without a litter.
        if (entry.asksLitterDetails) LitterDetailsFields(entry: entry, onChanged: onChanged),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AssessmentDropdown(
                hintText: 'Is she suspected to be pregnant?',
                value: entry.suspectedPregnancy,
                options: kSuspectedPregnancyOptions,
                onChanged: (v) => _set(() => entry.suspectedPregnancy = v),
              ),
            ),
            IconButton(
              tooltip: 'Signs of pregnancy',
              icon: const Icon(Icons.info_outline, color: AppColors.textPrimary),
              onPressed: () => showPregnancySignsSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Your answer is recorded as an observation only. A pregnancy is '
          'confirmed only by a veterinarian.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Educational panel: possible signs of pregnancy in dogs and cats.
Future<void> showPregnancySignsSheet(BuildContext context) {
  Widget section(String title, List<String> items) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.zain(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            'Possible signs of pregnancy',
            style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'These signs can suggest a dog or cat may be pregnant. Several '
            'appear only in the second half of pregnancy, and some can also '
            'come from illness, weight gain or a false pregnancy.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          section('Physical changes', const [
            'A rounder, enlarged belly that keeps growing over weeks.',
            'Enlarged, pinker or more visible nipples and mammary glands.',
            'Weight gain without other explanation.',
            'Late in pregnancy, milk or clear discharge from the nipples.',
          ]),
          section('Behavior changes', const [
            'Nesting: gathering cloth, paper or bedding, or seeking a hidden, quiet spot.',
            'More affectionate and clingy, or more withdrawn than usual.',
            'Restlessness, panting or pacing, especially close to giving birth.',
            'Changes in appetite: eating less early on, or much more later.',
          ]),
          section('Other observations', const [
            'Tiring easily or sleeping more.',
            'Moving more slowly or carefully.',
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.medical_services_outlined, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'None of these signs is definitive. Only a veterinary '
                    'examination (for example palpation, ultrasound or an '
                    'X-ray) can confirm a pregnancy. Your report is saved as a '
                    'suspected pregnancy, not a confirmed one.',
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
      ),
    ),
  );
}
