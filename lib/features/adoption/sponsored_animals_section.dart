import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/donation/sponsorship.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/repos/sponsorship_repository.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';

/// Home screen "Sponsored Animals" — the animals the SIGNED-IN user is
/// currently (actively) sponsoring, shown right under Post Adoption.
/// Mirrors PostAdoption's own plain-StreamBuilder row-list pattern in this
/// same file's sibling widget, rather than the Activity carousel's
/// PageView pattern — the two existing Home sections don't share a single
/// visual pattern, and this is a simple list of a few sponsorships, not a
/// swipeable feed. No new sponsorship collection: reads the existing
/// `sponsors` collection via [SponsorshipRepository].
class SponsoredAnimalsSection extends StatelessWidget {
  const SponsoredAnimalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<Sponsorship>>(
      stream: SponsorshipRepository().streamActiveSponsorshipsForUser(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
          );
        }
        if (snap.hasError) {
          return _message('Could not load your sponsored animals.');
        }
        final sponsorships = snap.data ?? const [];
        // Compact empty state — matches the sibling Post Adoption section's
        // own "No adopted pets yet." pattern immediately above this one,
        // rather than hiding the whole section (which would leave this
        // section's own header floating above nothing).
        if (sponsorships.isEmpty) return _message('No sponsored animals yet.');

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: sponsorships.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _SponsoredAnimalTile(sponsorship: sponsorships[i]),
        );
      },
    );
  }

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), boxShadow: [
            BoxShadow(color: AppColors.slaterspwn, blurRadius: 1, offset: const Offset(0, 3)),
          ]),
          child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
}

class _SponsoredAnimalTile extends StatelessWidget {
  final Sponsorship sponsorship;
  const _SponsoredAnimalTile({required this.sponsorship});

  String _fmtDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: sponsorship.animalRecordId.isEmpty
          ? null
          : FirebaseFirestore.instance.collection('animals').doc(sponsorship.animalRecordId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final record = data == null ? null : AnimalRecord.fromMap(sponsorship.animalRecordId, data);
        final displayName = (record?.name.isNotEmpty ?? false) ? record!.name : sponsorship.animalName;
        final photoUrl = (record?.photoUrls.isNotEmpty ?? false) ? record!.photoUrls.first : null;

        return GestureDetector(
          onTap: () {
            if (record == null) return;
            final animal = animalRecordToCard(record, 0);
            Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalPage(animal: animal, onFavoriteToggle: () {})));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), boxShadow: [
              BoxShadow(color: AppColors.slaterspwn, blurRadius: 1, offset: const Offset(0, 3)),
            ]),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: photoUrl != null
                      ? Image.network(photoUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName.isEmpty ? 'Sponsored animal' : displayName,
                          style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      if (sponsorship.organizationName.isNotEmpty)
                        Text(sponsorship.organizationName, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      Row(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                            child: Text(sponsorship.status.label, style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                      if (sponsorship.startDate != null)
                        Text('Since ${_fmtDate(sponsorship.startDate!)}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      if (sponsorship.nextContributionDate != null)
                        Text(
                          'Next contribution: ${_fmtDate(sponsorship.nextContributionDate!)}${sponsorship.cycle != null ? ' (${sponsorship.cycle})' : ''}',
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
        width: 48,
        height: 48,
        color: AppColors.tearspwn,
        child: const Icon(Icons.pets, size: 22, color: AppColors.textPrimary),
      );
}
