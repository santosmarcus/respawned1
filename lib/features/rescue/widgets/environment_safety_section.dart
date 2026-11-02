// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';

/// Environment and Safety chips for one animal — the predefined options
/// plus an optional reporter-added custom entry. Values belong to this
/// [entry] only; [onChanged] just triggers the parent's setState since the
/// actual data lives on the entry, not local widget state.
class EnvironmentSafetySection extends StatefulWidget {
  final FoundAnimalEntry entry;
  final VoidCallback onChanged;
  const EnvironmentSafetySection({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  @override
  State<EnvironmentSafetySection> createState() =>
      _EnvironmentSafetySectionState();
}

class _EnvironmentSafetySectionState extends State<EnvironmentSafetySection> {
  bool _addingCustom = false;

  void _addCustomValue() {
    final value = widget.entry.environmentSafetyOtherController.text.trim();
    if (value.isEmpty) return;
    // Case-insensitive de-dupe against both the predefined list and
    // whatever custom values this animal already has.
    final alreadyPresent =
        widget.entry.environmentSafety.any(
          (v) => v.toLowerCase() == value.toLowerCase(),
        ) ||
        kEnvironmentSafetyOptions.any(
          (v) => v.toLowerCase() == value.toLowerCase(),
        );
    if (alreadyPresent) {
      widget.entry.environmentSafetyOtherController.clear();
      setState(() => _addingCustom = false);
      return;
    }
    widget.entry.environmentSafety.add(value);
    widget.entry.environmentSafetyOtherController.clear();
    setState(() => _addingCustom = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // Custom values are whatever's in the set beyond the predefined list —
    // shown as their own removable chips alongside it.
    final customValues = entry.environmentSafety
        .where((v) => !kEnvironmentSafetyOptions.contains(v))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Environment and Safety',
          style: GoogleFonts.zain(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kEnvironmentSafetyOptions)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (entry.environmentSafety.contains(option)) {
                      entry.environmentSafety.remove(option);
                    } else {
                      entry.environmentSafety.add(option);
                    }
                  });
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: entry.environmentSafety.contains(option)
                        ? AppColors.yellowrspwn
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: entry.environmentSafety.contains(option)
                          ? AppColors.yellowrspwn
                          : AppColors.slaterspwn,
                    ),
                  ),
                  child: Text(
                    option,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: entry.environmentSafety.contains(option)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            for (final custom in customValues)
              GestureDetector(
                onTap: () {
                  setState(() => entry.environmentSafety.remove(custom));
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.yellowrspwn),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        custom,
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            if (!_addingCustom)
              GestureDetector(
                onTap: () => setState(() => _addingCustom = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.slaterspwn,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Text(
                    'Add another (optional)',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_addingCustom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.environmentSafetyOtherController,
                  autofocus: true,
                  onSubmitted: (_) => _addCustomValue(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter a custom value',
                    hintStyle: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.textPrimary),
                    ),
                  ),
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: _addCustomValue,
                icon: const Icon(Icons.check, color: AppColors.greenrspwn),
              ),
              IconButton(
                onPressed: () {
                  entry.environmentSafetyOtherController.clear();
                  setState(() => _addingCustom = false);
                },
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
