import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/utils/animal_tag_codes.dart';

// Moved to core/utils/animal_tag_codes.dart (shared with the NFC writer and
// the Management tab); re-exported for existing imports.
export 'package:respawnd1/core/utils/animal_tag_codes.dart' show kAnimalTagPrefix, animalTagFromScan;

/// Opens the animal a scanned animal tag (QR code or NFC chip) points at. Staff of the owning
/// organization get the full record; everyone else gets the public profile.
/// Returns false when [raw] isn't an animal tag, so the caller can fall
/// back to the collar-tag flow.
Future<bool> openScannedAnimalTag(BuildContext context, String raw) async {
  final tag = animalTagFromScan(raw);
  if (tag == null) return false;

  final messenger = ScaffoldMessenger.of(context);
  final db = FirebaseFirestore.instance;

  // The registry (animalTags/{code}) says which animal a QR or NFC code
  // belongs to, and whether it is still active.
  String? animalId;
  try {
    final reg = await db.collection('animalTags').doc(tag).get();
    if (reg.exists) {
      if (reg.data()?['active'] != true) {
        if (context.mounted) {
          messenger.showSnackBar(appSnackBar('This tag was removed from its animal and no longer opens a record.'));
        }
        return true;
      }
      animalId = reg.data()?['animalId'] as String?;
    }
  } on FirebaseException {
    // Not signed in, or offline: fall back to the field lookups below.
  }

  // Staff find their own organization's animals, hidden ones included;
  // everyone else (and staff scanning another organization's tag) finds
  // the public profile. Codes printed before the registry existed are only
  // on the animal's qrTagId.
  DocumentSnapshot<Map<String, dynamic>>? found;
  try {
    if (animalId != null) {
      final own = await AnimalRecordRepository().queryScoped(
        (q) => q.where(FieldPath.documentId, isEqualTo: animalId).limit(1),
      );
      if (own.isNotEmpty) found = own.first;
    } else {
      final own = await AnimalRecordRepository().queryScoped((q) => q.where('qrTagId', isEqualTo: tag).limit(1));
      if (own.isNotEmpty) found = own.first;
    }
  } on FirebaseException {
    // Not staff of any organization.
  }
  if (found == null) {
    if (animalId != null) {
      final pub = await db.collection('publicAnimals').doc(animalId).get();
      if (pub.exists) found = pub;
    } else {
      found = (await db.collection('publicAnimals').where('qrTagId', isEqualTo: tag).limit(1).get()).docs.firstOrNull;
    }
  }
  final doc = found;
  if (!context.mounted) return true;
  if (doc == null) {
    messenger.showSnackBar(appSnackBar('No animal record uses this tag.'));
    return true;
  }

  final record = AnimalRecord.fromFirestore(doc);
  final isStaff =
      doc.reference.parent.id == 'animals' && await isStaffOfOrganization(doc.data()?['organizationId'] as String?);
  if (!context.mounted) return true;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => isStaff
          ? AnimalRecordDetailPage(animalId: doc.id, data: doc.data() ?? const {})
          : AnimalPage(animal: animalRecordToCard(record, 0), onFavoriteToggle: () {}),
    ),
  );
  return true;
}

/// Same split as firestore.rules isStaffOf: linked to the org, and not a carer.
Future<bool> isStaffOfOrganization(String? orgId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || orgId == null || orgId.isEmpty) return false;
  final db = FirebaseFirestore.instance;
  final user = await db.collection('users').doc(uid).get();
  if (user.data()?['organizationId'] != orgId) return false;
  final org = await db.collection('organizations').doc(orgId).get();
  final member = await db.collection('organizations').doc(orgId).collection('members').doc(uid).get();
  // Rescue or animal records staff (Admins have both).
  final caps = capabilitiesFrom(
    uid: uid,
    ownerId: org.data()?['ownerId'] as String?,
    member: member.exists ? (member.data() ?? const {}) : null,
    org: org.data(),
  );
  return caps.canManageRescues || caps.canManageRecords;
}
