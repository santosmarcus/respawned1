import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

/// Adoption gap 10: one check-in two weeks after a Community Adoption
/// (communityAdoptionCheckIns/{id}, scheduled by
/// scheduleCommunityAdoptionCheckIn in functions/index.js), answered on the
/// post-adoption page (CommunityPostAdoptionPage in post_adoption_page.dart).
CollectionReference<Map<String, dynamic>> get _checkIns =>
    FirebaseFirestore.instance.collection('communityAdoptionCheckIns');

/// Shown on Home when the signed-in user owes a check-in.
class CommunityCheckInBanner extends StatelessWidget {
  const CommunityCheckInBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _checkIns.where('adopterId', isEqualTo: uid).where('status', isEqualTo: 'requested').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              for (final d in docs)
                Card(
                  color: AppColors.greenrspwn,
                  child: ListTile(
                    leading: const Icon(Icons.pets, color: AppColors.textPrimary),
                    title: Text('Check in on ${d.data()['animalName'] ?? 'your adopted animal'}',
                        style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Send your 2-week post-adoption check-in.'),
                    trailing: const Icon(Icons.chevron_right),
                    // The same post-adoption page as Home > Post Adoption.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityPostAdoptionPage(adoptionId: d.id),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Staff list of community adoptions in their area, with check-in state.
class CommunityAdoptionsStaffPage extends StatelessWidget {
  const CommunityAdoptionsStaffPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Community adoptions', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _checkIns.where('organizationIds', arrayContains: organizationId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = [...snap.data!.docs]..sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            final tb = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            return tb.compareTo(ta);
          });
          if (docs.isEmpty) return const Center(child: Text('No community adoptions in your area yet.'));
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final d in docs)
                Card(
                  color: AppColors.surface,
                  child: ListTile(
                    // Opens the adopter's post-adoption updates, read-only.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityPostAdoptionPage(adoptionId: d.id),
                      ),
                    ),
                    leading: d.data()['photoUrl'] is String
                        ? Image.network(d.data()['photoUrl'] as String, width: 48, height: 48, fit: BoxFit.cover)
                        : const Icon(Icons.pets),
                    title: Text('${d.data()['animalName'] ?? d.data()['species'] ?? 'Animal'} · ${d.data()['adopterName'] ?? 'Adopter'}',
                        style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      switch (d.data()['status']) {
                        'submitted' => 'Check-in: ${d.data()['note'] ?? ''}',
                        'requested' => 'Check-in requested, no answer yet',
                        _ => 'Check-in due ${d.data()['dueAt'] is Timestamp ? formatDate((d.data()['dueAt'] as Timestamp).toDate()) : ''}',
                      },
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
