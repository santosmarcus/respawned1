// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// Per-slot upload progress callback: [progress] is 0..1 while uploading
/// and null once that slot has finished.
typedef MediaUploadProgress = void Function(int slot, double? progress);

/// Firestore / Storage writes for the Report a Stray form. Moved verbatim
/// from the page: same collections (`users`, `cases`, `petAlerts`),
/// same document fields, same write order and same Storage paths.
/// Lost/found matches are scored server-side (scorePetAlertMatches in
/// functions/pet_matching.js), not here. Validation happens before these are called; any
/// exception propagates to the page, which shows it as before.
class RescueReportService {
  RescueReportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Uploads every non-empty media slot to `<folder>/<id>/media_<i>.<ext>`.
  /// [folder] is `cases` for rescue cases and `petAlerts` for lost/found
  /// pet alerts; storage.rules checks the matching Firestore doc's
  /// reporter, so the two must never be mixed.
  Future<({List<String> photoUrls, List<String> videoUrls})> uploadMedia(
      List<RescueMediaItem?> mediaFiles,
      String caseId, {
        required MediaUploadProgress onProgress,
        String folder = 'cases',
      }) async {
    // Every slot uploads at the same time (they used to go one after
    // another, so a report with several photos and a video waited for each
    // in turn). Results are collected per slot so the URL order still
    // follows the slots.
    Future<(bool, String)?> uploadSlot(int i) async {
      final item = mediaFiles[i];
      if (item == null) return null;

      final ext = item.isVideo ? 'mp4' : 'jpg';
      final ref = FirebaseStorage.instance.ref().child(
        '$folder/$caseId/media_$i.$ext',
      );

      final task = ref.putFile(
        File(item.file.path),
        SettableMetadata(
          contentType: item.isVideo ? 'video/mp4' : 'image/jpeg',
        ),
      );

      // Track upload progress for slot
      final progressSub = task.snapshotEvents.listen((snap) {
        onProgress(
          i,
          snap.bytesTransferred / (snap.totalBytes == 0 ? 1 : snap.totalBytes),
        );
      }, onError: (_) {});

      try {
        await task;
      } finally {
        await progressSub.cancel();
      }
      final url = await ref.getDownloadURL();
      onProgress(i, null);
      return (item.isVideo, url);
    }

    final results = await Future.wait([
      for (int i = 0; i < mediaFiles.length; i++) uploadSlot(i),
    ]);

    final photoUrls = <String>[];
    final videoUrls = <String>[];
    for (final r in results) {
      if (r == null) continue;
      (r.$1 ? videoUrls : photoUrls).add(r.$2);
    }

    return (photoUrls: photoUrls, videoUrls: videoUrls);
  }

  /// Uploads Pet Surrender vet record photos to
  /// `cases/<caseId>/vet_record_<i>.jpg` and returns their download URLs.
  Future<List<String>> uploadVetRecords(
      List<XFile> photos,
      String caseId,
      ) async {
    // In parallel, in order (Future.wait keeps the list order).
    return Future.wait([
      for (var i = 0; i < photos.length; i++)
            () async {
          final ref = FirebaseStorage.instance.ref().child(
            'cases/$caseId/vet_record_$i.jpg',
          );
          await ref.putFile(
            File(photos[i].path),
            SettableMetadata(contentType: 'image/jpeg'),
          );
          return ref.getDownloadURL();
        }(),
    ]);
  }

  /// Creates the rescue / surrender case (one doc for every animal), then
  /// uploads media and attaches the URLs. Returns the new case id.
  Future<String> submitRescueCase({
    required RescueFormController form,
    required LatLng location,
    required String pinnedAddress,
    ReportEvidence? evidence,
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
      for (final animal in validAnimals) animalDetailsMap(form, animal),
    ];

    final involvement = form.orgInvolvement;
    final assessment = form.urgencyAssessment;
    final asksOrg = form.asksOrgCoordination;

    final surrenderReasonValue =
    form.surrenderReason == 'Other (please specify)'
        ? 'Other: ${form.surrenderReasonOtherController.text.trim()}'
        : form.surrenderReason;

    final docRef = await casesCollection.add({
    // Not owned yet: the shared review pool (firestore.rules lets staff
    // query it by organizationId == '').
    'organizationId': '',
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
    // Assessed from the animals' answers (urgency_assessment.dart); none
    // for report types the organization does not triage.
    'urgency': assessment?.level,
    if (assessment != null)
    'urgencyAssessment': {
    ...assessment.toMap(),
    'assessedAt': FieldValue.serverTimestamp(),
    },
    'orgInvolvement': involvement.firestoreValue,
    if (form.isNeglectAbuseType) 'abuseReportPath': form.abuseReportPath,
    // Puppies from a litter reported on another case (LitterReportLink).
    'litterOf': ?form.litterLink?.toMap(),
    // Reporter-led path: what they have filed so far, from the "Reporting
    // to Authorities" answers; updated later from Track Case.
    if (form.isIndependentAbuseReport)
    'independentReport': {
    'alreadyReported': form.neglectReportedToAuthorities == 'Yes',
    if (form.neglectReportedToAuthorities == 'Yes')
    'referenceNumber': form.neglectReportReferenceController.text.trim(),
    'updatedAt': Timestamp.now(),
    },
    if (!form.isPetSurrenderType) 'onSite': form.onSiteChoice,
    if (!form.isPetSurrenderType)
    'accessInstructions': form.accessInstructionsController.text.trim(),
    if (!form.isPetSurrenderType)
    'bestTimeToContact': form.bestTimeContactController.text.trim(),
    if (form.asksCommunityCat && form.communityCat) 'communityCat': true,
    'reportAnonymously': form.selectedRescueType == 'Neglect or Abuse'
    ? form.reportAnonymously
        : false,
    'address': form.addressController.text.trim().isEmpty
    ? pinnedAddress
        : form.addressController.text.trim(),
    'lat': location.latitude,
    'lng': location.longitude,
    // Organization coordination answers: only asked when the reporter
    // wants the organization to act (not on surrenders or reporter-led
    // neglect/abuse reports).
    if (asksOrg) 'coordinateWithShelter': form.coordinateChoice,
    if (asksOrg) 'witnessName': form.witnessNameController.text.trim(),
    if (asksOrg) 'witnessPhone': form.witnessNumberController.text.trim(),
    if (asksOrg) 'interestedToAdopt': form.adoptionChoice,
    // Pet Surrender's own question set — see SurrenderFields.
    if (form.isPetSurrenderType) 'surrenderReason': surrenderReasonValue,
    if (form.isPetSurrenderType && form.surrenderNeedsExplanation)
    'surrenderExplanation': form.surrenderExplanationController.text.trim(),
    if (form.isPetSurrenderType)
    'surrenderTimeline': form.surrenderTimeline,
    // Neglect or Abuse follow-up answers — see NeglectAbuseFields.
    if (form.isNeglectAbuseType) 'neglectAbuse': {
    // "Other" is described in the report's own description.
    'observed': [for (final o in form.neglectObserved) o],
    'happeningNow': form.neglectHappeningNow,
    'ownerKnown': form.neglectOwnerKnown,
    if (form.neglectOwnerKnown == 'Yes')
    'ownerDetails': form.neglectOwnerDetailsController.text.trim(),
    'frequency': form.neglectFrequency,
    'reportedToAuthorities': form.neglectReportedToAuthorities,
    if (form.neglectReportedToAuthorities == 'Yes')
    'reportReference':
    form.neglectReportReferenceController.text.trim(),
    'willingWitness': form.neglectWillingWitness,
    },
    // Abandonment follow-up answers — see AbandonmentFields.
    if (form.isAbandonmentType) 'abandonment': {
    'duration': form.abandonmentDuration,
    'location': form.abandonmentLocation == kAbandonmentLocationOther
    ? 'Other: ${form.abandonmentLocationOtherController.text.trim()}'
        : form.abandonmentLocation,
    'hasFoodWater': form.abandonmentFoodWater,
    if (form.asksAbandonmentCanProvideFood)
    'canProvideFoodWater': form.abandonmentCanProvideFood,
    'witness': form.abandonmentWitness,
    'witnessDetails':
    form.abandonmentWitnessDetailsController.text.trim(),
    'belongingsLeft': form.abandonmentBelongings,
    if (form.abandonmentBelongings == 'Yes')
    'belongingsDetails':
    form.abandonmentBelongingsDetailsController.text.trim(),
    },
    // The reporter accepted the truthfulness declaration (rescue_page).
    'truthfulnessDeclaredAt': Timestamp.now(),
    'scannedTagId': form.scannedTagId,
    // A Pet Surrender goes straight to Community Adoption: the organization
    // does not facilitate surrenders, so it never waits in a review queue.
    'status': form.isPetSurrenderType ? kCommunityAdoptionStatus : 'pending',
    'statusHistory': [
    {
    'status': switch (involvement) {
    OrgInvolvement.orgAssist => 'Rescue case is being reviewed.',
    OrgInvolvement.independentReport =>
    'Report recorded. You chose to report this to the authorities '
    'yourself; the organization can see it and may assist if its '
    'capacity and coverage allow.',
    OrgInvolvement.notFacilitated =>
    'Your pet is now listed for Community Adoption. Interested adopters '
    'can reach you there; please keep caring for your pet in the '
    'meantime. You can withdraw this request at any time.',
    },
    'timestamp': Timestamp.now(),
    },
    ],
    'photoUrls': [],
    // How the report was made, for the staff's desk check.
    'reportEvidence': ?evidence?.toMap(),
    'createdAt': Timestamp.now(),
    'serverCreatedAt': FieldValue.serverTimestamp(),
    });

    final primaryCaseId = docRef.id;

    // A puppy report: list it on the mother's report, so rescuers see both.
    final link = form.litterLink;
    if (link != null) {
      try {
        await casesCollection.doc(link.parentCaseId).update({
          'litterReportCaseIds': FieldValue.arrayUnion([primaryCaseId]),
        });
      } catch (_) {
        // The puppy report itself is saved and carries litterOf either way.
      }
    }

    // Litter photos, per animal: cases/<id>/litter_<animal>_<n>.jpg.
    final litterPhotoUrls = <String, List<String>>{};
    for (var i = 0; i < validAnimals.length; i++) {
      final photos = validAnimals[i].asksLitterDetails ? validAnimals[i].litterPhotos : const <XFile>[];
      for (var n = 0; n < photos.length; n++) {
        final ref = FirebaseStorage.instance.ref().child('cases/$primaryCaseId/litter_${i}_$n.jpg');
        await ref.putFile(File(photos[n].path), SettableMetadata(contentType: 'image/jpeg'));
        (litterPhotoUrls['$i'] ??= []).add(await ref.getDownloadURL());
      }
    }
    if (litterPhotoUrls.isNotEmpty) {
      await casesCollection.doc(primaryCaseId).update({'litterPhotoUrls': litterPhotoUrls});
    }
    // Media and vet records upload side by side.
    final mediaFuture = uploadMedia(
    form.mediaFiles,
    primaryCaseId,
    onProgress: onProgress,
    );
    final vetFuture = form.isPetSurrenderType
    ? uploadVetRecords(form.vetRecordPhotos, primaryCaseId)
        : Future.value(const <String>[]);
    // Future.wait listens to both at once, so a failure in either one
    // surfaces here instead of as an unhandled error.
    final uploaded = await Future.wait<Object>([mediaFuture, vetFuture]);
    final media = uploaded[0] as ({List<String> photoUrls, List<String> videoUrls});
    final vetRecordUrls = uploaded[1] as List<String>;
    if (media.photoUrls.isNotEmpty ||
    media.videoUrls.isNotEmpty ||
    vetRecordUrls.isNotEmpty) {
    await casesCollection.doc(primaryCaseId).update({
    'photoUrls': media.photoUrls,
    'videoUrls': media.videoUrls,
    if (vetRecordUrls.isNotEmpty) 'vetRecordUrls': vetRecordUrls,
    });
    }

    return primaryCaseId;
  }

  /// Creates the lost/found pet alert(s) and uploads media. (No rescue
  /// case: the organization does not handle lost-pet reports.) Creating a petAlerts doc triggers
  /// scorePetAlertMatches (functions/pet_matching.js), which scores it
  /// against open reports and writes `possibleMatches`.
  Future<void> submitLostPetReport({
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
        // The pet's Health & Behavior Assessment and Bite Risk (same
        // fields as a found animal's, so the report page and matches can
        // show them side by side).
        'bodyCondition': form.lostAnimal.bodyCondition,
        'mobility': form.lostAnimal.mobility,
        'alertness': form.lostAnimal.alertness,
        'eyesNoseMouth': form.lostAnimal.eyesNoseMouth,
        'skinAndCoat': form.lostAnimal.skinAndCoat,
        'appetiteHydration': form.lostAnimal.appetiteHydration,
        'behavior': form.lostAnimal.behavior.toList(),
        'biteRisk': form.lostAnimal.biteRisk,
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
        // The registered collar tag this report is for (picked on the
        // form); the tag is marked lost and linked once the report exists.
        if (form.linkedCollarTag?.tagId != null) ...{
          'collarTagId': form.linkedCollarTag!.tagId,
          'source': 'collar_tag',
        },
        // The tag's photo until the report's own photos are uploaded (and
        // when none were added).
        'photoUrls': [
          if (form.hasLinkedTagPhoto) form.linkedCollarTag!.petImageUrl!,
        ],
        'status': 'open',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });
      groupId = docRef.id;
      createdDocIds.add(docRef.id);
      await docRef.update({'groupId': groupId});
    } else {
      for (int i = 0; i < form.foundAnimals.length; i++) {
        final a = form.foundAnimals[i];
        final docRef = await alertsCollection.add({
          'type': 'found',
          'groupId': groupId, // filled in after the first doc is created
          'reporterId': uid,
          'reporterName': reporterName,
          'contactNumber': form.finderContactController.text.trim(),
          // Everything from this animal's card: basic details, the Health
          // & Behavior Assessment and the risk fields (shown on the report
          // page and to staff of the linked case).
          ...animalDetailsMap(form, a),
          'animalStatus': form.animalStatus,
          // The organization does not handle lost-pet reports; an animal
          // needing help is filed as a rescue report instead (see
          // FinderFields). Kept for readers of older alerts.
          'needsRescue': false,
          'urgency': null,
          'linkedCaseId': null,
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
      await Future.wait([
        for (final id in createdDocIds)
          alertsCollection.doc(id).update({'groupId': groupId}),
      ]);
    }

    // Media is shared across the whole group (same sighting/animal(s)),
    // stored under the group's first alert, whose reporter is this user.
    // (It used to go to cases/lostpet_<id>, which storage.rules refuses
    // because no case doc has that id.)
    final media = await uploadMedia(
      form.mediaFiles,
      groupId!,
      onProgress: onProgress,
      folder: 'petAlerts',
    );
    if (media.photoUrls.isNotEmpty || media.videoUrls.isNotEmpty) {
      for (final id in createdDocIds) {
        await alertsCollection.doc(id).update({
          'photoUrls': media.photoUrls,
          'videoUrls': media.videoUrls,
        });
      }
    }

    // An owner who picked their registered pet: its collar tag goes lost
    // with the same pin and links this report, so anyone who scans the tag
    // (in the app or on the web page) can message the owner, and finding
    // the pet closes both.
    final tag = form.linkedCollarTag;
    if (form.isOwner == true && tag?.tagId != null) {
      await CollarTagLostFound.linkLostReport(
        tag!,
        alertId: groupId,
        lat: location.latitude,
        lng: location.longitude,
        address: form.addressController.text.trim().isEmpty
            ? pinnedAddress
            : form.addressController.text.trim(),
      );
    }
  }
}

/// One animal's answers from its card on the form (basic details, the
/// Health & Behavior Assessment and the risk fields), as saved on a rescue
/// case's `animals[]` entry and on each found-pet `petAlerts` doc.
Map<String, dynamic> animalDetailsMap(
    RescueFormController form,
    FoundAnimalEntry animal,
    ) => {
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
  // Not asked on Pet Surrender; drop any chips picked earlier
  // under another rescue type.
  'environmentSafety': form.isPetSurrenderType
      ? <String>[]
      : animal.environmentSafety.toList(),
  'biteRisk': animal.biteRisk,
  'escapeRisk': animal.escapeRisk,
  // Visible injury (reporter's description) and whether their photos show
  // it — the app does not analyze photos itself. Not asked on surrenders.
  if (!form.isPetSurrenderType) 'injury': animal.injury,
  if (!form.isPetSurrenderType && animal.asksInjuryPhotos)
    'injuryVisibleInPhotos': animal.injuryVisibleInPhotos,
  // Female only, and only the reporter's observation: never a confirmed
  // pregnancy.
  if (sexAllowsPregnancyQuestions(animal.sex)) ...{
    'hasLitter': animal.hasLitter,
    'suspectedPregnancy': animal.suspectedPregnancy,
  },
  // Injury, Illness, Neglect or Abuse — asked per animal.
  // A female dog's litter: count, places, condition (photos are uploaded
  // after the case exists, into litterPhotoUrls).
  'litter': ?animal.litterMap,
  if (form.asksVisibleSigns) ...{
    'visibleSigns': animal.visibleSigns.toList(),
    'needsMedical': animal.needsMedical,
  },
  // Pet Surrender — asked per animal inside its card.
  if (form.isPetSurrenderType) ...{
    'age': animal.ageController.text.trim(),
    'stayDuration': animal.stayDurationController.text.trim(),
    'acquisitionSource': animal.acquisitionSource,
    'vaccination': animal.vaccination,
    'spayNeuter': animal.spayNeuter,
    'compatibility': animal.compatibility.toList(),
  },
};

/// The Health & Behavior Assessment as one line of text, e.g.
/// "Body condition: Thin · Mobility: Limping · Behavior: Friendly", for
/// the `condition` of the rescue case a finder opens (the finder form has
/// no separate free-text condition).
String animalHealthSummary(FoundAnimalEntry a) {
  final parts = <String>[
    if (a.bodyCondition != null) 'Body condition: ${a.bodyCondition}',
    if (a.mobility != null) 'Mobility: ${a.mobility}',
    if (a.alertness != null) 'Alertness: ${a.alertness}',
    if (a.eyesNoseMouth != null) 'Eyes, nose, mouth: ${a.eyesNoseMouth}',
    if (a.skinAndCoat != null) 'Skin and coat: ${a.skinAndCoat}',
    if (a.appetiteHydration != null)
      'Appetite and hydration: ${a.appetiteHydration}',
    if (a.behavior.isNotEmpty) 'Behavior: ${a.behavior.join(', ')}',
  ];
  return parts.join(' · ');
}
