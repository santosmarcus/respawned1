import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

/// The animal's gender icon, or null for 'Unknown'/unset sex — never
/// guesses Male as a default. Shared by the list card and the admin/user
/// detail-page headers so gender reads identically everywhere it appears.
IconData? genderIconFor(String sex) => switch (sex.toLowerCase()) {
      'male' => Icons.male,
      'female' => Icons.female,
      _ => null,
    };

/// One chip shown in an [AnimalRecordCard]'s chip row — label + color, used
/// for both the admin's attention/status chips and the user's health tags.
class CardChip {
  final String label;
  final Color color;
  const CardChip(this.label, {this.color = AppColors.yellowrspwn});
}

/// Shared Animal Record list-card — the structural base for both the admin
/// Animal Records list (`animal_record_page.dart`) and the user Adoption
/// list (`adoption_page.dart`), which used to be two unrelated layouts (the
/// admin card put the gender icon alone at the card's far-right edge; the
/// user card had no admin equivalent at all). Both now render the exact
/// same image/name/basic-info/chip structure; only the optional
/// role-specific slots below differ per caller.
class AnimalRecordCard extends StatelessWidget {
  final AnimalRecord animal;
  final VoidCallback onTap;

  /// User-only: null hides the heart entirely (admin never passes this).
  final VoidCallback? onFavorite;
  final bool favorited;

  /// User-only: the public Available/Reserved/Adopted/Not Available label.
  final String? publicStatusLabel;

  /// Extra chips beyond the public-status pill — admin passes its
  /// attention/status chips (Vaccine, In Treatment, Reserved, Archived,
  /// ...); the user side passes health tags (Vaccinated, Dewormed, ...).
  final List<CardChip> extraChips;

  /// Admin-only: hides the description line and the entire chip row so the
  /// list card shows only what's needed to scan/identify a record (image,
  /// name+gender, species/breed, age). The user-facing adoption list never
  /// sets this — its description and public-status/health chips stay.
  final bool compact;

  /// Admin-only: enters/toggles the Animal Records list's long-press
  /// multi-select mode. Null on the user-facing adoption list.
  final VoidCallback? onLongPress;

  /// True while this card is part of the active selection — draws the
  /// same selected-state border the app already uses for chosen tabs/
  /// chips, rather than a one-off style.
  final bool selected;

  const AnimalRecordCard({
    super.key,
    required this.animal,
    required this.onTap,
    this.onFavorite,
    this.favorited = false,
    this.publicStatusLabel,
    this.extraChips = const [],
    this.compact = false,
    this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    if (animal.isMalformed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.slaterspwn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not display this record (${animal.id}) — its data may be from an older format.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final displayName = animal.name.isNotEmpty ? animal.name : animal.species;
    final genderIcon = genderIconFor(animal.sex);
    final subtitle = [
      if (animal.species.isNotEmpty) animal.species,
      if (animal.breed.isNotEmpty) animal.breed,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: selected ? Border.all(color: AppColors.yellowrspwn, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: animal.photoUrls.isNotEmpty
                  ? Image.network(
                      animal.photoUrls.first,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoPlaceholder(),
                    )
                  : _photoPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Gender icon sits directly beside the name — never
                      // alone at the card's far-right edge, and hidden
                      // entirely (not defaulted to Male) for Unknown/unset.
                      if (genderIcon != null) ...[
                        const SizedBox(width: 6),
                        Icon(genderIcon, size: 16, color: AppColors.textSecondary),
                      ],
                      if (onFavorite != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onFavorite,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            favorited ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: favorited ? const Color(0xFFE05C5C) : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (animal.age.isNotEmpty)
                    Text(animal.age, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (!compact && animal.description.isNotEmpty)
                    Text(
                      animal.description,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (!compact && (publicStatusLabel != null || extraChips.isNotEmpty)) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (publicStatusLabel != null)
                          _chip(publicStatusLabel!, _publicStatusColor(publicStatusLabel!)),
                        for (final c in extraChips) _chip(c.label, c.color),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _publicStatusColor(String status) => switch (status) {
        'Reserved' => const Color(0xFFE0A83C),
        'Adopted' => AppColors.slaterspwn,
        'Not Available' => AppColors.slaterspwn,
        _ => AppColors.greenrspwn,
      };

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
      );

  Widget _photoPlaceholder() => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, size: 32, color: AppColors.textSecondary),
      );
}

/// Admin Animal Records grid-view card — the vertical counterpart to
/// [AnimalRecordCard]'s (horizontal) list layout, showing the exact same
/// compact field set (image, name+gender, species/breed, age; never a
/// description or chip row) and the same long-press multi-select contract
/// (stable doc id, `selected` border), so switching list/grid never changes
/// what information is shown or how selection behaves.
class AnimalRecordGridTile extends StatelessWidget {
  final AnimalRecord animal;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  const AnimalRecordGridTile({
    super.key,
    required this.animal,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    if (animal.isMalformed) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: Center(
          child: Text('Could not display this record.',
              textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        ),
      );
    }

    final displayName = animal.name.isNotEmpty ? animal.name : animal.species;
    final genderIcon = genderIconFor(animal.sex);
    final subtitle = [
      if (animal.species.isNotEmpty) animal.species,
      if (animal.breed.isNotEmpty) animal.breed,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: AppColors.yellowrspwn, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: animal.photoUrls.isNotEmpty
                    ? Image.network(
                        animal.photoUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gridPlaceholder(),
                      )
                    : _gridPlaceholder(),
              ),
            ),
            const SizedBox(height: 8),
            // Name + gender in one Row, never a separate top-right trailing
            // icon — same rule as the list card.
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: GoogleFonts.tiltWarp(fontSize: 13, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (genderIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(genderIcon, size: 14, color: AppColors.textSecondary),
                ],
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (animal.age.isNotEmpty)
              Text(animal.age, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _gridPlaceholder() => Container(
        color: AppColors.tearspwn,
        child: const Center(child: Icon(Icons.pets, size: 28, color: AppColors.textSecondary)),
      );
}
