// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

// Small, stateless form building blocks shared by the Report a Stray form's
// sections. Each was a private `_build…`/helper method on the page's State.

/// Bold field label with an optional red required-asterisk.
class RescueFieldLabel extends StatelessWidget {
  const RescueFieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.zain(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (required) ...[
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
      ],
    );
  }
}

/// Species dropdown ('Dog' / 'Cat') shared by the owner's pet and every
/// found/stray animal card.
class SpeciesDropdown extends StatelessWidget {
  const SpeciesDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      isDense: true,
      // Fit the column it's in (its widest option otherwise sets its
      // width and overflows half-width rows on small phones).
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Select species',
        hintStyle: GoogleFonts.zain(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary),
        ),
      ),
      items: const [
        DropdownMenuItem(value: kDogSpecies, child: Text('Dog')),
        DropdownMenuItem(value: kCatSpecies, child: Text('Cat')),
      ],
      onChanged: onChanged,
    );
  }
}

/// Breed dropdown, filtered by whichever species is selected. Picking
/// "Others / Not sure" reveals a small text field for a custom breed.
class BreedDropdown extends StatelessWidget {
  const BreedDropdown({
    super.key,
    required this.species,
    required this.breedValue,
    required this.onChanged,
    required this.otherController,
  });

  final String? species;
  final String? breedValue;
  final ValueChanged<String?> onChanged;
  final TextEditingController otherController;

  @override
  Widget build(BuildContext context) {
    final options = breedOptionsFor(species);
    final validValue = (breedValue != null && options.contains(breedValue))
        ? breedValue
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(validValue),
          initialValue: validValue,
          isDense: true,
          // Fit the column it's in (its widest option otherwise sets its
          // width and overflows half-width rows on small phones).
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: species == null ? 'Select species first' : 'Select breed',
            hintStyle: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary),
            ),
          ),
          items: species == null
              ? const []
              : options
              .map(
                (b) => DropdownMenuItem(
              value: b,
              child: Text(
                b,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          )
              .toList(),
          onChanged: species == null ? null : onChanged,
        ),
        if (validValue == kOthersBreedLabel) ...[
          const SizedBox(height: 8),
          RescueTextField(otherController, 'Enter breed'),
        ],
      ],
    );
  }
}

/// One answer of a single-choice question: a bordered tile with a radio
/// mark, so mutually exclusive answers look and behave like radio buttons
/// (they used to be square checkboxes, which read as "pick any").
/// [value] is what gets stored; it defaults to [label].
class RescueRadioOption extends StatelessWidget {
  const RescueRadioOption(
      this.label,
      this.selected,
      this.onSelect, {
        super.key,
        this.value,
      });

  final String label;
  final String? selected;
  final ValueChanged<String> onSelect;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value ?? label;
    final isSelected = selected == v;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: isSelected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelect(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? kRescueSelectedFill : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.textPrimary : kRescueFieldBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pale yellow fill for a selected chip/option, with a dark olive border.
const Color kRescueSelectedFill = Color(0xFFFFF4CC);

/// Subtle gray border for unselected chips/options and form cards.
const Color kRescueFieldBorder = Color(0xFFDAD7CC);

/// A titled card grouping one part of the form ("1 · Location", ...), so
/// the long form reads as a few clear steps.
class RescueFormSection extends StatelessWidget {
  const RescueFormSection({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kRescueFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.yellowrspwn, shape: BoxShape.circle),
                child: Text('$step',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(subtitle!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Small section heading inside an animal card ("Health assessment").
class RescueSubsectionHeader extends StatelessWidget {
  const RescueSubsectionHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (subtitle != null)
          Text(subtitle!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// The rescue type's urgency, set automatically, with the reason — so a
/// reporter (and later staff) can see why a case is Critical/Medium/Low.
class RescueUrgencyCard extends StatelessWidget {
  const RescueUrgencyCard({super.key, required this.rescueType, required this.urgency});

  final String rescueType;
  final String? urgency;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColorFor(urgency);
    String? description;
    for (final o in kRescueTypeOptions) {
      if (o['label'] == rescueType) description = o['description'];
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Text('${urgency ?? 'N/A'} urgency',
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Set automatically from the rescue type'
                  '${description == null ? '' : ' — $rescueType: ${description[0].toLowerCase()}${description.substring(1)}'}.'
                  ' Staff may update the animal\'s condition after the rescue.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Underlined tappable field that opens a date/time picker.
class RescuePickerField extends StatelessWidget {
  const RescuePickerField({
    super.key,
    required this.label,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.textPrimary, width: 1),
          ),
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Underlined single-line text field used throughout the form.
class RescueTextField extends StatelessWidget {
  const RescueTextField(
      this.controller,
      this.hint, {
        super.key,
        this.keyboardType,
        this.inputFormatters,
      });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
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
    );
  }
}

/// Dropdown for one Health & Behavior Assessment field.
class AssessmentDropdown extends StatelessWidget {
  const AssessmentDropdown({
    super.key,
    required this.hintText,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String hintText;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: GoogleFonts.zain(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary),
        ),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(
              o,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.zain(fontSize: 13),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Rounded multi-select chip.
class RescueToggleChip extends StatelessWidget {
  const RescueToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // At least the old fixed height; a label too long for the row wraps
        // onto a second line instead of overflowing on small phones.
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kRescueSelectedFill : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.textPrimary : kRescueFieldBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: AppColors.textPrimary),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bite / Escape risk dropdown with a persistent label above it.
class RiskDropdown extends StatelessWidget {
  const RiskDropdown({
    super.key,
    required this.label,
    required this.hintText,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String hintText;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // A persistent label above the field, separate from `hintText` (which
    // is Flutter's InputDecoration.hintText — it only renders while the
    // value is null and disappears the moment anything is selected). Once
    // an admin/reporter picks a level, the dropdown itself only shows the
    // bare value (e.g. "High") with nothing else identifying it as Bite
    // vs. Escape risk — this label fixes that in both view and edit
    // states, since it's always visible regardless of selection.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        DropdownButtonFormField<String>(
          key: ValueKey(value),
          initialValue: value,
          isDense: true,
          isExpanded:
          true, // lets the selected-value Text shrink to fit instead of overflowing
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary),
            ),
          ),
          items: [
            for (final level in options)
              DropdownMenuItem(
                value: level,
                child: Text(level, overflow: TextOverflow.ellipsis),
              ),
          ],
          selectedItemBuilder: (context) => [
            for (final _ in options)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  value ?? '',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
