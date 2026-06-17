import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'collar_tag_data_model.dart';
import 'collar_tag_form_screen.dart';

//  Pet Identification Card Screen

class CollarIdTagCardScreen extends StatefulWidget {
  final CollarTagData tagData;
  final bool isNewlyCreated;

  const CollarIdTagCardScreen({
    super.key,
    required this.tagData,
    this.isNewlyCreated = false,
  });

  @override
  State<CollarIdTagCardScreen> createState() => _CollarIdTagCardScreenState();
}

class _CollarIdTagCardScreenState extends State<CollarIdTagCardScreen> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.isNewlyCreated) _saveFcmTokenToTag();
  }

  Future<void> _saveFcmTokenToTag() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || widget.tagData.tagId == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(widget.tagData.tagId)
          .update({'ownerFcmToken': token, 'ownerId': uid});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc('main')
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final tag = widget.tagData;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => _editTag(context),
            child: Text('Edit',
                style: GoogleFonts.zain(
                    fontSize: 15, color: AppColors.textPrimary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Text(
              'Pet Identification\nCard',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),


            RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Pet photo
                    _PetPhoto(
                      imageUrl: tag.petImageUrl,
                      imagePath: tag.petImagePath,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tag.name.isNotEmpty ? tag.name : '—',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Breed:', tag.breed),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Color/Markings:', tag.colorMarkings),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Birthday: ${tag.birthday}', 'Sex: ${tag.sex}',
                        isDouble: true),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    const SizedBox(height: 8),
                    _healthDots(tag),
                    const SizedBox(height: 10),

                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Owner Information',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              color: AppColors.textPrimary)),
                    ),

                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerName,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerMobile,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),


                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Finish
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text('Finish',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // Helpers

  Widget _infoRow(String left, String right, {bool isDouble = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(left,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
          Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _healthDots(CollarTagData tag) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dot(tag.isSpayedNeutered, 'Spayed'),
              _dot(tag.isVaccinated, 'Vaccinated'),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dot(
                tag.allergies.isEmpty || tag.allergies.toLowerCase() == 'none',
                'No Allergies',
              ),
              _dot(
                tag.medicalCondition.isEmpty ||
                    tag.medicalCondition.toLowerCase() == 'none',
                'No Medical Condition',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot(bool positive, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: positive ? AppColors.textPrimary : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );

  void _editTag(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollarTagFormScreen(
          existingTag: widget.tagData,
        ),
      ),
    );
  }
}

// Pet Photo

class _PetPhoto extends StatelessWidget {
  final String? imageUrl;
  final String? imagePath;

  const _PetPhoto({this.imageUrl, this.imagePath});

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (imagePath != null && File(imagePath!).existsSync()) {
      child = Image.file(File(imagePath!), fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      child = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
        const Icon(Icons.pets, size: 50, color: AppColors.textPrimary),
      );
    } else {
      child = const Icon(Icons.pets, size: 50, color: AppColors.textPrimary);
    }

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.tearspwn,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// Action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap != null
                ? AppColors.textPrimary
                : AppColors.textPrimary.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textPrimary),
              )
            else
              Icon(icon,
                  size: 20,
                  color: onTap != null
                      ? AppColors.textPrimary
                      : AppColors.textPrimary.withOpacity(0.4)),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    color: onTap != null
                        ? AppColors.textPrimary
                        : AppColors.textPrimary.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}