// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/widgets/found_animal_card.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

// Pet Surrender — its own question set, replacing the generic on-site /
// coordinate-with-shelter / willing-to-adopt questions (none of which
// make sense when the owner is voluntarily surrendering their own pet
// and is already right there with it). The Environment and Safety
// section is hidden for the same reason.
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

  Future<void> _addVetRecords() async {
    final remaining = kMaxVetRecordPhotos - form.vetRecordPhotos.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    // pickMultiImage only accepts a limit of 2 or more.
    final picked = remaining == 1
    ? [?await picker.pickImage(source: ImageSource.gallery, imageQuality: 80)]
        : await picker.pickMultiImage(imageQuality: 80, limit: remaining);
    if (picked.isEmpty) return;
    _set(() => form.vetRecordPhotos.addAll(picked.take(remaining)));
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
        FoundAnimalList(
          animals: form.foundAnimals,
          onChanged: onChanged,
          isSurrender: true,
        ),
        const SizedBox(height: 20),

        // ---- Health records ------------------------------------------------
        const _SectionTitle('Health Records'),
        const SizedBox(height: 14),

        RescueFieldLabel('Vaccination card or vet records (optional)'),
        const SizedBox(height: 4),
        Text(
          'Upload up to $kMaxVetRecordPhotos photos. Records help our '
              'veterinary team avoid repeat vaccinations and continue any '
              'ongoing treatment.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < form.vetRecordPhotos.length; i++)
              _VetRecordThumb(
                file: form.vetRecordPhotos[i],
                onRemove: () => _set(() => form.vetRecordPhotos.removeAt(i)),
              ),
            if (form.vetRecordPhotos.length < kMaxVetRecordPhotos)
              _AddRecordTile(onTap: _addVetRecords),
          ],
        ),
        const SizedBox(height: 28),

        // ---- Surrender details ---------------------------------------------
        const _SectionTitle('Surrender Details'),
        const SizedBox(height: 14),

        RescueFieldLabel('Why are you surrendering this pet?', required: true),
        const SizedBox(height: 6),
        _SurrenderDropdown(
          field: 'surrenderReason',
          value: form.surrenderReason,
          hint: 'Select a reason',
          options: kSurrenderReasonOptions,
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

        RescueFieldLabel(
          'How soon does the pet need to be rehomed?',
          required: true,
        ),
        const SizedBox(height: 6),
        _SurrenderDropdown(
          field: 'timeline',
          value: form.surrenderTimeline,
          hint: 'Select a timeframe',
          options: kSurrenderTimelineOptions,
          onChanged: (v) => _set(() => form.surrenderTimeline = v),
        ),
      ],
    );
  }
}

/// Small bold heading that groups related surrender questions.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
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
}

/// Underlined single-select dropdown. Keyed by [field] plus its value so
/// sibling dropdowns never share a key (two null values once collided as
/// ValueKey(null) and crashed the form), while a new value still resets
/// `initialValue`.
class _SurrenderDropdown extends StatelessWidget {
  const _SurrenderDropdown({
    required this.field,
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
  });

  final String field;
  final String? value;
  final String hint;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$field:$value'),
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: GoogleFonts.zain(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary),
        ),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              option,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _VetRecordThumb extends StatelessWidget {
  const _VetRecordThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(file.path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 72,
              height: 72,
              color: AppColors.slaterspwn.withValues(alpha: 0.3),
              child: const Icon(Icons.description_outlined),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddRecordTile extends StatelessWidget {
  const _AddRecordTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                size: 20, color: AppColors.textPrimary),
            SizedBox(height: 4),
            Text('Add', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
