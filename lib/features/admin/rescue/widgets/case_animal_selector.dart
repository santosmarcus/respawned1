import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';

/// One selectable entry for a case's `animals[]` list — [index] is the
/// stable identifier (list position; RescueCase.animals has no other id —
/// see RescueCaseRepository.reportAnimalDeath's own animalIndex convention,
/// reused here rather than inventing a second scheme). [label] is the
/// animal's linked AnimalRecord name when one exists, otherwise a
/// per-species ordinal ("Dog 1", "Dog 2", "Cat 1") computed from list order.
class CaseAnimalOption {
  final int index;
  final String label;
  const CaseAnimalOption({required this.index, required this.label});
}

/// [namesByAnimalIndex] — optional linked AnimalRecord names keyed by
/// sourceAnimalIndex (see recordsForCaseProvider), for cases already past
/// Intake. Most cases reach Treatment before any AnimalRecord exists, so
/// this is normally empty and every option falls back to the species-
/// ordinal label — exactly the shape the spec's own examples show.
List<CaseAnimalOption> buildCaseAnimalOptions(RescueCase c, {Map<int, String>? namesByAnimalIndex}) {
  final speciesOrdinal = <String, int>{};
  return List.generate(c.animals.length, (i) {
    final species = (c.animals[i]['species'] as String?)?.trim();
    final key = (species == null || species.isEmpty) ? 'Animal' : species;
    final ordinal = (speciesOrdinal[key] ?? 0) + 1;
    speciesOrdinal[key] = ordinal;
    final name = namesByAnimalIndex?[i];
    return CaseAnimalOption(index: i, label: (name != null && name.isNotEmpty) ? name : '$key $ordinal');
  });
}

Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.yellowrspwn : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? AppColors.yellowrspwn : AppColors.slaterspwn),
      ),
      child: Text(
        label,
        style: GoogleFonts.zain(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    ),
  );
}

/// Visible, non-carousel horizontally scrollable selector — never hides the
/// current selection behind a swipe. Single-select: null means "All
/// Animals" (the default). Used both to filter Treatment Logs/Cost
/// Tracking by animal and to preserve that selection across the two
/// sections, since they share one page/state (treatment_detail_page.dart).
class CaseAnimalSelectorBar extends StatelessWidget {
  final List<CaseAnimalOption> options;
  final int? selected;
  final ValueChanged<int?> onChanged;

  const CaseAnimalSelectorBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _chip(label: 'All Animals', selected: selected == null, onTap: () => onChanged(null));
          }
          final o = options[i - 1];
          return _chip(label: o.label, selected: selected == o.index, onTap: () => onChanged(o.index));
        },
      ),
    );
  }
}

/// Multi-select variant for the "Applies to" field on a new Treatment Log
/// or Expense: All Animals (clears the set) / one tap toggles a specific
/// animal in/out of the set. A non-empty [selected] set is "One animal" or
/// "Multiple animals" depending on its size — spec's three options map onto
/// one underlying representation (an empty set means All Animals) rather
/// than three separate fields.
class CaseAnimalMultiSelectBar extends StatelessWidget {
  final List<CaseAnimalOption> options;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  const CaseAnimalMultiSelectBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.length <= 1) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(label: 'All Animals', selected: selected.isEmpty, onTap: () => onChanged(const {})),
        for (final o in options)
          _chip(
            label: o.label,
            selected: selected.contains(o.index),
            onTap: () {
              final next = {...selected};
              if (next.contains(o.index)) {
                next.remove(o.index);
              } else {
                next.add(o.index);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}
