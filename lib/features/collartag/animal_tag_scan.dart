import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Prefix of the QR payload printed for animal records (Animal Management >
/// Add QR Tag). Collar tags use their own links (AppLinks.tagIdFromScan).
const String kAnimalTagPrefix = 'RESPAWND-ANIMAL:';

/// The tag code inside an animal QR payload, or null if [raw] isn't one.
String? animalTagFromScan(String raw) {
  final value = raw.trim();
  if (!value.startsWith(kAnimalTagPrefix)) return null;
  final tag = value.substring(kAnimalTagPrefix.length).trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{6,16}$').hasMatch(tag) ? tag : null;
}

/// Opens the animal a scanned animal QR points at. Staff of the owning
/// organization get the full record; everyone else gets the public profile.
/// Returns false when [raw] isn't an animal tag, so the caller can fall
/// back to the collar-tag flow.
Future<bool> openScannedAnimalTag(BuildContext context, String raw) async {
  final tag = animalTagFromScan(raw);
  if (tag == null) return false;

  final messenger = ScaffoldMessenger.of(context);
  final snap = await FirebaseFirestore.instance
      .collection('animals')
      .where('qrTagId', isEqualTo: tag)
      .limit(1)
      .get();
  if (!context.mounted) return true;
  if (snap.docs.isEmpty) {
    messenger.showSnackBar(appSnackBar('No animal record uses this QR tag.'));
    return true;
  }

  final doc = snap.docs.first;
  final record = AnimalRecord.fromFirestore(doc);
  final isStaff = await _isStaffOf(doc.data()['organizationId'] as String?);
  if (!context.mounted) return true;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => isStaff
          ? AnimalRecordDetailPage(animalId: doc.id, data: doc.data())
          : AnimalPage(animal: animalRecordToCard(record, 0), onFavoriteToggle: () {}),
    ),
  );
  return true;
}

/// Same split as firestore.rules isStaffOf: linked to the org, and not a carer.
Future<bool> _isStaffOf(String? orgId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || orgId == null || orgId.isEmpty) return false;
  final db = FirebaseFirestore.instance;
  final user = await db.collection('users').doc(uid).get();
  if (user.data()?['organizationId'] != orgId) return false;
  final member = await db.collection('organizations').doc(orgId).collection('members').doc(uid).get();
  return member.data()?['role'] != 'carer';
}
