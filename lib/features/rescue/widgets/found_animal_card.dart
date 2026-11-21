// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/female_animal_questions.dart';
import 'package:respawnd1/features/rescue/widgets/health_behavior_assessment.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/features/rescue/widgets/risk_fields_row.dart';

/// The list of per-animal cards plus the "Add another animal" button —
/// shared by the stray, surrender and finder sections.
class FoundAnimalList extends StatelessWidget {
  const FoundAnimalList({
    super.key,
    required this.animals,
    required this.onChanged,
    this.isSurrender = false,
    this.rescueType,
  });

  /// The form's live list; cards are added/removed in place.
  final List<FoundAnimalEntry> animals;
  final VoidCallback onChanged;

  /// Passed to each card; true shows the Pet Surrender questions.
  final bool isSurrender;

  /// Passed down to the Health & Behavior Assessment.
  final String? rescueType;

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
        for (int i = 0; i < animals.length; i++)
          FoundAnimalCard(
            entry: animals[i],
            index: i,
            canRemove: animals.length > 1,
            onRemove: () {
              animals[i].dispose();
              _set(() => animals.removeAt(i));
            },
            onChanged: onChanged,
            isSurrender: isSurrender,
            rescueType: rescueType,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            // Collapse the cards already filled so the new one is in view.
            onPressed: () => _set(() {
              for (final a in animals) {
                a.expanded = false;
              }
              animals.add(FoundAnimalEntry());
            }),
            icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
            label: Text(
              'Add another animal',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }
}

/// One animal's card: species/breed/sex/size/color, the Health & Behavior
/// Assessment, and the risk fields.
class FoundAnimalCard extends StatelessWidget {
  const FoundAnimalCard({
    super.key,
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    this.isSurrender = false,
    this.rescueType,
  });

  final FoundAnimalEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final bool isSurrender;

  /// Passed down to the Health & Behavior Assessment.
  final String? rescueType;

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: entry.cardKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F5),
        border: Border.all(
          color: entry.hasAssessmentError
              ? AppColors.error
              : kRescueFieldBorder,
          width: entry.hasAssessmentError ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The header opens and closes every card, a single animal's too.
          // The answers live on the entry, so closing a card never resets
          // them; a failed submit reopens the card with the error.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _set(() => entry.expanded = !entry.expanded),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Animal ${index + 1}',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Required',
                            style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (!entry.expanded && _summary.isNotEmpty)
                        Text(
                          _summary,
                          style: GoogleFonts.zain(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  entry.expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textPrimary,
                  semanticLabel: entry.expanded
                      ? 'Collapse animal ${index + 1}'
                      : 'Expand animal ${index + 1}',
                ),
                if (canRemove) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Remove this animal',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entry.expanded) ..._body(),
          if (!entry.expanded && entry.hasAssessmentError) ...[
            const SizedBox(height: 6),
            Text(
              'Incomplete — tap to finish this animal.',
              style: GoogleFonts.zain(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Dog · Aspin · Male", shown on a collapsed card's header.
  String get _summary => [
    entry.species,
    entry.breedText,
    entry.sex,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  List<Widget> _body() {
    return [
      const SizedBox(height: 10),
      const RescueSubsectionHeader('Basic details'),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SpeciesDropdown(
              value: entry.species,
              onChanged: (v) => _set(() {
                entry.species = v;
                entry.breed = null;
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BreedDropdown(
              species: entry.species,
              breedValue: entry.breed,
              onChanged: (v) => _set(() => entry.breed = v),
              otherController: entry.breedOtherController,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey(entry.sex),
              initialValue: entry.sex,
              isDense: true,
              // Fit the column it's in (its widest option otherwise sets its
              // width and overflows half-width rows on small phones).
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Sex',
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Unsure', child: Text('Unsure')),
              ],
              // The setter clears the litter/pregnancy answers when the
              // animal is no longer Female.
              onChanged: (v) => _set(() => entry.sex = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey(entry.size),
              initialValue: entry.size,
              isDense: true,
              // Fit the column it's in (its widest option otherwise sets its
              // width and overflows half-width rows on small phones).
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Size',
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Small', child: Text('Small')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Large', child: Text('Large')),
              ],
              onChanged: (v) => _set(() => entry.size = v),
            ),
          ),
        ],
      ),
      if (isSurrender) ...[
        const SizedBox(height: 10),
        RescueTextField(
          entry.ageController,
          'Age (e.g. 3 years old, 6 months)',
        ),
      ],
      const SizedBox(height: 10),
      RescueTextField(entry.colorController, 'Color / Distinguishing markings'),
      if (sexAllowsPregnancyQuestions(entry.sex)) ...[
        const SizedBox(height: 14),
        FemaleAnimalQuestions(entry: entry, onChanged: onChanged),
      ],
      if (entry.hasAssessmentError) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.error_outline, size: 14, color: AppColors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isSurrender
                    ? 'Complete all details for this animal.'
                    : 'Complete the Health & Behavior Assessment for this animal.',
                style: GoogleFonts.zain(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      const Divider(height: 1, color: kRescueFieldBorder),
      const SizedBox(height: 14),
      HealthBehaviorAssessment(
        entry: entry,
        onChanged: onChanged,
        isSurrender: isSurrender,
        rescueType: rescueType,
      ),
      const SizedBox(height: 16),
      const RescueSubsectionHeader(
        'Risk assessment',
        subtitle: 'Choose Unknown if you could not tell — it is never assumed Low.',
      ),
      const SizedBox(height: 8),
      RiskFieldsRow(entry: entry, onChanged: onChanged),
    ];
  }
}
