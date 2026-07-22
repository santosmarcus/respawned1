import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

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

  const AnimalRecordCard({
    super.key,
    required this.animal,
    required this.onTap,
    this.onFavorite,
    this.favorited = false,
    this.publicStatusLabel,
    this.extraChips = const [],
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
    final subtitle = [
      if (animal.species.isNotEmpty) animal.species,
      if (animal.breed.isNotEmpty) animal.breed,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                      const SizedBox(width: 6),
                      // Gender icon sits directly beside the name — never
                      // alone at the card's far-right edge.
                      Icon(
                        animal.sex.toLowerCase() == 'female' ? Icons.female : Icons.male,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
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
                  if (animal.description.isNotEmpty)
                    Text(
                      animal.description,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
