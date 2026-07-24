import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/widgets/animal_basic_info_row.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';

const String _kNA = 'Not provided';

class AnimalProfileTab extends StatelessWidget {
  final AnimalRecord animal;
  const AnimalProfileTab({super.key, required this.animal});

  String _orNA(String v) => v.isEmpty ? _kNA : v;

  @override
  Widget build(BuildContext context) {
    final temperament = animal.keyCharacteristics.where(kTemperamentValues.contains).toList();
    final compatibility = animal.keyCharacteristics.where(kCompatibilityValues.contains).toList();
    final training = animal.keyCharacteristics.where(kTrainingValues.contains).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Species/Age/Size, Breed/Coat Length/Color-Markings — the same
          // six-field structure and order the user-side detail page
          // (animal_page.dart) uses, so both surfaces read identically. Sex
          // is deliberately not a field here — it's already represented as
          // the gender icon beside the name above, and repeating it as text
          // would be a duplicate gender row.
          AnimalBasicInfoRow(fields: [
            InfoField('Species', _orNA(animal.species)),
            InfoField('Age', _orNA(animal.age)),
            InfoField('Size', _orNA(animal.size)),
            InfoField('Breed', _orNA(animal.breed)),
            InfoField('Coat Length', _orNA(animal.coatLength)),
            // No dedicated color/markings field yet — that text is folded
            // into Description at intake time (see
            // create_animal_record_page.dart's _prefill), so this is
            // honestly "not provided" as its own field rather than
            // guessed out of free text.
            const InfoField('Color / Markings', _kNA),
          ]),

          const SizedBox(height: 12),
          _SectionLabel('Temperament'),
          const SizedBox(height: 6),
          _ChipsOrNA(items: temperament),

          const SizedBox(height: 16),
          _SectionLabel('Compatibility'),
          const SizedBox(height: 6),
          _ChipsOrNA(items: compatibility),

          const SizedBox(height: 16),
          _SectionLabel('Training'),
          const SizedBox(height: 6),
          _ChipsOrNA(items: training),

          const SizedBox(height: 16),
          _SectionLabel('Rescue Background'),
          const SizedBox(height: 6),
          _ChipsOrNA(items: animal.rescueBackground),

          const SizedBox(height: 16),
          _SectionLabel('Description'),
          const SizedBox(height: 6),
          Text(_orNA(animal.description), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary, height: 1.4)),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _InfoItem('Rescued By', _orNA(animal.rescuedBy))),
              Expanded(child: _InfoItem('Adoptable', animal.isAdoptable ? 'Yes' : 'No')),
            ],
          ),
          if (animal.isReserved || animal.isAdopted)
            _InfoItem(
              animal.isAdopted ? 'Adopted' : 'Reserved',
              animal.isAdopted
                  ? (animal.adoptedAt != null ? '${animal.adoptedAt!.month}/${animal.adoptedAt!.day}/${animal.adoptedAt!.year}' : 'Yes')
                  : 'Reserved · application #${animal.reservedApplicationId?.substring(0, 6) ?? ''}',
            ),

          if (animal.hasSourceCase) ...[
            const SizedBox(height: 8),
            _SectionLabel('Source Rescue Case'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RescueDetailPage(caseId: animal.linkedCaseId, data: const {})),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: AppColors.textPrimary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('#${shortCaseId(animal.linkedCaseId)} — view rescue record',
                          style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          _SectionLabel('Tags'),
          const SizedBox(height: 6),
          _ChipsOrNA(items: animal.tags),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdoptionApplicationReviewPage(
                        animalId: animal.id,
                        animalName: animal.name.isNotEmpty ? animal.name : animal.species,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('View Applications', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('View Donations', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) =>
      Text(label, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary));
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _ChipsOrNA extends StatelessWidget {
  final List<String> items;
  const _ChipsOrNA({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(_kNA, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .map((label) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ))
          .toList(),
    );
  }
}
