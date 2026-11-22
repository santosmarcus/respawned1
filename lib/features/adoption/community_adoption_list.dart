import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/utils/stream_combine.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';
import 'package:respawnd1/features/adoption/community_profile.dart';

/// One animal still available on a Community Adoption listing.
class CommunityListingAnimal {
  final String caseId;
  final int index;
  final String label;
  final String species;
  final String breed;
  final String? photoUrl;
  final CommunityAnimalProfile profile;
  final String summary;
  final DateTime? listedAt;

  const CommunityListingAnimal({
    required this.caseId,
    required this.index,
    required this.label,
    required this.species,
    required this.breed,
    required this.photoUrl,
    required this.profile,
    this.summary = '',
    this.listedAt,
  });
}

/// Every animal still available across the reports open for Community
/// Adoption (rejected as healthy / low urgency, not lost pets; and Pet
/// Surrenders while active), newest
/// first. Read from the public copy of each case (`publicCases`), which
/// carries the reporter's adoption profile as `communityListing`.
List<CommunityListingAnimal> communityListingAnimalsOf(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
  final out = <CommunityListingAnimal>[];
  for (final doc in docs) {
    final d = doc.data();
    if (d['hiddenFromExplore'] == true) continue;
    if (!isCommunityAdoptionEligible(
      status: d['status'] as String?,
      rejectionReason: d['rejectionReason'] as String?,
      rescueType: d['rescueType'] as String?,
    )) {
      continue;
    }
    final animals = (d['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final labels = CommunityAdoptionRequestRepository.animalLabelsOf(d);
    final claimed = {
      for (final i in d['claimedAnimalIndexes'] as List? ?? const []) (i as num).toInt(),
    };
    final photos = List<String>.from(d['photoUrls'] ?? const []);
    final created = d['createdAt'];
    for (var i = 0; i < labels.length; i++) {
      if (claimed.contains(i)) continue;
      final raw = i < animals.length ? animals[i] : d;
      out.add(CommunityListingAnimal(
        caseId: doc.id,
        index: i,
        label: labels[i],
        species: ((raw['species'] ?? raw['animalType']) as String?) ?? '',
        breed: (raw['breed'] as String?) ?? '',
        photoUrl: photos.isEmpty ? null : photos.first,
        profile: communityProfileOf(d, i),
        summary: reportSummaryOf(d),
        listedAt: created is Timestamp ? created.toDate() : null,
      ));
    }
  }
  out.sort((a, b) => (b.listedAt ?? DateTime(0)).compareTo(a.listedAt ?? DateTime(0)));
  return out;
}

/// The Community Adoption section of the adoption listing.
class CommunityAdoptionList extends StatelessWidget {
  const CommunityAdoptionList({
    super.key,
    this.speciesFilter,
    this.searchQuery = '',
  });

  /// 'Dog' or 'Cat'; null shows every species.
  final String? speciesFilter;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final cases = FirebaseFirestore.instance.collection('publicCases');
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      // Healthy strays an organization rejected for rescue, and Pet
      // Surrenders, listed as soon as they are filed (a withdrawn one has
      // left this status and so leaves the list).
      stream: combineLatest([
        cases
            .where('status', isEqualTo: 'rejected')
            .where('rejectionReason', isEqualTo: RejectionReason.healthyAnimalLowUrgency.name)
            .snapshots()
            .map((s) => s.docs),
        cases.where('status', isEqualTo: kCommunityAdoptionStatus).snapshots().map((s) => s.docs),
      ]).map((lists) => [for (final l in lists) ...l]),
      builder: (context, snap) {
        if (snap.hasError) {
          return _message('Could not load community adoptions. Please try again later.');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final q = searchQuery.trim().toLowerCase();
        final animals = communityListingAnimalsOf(snap.data!).where((a) {
          if (speciesFilter != null && a.species.toLowerCase() != speciesFilter!.toLowerCase()) {
            return false;
          }
          if (q.isEmpty) return true;
          return [a.label, a.profile.name, a.breed, a.species, a.profile.about]
              .any((s) => s.toLowerCase().contains(q));
        }).toList();

        if (animals.isEmpty) {
          return _message(
            'No animals are open for Community Adoption right now.\n'
                'These are healthy strays reported by the community, and pets '
                'whose owners are looking for a new home for them.',
          );
        }
        // Same list layout as the Adopt a Stray list (adoption_page.dart).
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: animals.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final a = animals[i];
            return CommunityAnimalCard(
              profile: a.profile,
              label: a.label,
              species: a.species,
              breed: a.breed,
              photoUrl: a.photoUrl,
              fallbackDescription: a.summary,
              statusLabel: 'Available',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CommunityAnimalPage(caseId: a.caseId, index: a.index)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
      ),
    ),
  );
}
