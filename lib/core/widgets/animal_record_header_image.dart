import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

/// Shared header image for the user and admin post-adoption pages —
/// always the linked Animal Record's own photo
/// (AnimalRecord.photoUrls, which already resolves
/// imageUrls/images -> legacy imageUrl/photoUrl internally), never a
/// follow-up upload, home photo, application document, return photo, or
/// treatment media. Falls back to the plain paw placeholder when there's
/// no [animalRecordId], the record has no photo, or the record can't be
/// loaded — never a broken-image icon.
class AnimalRecordHeaderImage extends StatelessWidget {
  final String? animalRecordId;
  final double height;
  const AnimalRecordHeaderImage({super.key, required this.animalRecordId, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final id = animalRecordId;
    if (id == null || id.isEmpty) return _placeholder();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('animals').doc(id).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return _placeholder();
        final record = AnimalRecord.fromMap(id, data);
        if (record.photoUrls.isEmpty) return _placeholder();
        return Image.network(
          record.photoUrls.first,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => _placeholder(),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(
                  height: height,
                  width: double.infinity,
                  color: AppColors.tearspwn,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
        height: height,
        width: double.infinity,
        color: AppColors.tearspwn,
        child: const Center(child: Icon(Icons.pets, size: 56, color: AppColors.textPrimary)),
      );
}
