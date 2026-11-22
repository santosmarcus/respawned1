import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// A female dog's litter: how many puppies, where they are, how they look,
/// and how many need their own rescue report. Shown only when
/// [FoundAnimalEntry.asksLitterDetails] (Dog, Female, has a litter: Yes);
/// the answers live on the entry, so collapsing the card or moving between
/// sections keeps them.
class LitterDetailsFields extends StatelessWidget {
  const LitterDetailsFields({super.key, required this.entry, required this.onChanged});

  final FoundAnimalEntry entry;
  final VoidCallback onChanged;

  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  Future<void> _addPhotos() async {
    final remaining = kMaxLitterPhotos - entry.litterPhotos.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = remaining == 1
        ? [?await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280)]
        : await picker.pickMultiImage(imageQuality: 80, maxWidth: 1280, limit: remaining);
    if (picked.isEmpty) return;
    _set(() => entry.litterPhotos.addAll(picked.take(remaining)));
  }

  @override
  Widget build(BuildContext context) {
    final split = litterLocationIsSplit(entry.litterLocation);
    final small = GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Her litter',
            style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        RescueFieldLabel('How many puppies are in the litter?', required: true),
        const SizedBox(height: 4),
        RescueTextField(
          entry.litterCountController,
          'Your best estimate, e.g. 4',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        ),
        const SizedBox(height: 12),
        RescueFieldLabel('Where are the puppies?', required: true),
        for (final option in kLitterLocationOptions)
          RescueRadioOption(option, entry.litterLocation, (v) => _set(() {
                entry.litterLocation = v;
                // Two places to fill in to start with; more can be added.
                if (litterLocationIsSplit(v) && entry.litterGroupControllers.isEmpty) {
                  entry.litterGroupControllers.addAll([TextEditingController(), TextEditingController()]);
                }
              })),
        if (split) ...[
          const SizedBox(height: 4),
          Text('Where is each group you know of? (optional)', style: small),
          for (var i = 0; i < entry.litterGroupControllers.length; i++)
            Row(
              children: [
                Expanded(
                  child: RescueTextField(entry.litterGroupControllers[i], 'Group ${i + 1}: e.g. under the stairs, 2 puppies'),
                ),
                if (entry.litterGroupControllers.length > 1)
                  IconButton(
                    tooltip: 'Remove group ${i + 1}',
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                    onPressed: () => _set(() => entry.litterGroupControllers.removeAt(i).dispose()),
                  ),
              ],
            ),
          if (entry.litterGroupControllers.length < kMaxLitterGroups)
            TextButton.icon(
              onPressed: () => _set(() => entry.litterGroupControllers.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
              label: Text('Add another place', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
            ),
        ],
        const SizedBox(height: 12),
        RescueFieldLabel('How do the puppies look?', required: true),
        for (final option in kLitterConditionOptions)
          RescueRadioOption(option, entry.litterCondition, (v) => _set(() => entry.litterCondition = v)),
        if (entry.litterNeedsAttention) ...[
          const SizedBox(height: 8),
          RescueFieldLabel('How many puppies need medical attention?', required: true),
          const SizedBox(height: 4),
          RescueTextField(
            entry.puppiesNeedingAttentionController,
            'e.g. 1',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          ),
          const SizedBox(height: 4),
          Text(
            'After you submit, you can report these puppies in a separate rescue report, '
            'so each one is assessed on its own. It stays linked to this report.',
            style: small,
          ),
        ],
        const SizedBox(height: 12),
        RescueFieldLabel('Other observations (optional)', required: false),
        const SizedBox(height: 4),
        RescueTextField(entry.litterNotesController, 'e.g. eyes still closed, mother nursing them'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < entry.litterPhotos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(entry.litterPhotos[i].path), width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => _set(() => entry.litterPhotos.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (entry.litterPhotos.length < kMaxLitterPhotos)
              OutlinedButton.icon(
                onPressed: _addPhotos,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18, color: AppColors.textPrimary),
                label: Text('Litter photos (optional)', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
              ),
          ],
        ),
        // Shown once a submit found this card incomplete.
        if (entry.hasAssessmentError && entry.litterError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(entry.litterError!, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
          ),
      ],
    );
  }
}
