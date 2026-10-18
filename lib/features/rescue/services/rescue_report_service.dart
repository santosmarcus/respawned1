// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/features/rescue/rescue_form_controller.dart';

/// Per-slot upload progress callback: [progress] is 0..1 while uploading
/// and null once that slot has finished.
typedef MediaUploadProgress = void Function(int slot, double? progress);

/// Firestore / Storage writes for the Report a Stray form. Moved verbatim
/// from the page: same collections (`users`, `cases`, `petAlerts`,
/// `possibleMatches`), same document fields, same write order and same
/// Storage paths. Validation happens before these are called; any
/// exception propagates to the page, which shows it as before.
class RescueReportService {
  RescueReportService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Uploads every non-empty media slot to `cases/<caseId>/media_<i>.<ext>`.
  Future<({List<String> photoUrls, List<String> videoUrls})> uploadMedia(
    List<RescueMediaItem?> mediaFiles,
    String caseId, {
    required MediaUploadProgress onProgress,
  }) async {
    final photoUrls = <String>[];
    final videoUrls = <String>[];

    for (int i = 0; i < mediaFiles.length; i++) {
      final item = mediaFiles[i];
      if (item == null) continue;

      final ext = item.isVideo ? 'mp4' : 'jpg';
      final ref = FirebaseStorage.instance.ref().child(
        'cases/$caseId/media_$i.$ext',
      );

      final task = ref.putFile(
        File(item.file.path),
        SettableMetadata(
          contentType: item.isVideo ? 'video/mp4' : 'image/jpeg',
        ),
      );

      // Track upload progress for slot
      task.snapshotEvents.listen((snap) {
        onProgress(
          i,
          snap.bytesTransferred / (snap.totalBytes == 0 ? 1 : snap.totalBytes),
        );
      });

      await task;
      final url = await ref.getDownloadURL();
      if (item.isVideo) {
        videoUrls.add(url);
      } else {
        photoUrls.add(url);
      }

      onProgress(i, null);
    }

    return (photoUrls: photoUrls, videoUrls: videoUrls);
  }

  /// Creates the rescue / surrender case (one doc for every animal), then
  /// uploads media and attaches the URLs. Returns the new case id.
  Future<String> submitRescueCase({
    required RescueFormController form,
    required LatLng location,
    required String pinnedAddress,
    required MediaUploadProgress onProgress,
  }) async {
    final condition = form.conditionController.text.trim();
    final validAnimals = form.validAnimals;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data();
    final reporterName =
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();

    final casesCollection = _db.collection('cases');

    // One case document covers every animal in this report — an
    // `animals[]` entry per animal, not a separate case doc per animal.
    // Every phase downstream (Treatment's animal selector, Intake,
    // Animal Record creation via sourceAnimalIndex, findPossibleDuplicates,
    // etc.) already reads this array as the primary source, falling back
    // to the legacy top-level animalType/breed/... fields only for
    // reports saved before this array existed — so this is the only
    // write-side change needed to keep every animal attached through the
    // whole workflow instead of losing all but one to a since-removed
    // per-animal-doc split.
    final animalsArray = [
      for (final animal in validAnimals)
        {
          'species': animal.speciesText,
          'breed': animal.breedText,
          'sex': animal.sex,
          'size': animal.size,
          'colorMarkings': animal.colorController.text.trim(),
          // Health & Behavior Assessment (spec) — per animal, never
          // collapsed into a shared/first-animal value.
          'bodyCondition': animal.bodyCondition,
          'mobility': animal.mobility,
          'alertness': animal.alertness,
          'eyesNoseMouth': animal.eyesNoseMouth,
          'skinAndCoat': animal.skinAndCoat,
          'appetiteHydration': animal.appetiteHydration,
          'behavior': animal.behavior.toList(),
          'environmentSafety': animal.environmentSafety.toList(),
          'biteRisk': animal.biteRisk,
          'escapeRisk': animal.escapeRisk,
        },
    ];

    final surrenderReasonValue =
        form.surrenderReason == 'Other (please specify)'
        ? 'Other: ${form.surrenderReasonOtherController.text.trim()}'
        : form.surrenderReason;

    final docRef = await casesCollection.add({
      'reporterId': uid,
      'reporterName': reporterName,
      'reporterPhone': userData?['phone'] ?? '',
      'animals': animalsArray,
      // Legacy singular fields, kept for any code path that hasn't been
      // migrated to read `animals[]` yet — mirrors the first animal,
      // same as every other reader's own fallback convention.
      'animalType': animalsArray.first['species'],
      'breed': animalsArray.first['breed'],
      'sex': animalsArray.first['sex'],
      'size': animalsArray.first['size'],
      'colorMarkings': animalsArray.first['colorMarkings'],
      'biteRisk': animalsArray.first['biteRisk'],
      'escapeRisk': animalsArray.first['escapeRisk'],
      'rescueType': form.selectedRescueType,
      'condition': condition,
      'urgency': form.selectedUrgency,
      if (!form.isPetSurrenderType) 'onSite': form.onSiteChoice,
      if (!form.isPetSurrenderType)
        'accessInstructions': form.accessInstructionsController.text.trim(),
      if (!form.isPetSurrenderType)
        'bestTimeToContact': form.bestTimeContactController.text.trim(),
      'reportAnonymously': form.selectedRescueType == 'Neglect or Abuse'
          ? form.reportAnonymously
          : false,
      'address': form.addressController.text.trim().isEmpty
          ? pinnedAddress
          : form.addressController.text.trim(),
      'lat': location.latitude,
      'lng': location.longitude,
      if (!form.isPetSurrenderType)
        'coordinateWithShelter': form.coordinateChoice,
      if (!form.isPetSurrenderType)
        'witnessName': form.witnessNameController.text.trim(),
      if (!form.isPetSurrenderType)
        'witnessPhone': form.witnessNumberController.text.trim(),
      if (!form.isPetSurrenderType) 'interestedToAdopt': form.adoptionChoice,
      // Pet Surrender's own question set — see SurrenderFields.
      if (form.isPetSurrenderType)
        'surrenderDuration': form.surrenderDurationController.text.trim(),
      if (form.isPetSurrenderType)
        'surrenderAge': form.surrenderAgeController.text.trim(),
      if (form.isPetSurrenderType) 'surrenderReason': surrenderReasonValue,
      if (form.isPetSurrenderType && form.surrenderNeedsExplanation)
        'surrenderExplanation': form.surrenderExplanationController.text.trim(),
      if (form.isPetSurrenderType)
        'petAcquisitionSource': form.petAcquisitionSource,
      'scannedTagId': form.scannedTagId,
      'status': 'pending',
      'statusHistory': [
        {
          'status': 'Rescue case is being reviewed.',
          'timestamp': Timestamp.now(),
        },
      ],
      'photoUrls': [],
      'createdAt': Timestamp.now(),
      'serverCreatedAt': FieldValue.serverTimestamp(),
    });

    final primaryCaseId = docRef.id;
    final media = await uploadMedia(
      form.mediaFiles,
      primaryCaseId,
      onProgress: onProgress,
    );
    if (media.photoUrls.isNotEmpty || media.videoUrls.isNotEmpty) {
      await casesCollection.doc(primaryCaseId).update({
        'photoUrls': media.photoUrls,
        'videoUrls': media.videoUrls,
      });
    }

    return primaryCaseId;
  }

  /// Creates the lost/found pet alert(s), optional linked rescue case,
  /// uploads media, and records possible matches. Returns how many
  /// possible matches were found (shown in the confirmation dialog).
  Future<int> submitLostPetReport({
    required RescueFormController form,
    required LatLng location,
    required String pinnedAddress,
    required String? lastSeenTimeLabel,
    required MediaUploadProgress onProgress,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data();
    final reporterName =
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();

    final alertsCollection = _db.collection('petAlerts');
    String? groupId;
    final createdDocIds = <String>[];
    String? linkedCaseId;

    if (form.isOwner == true) {
      final docRef = await alertsCollection.add({
        'type': 'lost',
        'groupId': null, // set to own id right after creation
        'reporterId': uid,
        'reporterName': reporterName,
        'contactNumber': form.ownerContactController.text.trim(),
        'petName': form.petNameController.text.trim(),
        'species': form.selectedAnimalType,
        'breed': form.lostBreedText,
        'sex': form.lostSex,
        'colorMarkings': form.lostColorController.text.trim(),
        'temperament': form.temperament,
        'offerReward': form.offerReward,
        'rewardAmount': form.offerReward
            ? form.rewardAmountController.text.trim()
            : null,
        'lastSeenDate': form.lastSeenDate != null
            ? Timestamp.fromDate(form.lastSeenDate!)
            : null,
        'lastSeenTime': lastSeenTimeLabel,
        'address': form.addressController.text.trim().isEmpty
            ? pinnedAddress
            : form.addressController.text.trim(),
        'lat': location.latitude,
        'lng': location.longitude,
        'scannedTagId': form.scannedTagId,
        'photoUrls': [],
        'status': 'open',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });
      groupId = docRef.id;
      createdDocIds.add(docRef.id);
      await docRef.update({'groupId': groupId});
    } else {
      // Optional linked rescue case if the finder needs pickup/medical help.
      if (form.finderNeedsRescue) {
        final caseRef = await _db.collection('cases').add({
          'reporterId': uid,
          'reporterName': reporterName,
          'reporterPhone': form.finderContactController.text.trim(),
          'animalType': form.foundAnimals.first.speciesText,
          'rescueType': 'Lost Pet',
          'condition': form.conditionController.text.trim(),
          'urgency': form.selectedUrgency,
          'address': form.addressController.text.trim().isEmpty
              ? pinnedAddress
              : form.addressController.text.trim(),
          'lat': location.latitude,
          'lng': location.longitude,
          'scannedTagId': form.scannedTagId,
          'status': 'pending',
          'statusHistory': [
            {
              'status':
                  'Suspected lost pet reported — awaiting pickup assignment.',
              'timestamp': Timestamp.now(),
            },
          ],
          'photoUrls': [],
          'createdAt': Timestamp.now(),
          'serverCreatedAt': FieldValue.serverTimestamp(),
        });
        linkedCaseId = caseRef.id;
      }

      for (int i = 0; i < form.foundAnimals.length; i++) {
        final a = form.foundAnimals[i];
        final docRef = await alertsCollection.add({
          'type': 'found',
          'groupId': groupId, // filled in after the first doc is created
          'reporterId': uid,
          'reporterName': reporterName,
          'contactNumber': form.finderContactController.text.trim(),
          'species': a.speciesText,
          'breed': a.breedText,
          'sex': a.sex,
          'size': a.size,
          'colorMarkings': a.colorController.text.trim(),
          'describeCondition': form.conditionController.text.trim(),
          'animalStatus': form.animalStatus,
          'needsRescue': form.finderNeedsRescue,
          'linkedCaseId': linkedCaseId,
          'address': form.addressController.text.trim().isEmpty
              ? pinnedAddress
              : form.addressController.text.trim(),
          'lat': location.latitude,
          'lng': location.longitude,
          'scannedTagId': form.scannedTagId,
          'photoUrls': [],
          'status': 'open',
          'createdAt': Timestamp.now(),
          'serverCreatedAt': FieldValue.serverTimestamp(),
        });
        groupId ??= docRef.id;
        createdDocIds.add(docRef.id);
      }
      // Backfill groupId on every doc in the group (first doc included).
      for (final id in createdDocIds) {
        await alertsCollection.doc(id).update({'groupId': groupId});
      }
    }

    // Media is shared across the whole group (same sighting/animal(s)).
    final media = await uploadMedia(
      form.mediaFiles,
      'lostpet_$groupId',
      onProgress: onProgress,
    );
    if (media.photoUrls.isNotEmpty || media.videoUrls.isNotEmpty) {
      for (final id in createdDocIds) {
        await alertsCollection.doc(id).update({
          'photoUrls': media.photoUrls,
          'videoUrls': media.videoUrls,
        });
      }
    }

    final oppositeType = form.isOwner == true ? 'found' : 'lost';
    final firstSpecies = form.isOwner == true
        ? form.selectedAnimalType
        : form.foundAnimals.first.speciesText;
    final candidates = await alertsCollection
        .where('type', isEqualTo: oppositeType)
        .where('status', isEqualTo: 'open')
        .where('species', isEqualTo: firstSpecies)
        .limit(20)
        .get();

    for (final candidate in candidates.docs) {
      final lostAlertId = form.isOwner == true ? groupId : candidate.id;
      final foundAlertId = form.isOwner == true ? candidate.id : groupId;
      final lostReporterId = form.isOwner == true
          ? uid
          : candidate['reporterId'];
      final foundReporterId = form.isOwner == true
          ? candidate['reporterId']
          : uid;

      await _db.collection('possibleMatches').add({
        'lostAlertId': lostAlertId,
        'foundAlertId': foundAlertId,
        'lostReporterId': lostReporterId,
        'foundReporterId': foundReporterId,
        'species': firstSpecies,
        'status': 'pending_review',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });
    }

    return candidates.docs.length;
  }
}
