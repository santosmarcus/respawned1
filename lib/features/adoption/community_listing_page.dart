import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/community_adoption_request.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/features/adoption/community_adoption_request_page.dart';
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';
import 'package:respawnd1/features/adoption/community_profile.dart';

/// The reporter's view of their own report once it is open for Community
/// Adoption. They cannot adopt it themselves; instead they complete each
/// animal's adoption profile (community_profile.dart), answer interested
/// adopters' requests and choose who adopts.
class CommunityListingPage extends StatelessWidget {
  const CommunityListingPage({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.yellowrspwn,
        leading: IconButton(
          icon: const Icon(
            Icons.chevron_left,
            color: AppColors.textPrimary,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage Community Adoption',
          style: GoogleFonts.tiltWarp(
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('cases')
            .doc(caseId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load your report: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data();
          if (data == null) {
            return Center(
              child: Text(
                'This report is no longer available.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
              ),
            );
          }
          return _ListingBody(caseId: caseId, data: data);
        },
      ),
    );
  }
}

class _ListingBody extends StatelessWidget {
  const _ListingBody({required this.caseId, required this.data});

  final String caseId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final labels = CommunityAdoptionRequestRepository.animalLabelsOf(data);
    final claimed = {
      for (final i in data['claimedAnimalIndexes'] as List? ?? const [])
        (i as num).toInt(),
    };
    final animals =
        (data['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final photos = List<String>.from(data['photoUrls'] ?? const []);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greenrspwn.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Your report #${caseId.substring(0, 7).toUpperCase()} is open for '
                'Community Adoption. As the reporter, you cannot adopt it yourself, '
                'but you can help it find a home: complete each animal\'s adoption '
                'profile, talk with interested adopters, and choose the best fit.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 20),
        Text('Adoption Profile', style: GoogleFonts.tiltWarp(fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          'Shown on the Community Adoption listing. Tap an animal to add or '
              'edit its details.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < labels.length; i++) ...[
              () {
            final profile = communityProfileOf(data, i);
            final raw = i < animals.length ? animals[i] : data;
            final adopted = claimed.contains(i);
            return CommunityAnimalCard(
              profile: profile,
              label: labels[i],
              species: ((raw['species'] ?? raw['animalType']) as String?) ?? '',
              breed: (raw['breed'] as String?) ?? '',
              photoUrl: photos.isEmpty ? null : photos.first,
              fallbackDescription: reportSummaryOf(data),
              statusLabel: adopted
                  ? 'Adopted'
                  : profile.isComplete
                  ? 'Profile complete'
                  : 'Tap to complete profile',
              onTap: adopted
                  ? null
                  : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityProfileEditPage(
                    caseId: caseId,
                    index: i,
                    label: labels[i],
                    initial: profile,
                  ),
                ),
              ),
            );
          }(),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 20),
        Text('Interested Adopters', style: GoogleFonts.tiltWarp(fontSize: 15)),
        const SizedBox(height: 8),
        if (uid != null)
          StreamBuilder<List<CommunityAdoptionRequest>>(
            stream: CommunityAdoptionRequestRepository().watchForLister(
              caseId: caseId,
              listerId: uid,
            ),
            builder: (context, snap) {
              final requests = snap.data ?? const [];
              if (requests.isEmpty) {
                return Text(
                  'No one has expressed interest yet. You will be notified when '
                      'someone does.',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                );
              }
              return Column(
                children: [for (final r in requests) _RequestTile(request: r)],
              );
            },
          ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final CommunityAdoptionRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.slaterspwn),
      ),
      child: ListTile(
        onTap: () => openCommunityAdoptionRequest(context, r.id),
        title: Text(
          r.adopterName,
          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${r.status.label} · ${r.animalsLabel}',
          style: GoogleFonts.zain(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
