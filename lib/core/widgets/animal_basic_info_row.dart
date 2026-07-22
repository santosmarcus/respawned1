import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// One label/value pair for [AnimalBasicInfoRow] — e.g. ('Breed', 'Aspin').
class InfoField {
  final String label;
  final String value;
  const InfoField(this.label, this.value);
}

/// Responsive basic-information grid shared by the admin Profile tab
/// (`animal_profile_tab.dart`) and the user animal detail page
/// (`animal_page.dart`) — replaces what used to be two independent,
/// slightly different fixed-width `Row`-of-`Expanded` layouts (three
/// columns, unconditionally), which overflowed on narrow screens. Uses
/// `Wrap` so it naturally reflows to fewer columns instead.
class AnimalBasicInfoRow extends StatelessWidget {
  final List<InfoField> fields;
  const AnimalBasicInfoRow({super.key, required this.fields});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth < 320 ? 2 : 3;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: [
            for (final f in fields) SizedBox(width: itemWidth, child: _FieldTile(f)),
          ],
        );
      },
    );
  }
}

class _FieldTile extends StatelessWidget {
  final InfoField field;
  const _FieldTile(this.field);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        Text(
          field.value,
          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
