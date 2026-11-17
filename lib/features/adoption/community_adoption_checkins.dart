import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';

/// Adoption gap 10: one light check-in two weeks after a Community Adoption
/// (communityAdoptionCheckIns/{id}, scheduled by
/// scheduleCommunityAdoptionCheckIn in functions/adoption_ops.js). No
/// interview, agreement or schedule — just a photo and a line.
CollectionReference<Map<String, dynamic>> get _checkIns =>
    FirebaseFirestore.instance.collection('communityAdoptionCheckIns');

/// Shown on Home when the signed-in user owes a check-in.
class CommunityCheckInBanner extends StatelessWidget {
  const CommunityCheckInBanner({super.key});

  Future<void> _submit(BuildContext context, DocumentSnapshot<Map<String, dynamic>> d) async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo == null || !context.mounted) return;
    final note = await showTextInputDialog(context,
        title: 'How is ${d.data()?['animalName'] ?? 'your animal'}?', label: 'A short update', confirmLabel: 'Send', required: true);
    if (note == null) return;
    final ref = FirebaseStorage.instance.ref('communityAdoptions/${d.id}/checkin.jpg');
    await ref.putFile(File(photo.path));
    await d.reference.update({
      'status': 'submitted',
      'photoUrl': await ref.getDownloadURL(),
      'note': note,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

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
                    subtitle: const Text('Send a photo and a short update.'),
                    trailing: const Icon(Icons.photo_camera),
                    onTap: () => _submit(context, d),
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
