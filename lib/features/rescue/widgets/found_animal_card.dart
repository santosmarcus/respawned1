// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
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
  });

  /// The form's live list; cards are added/removed in place.
  final List<FoundAnimalEntry> animals;
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
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _set(() => animals.add(FoundAnimalEntry())),
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
  });

  final FoundAnimalEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: entry.hasAssessmentError
              ? const Color(0xFFE05353)
              : AppColors.slaterspwn,
          width: entry.hasAssessmentError ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Animal ${index + 1}',
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (canRemove)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                  value: entry.sex,
                  isDense: true,
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
                  onChanged: (v) => _set(() => entry.sex = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: entry.size,
                  isDense: true,
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
          const SizedBox(height: 10),
          RescueTextField(
            entry.colorController,
            'Color / Distinguishing markings',
          ),
          if (entry.hasAssessmentError) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 14,
                  color: Color(0xFFE05353),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Complete the Health & Behavior Assessment for this animal.',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE05353),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          HealthBehaviorAssessment(entry: entry, onChanged: onChanged),
          const SizedBox(height: 14),
          Text(
            'Risk Assessment',
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          RiskFieldsRow(entry: entry, onChanged: onChanged),
        ],
      ),
    );
  }
}
