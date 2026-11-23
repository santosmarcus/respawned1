// Firestore / Storage reads and writes for the applicant's adoption flow,
// split out of adoption_process.dart (behavior-preserving refactor). The
// page keeps validation messages, busy flags and step changes; this class
// only moves data, using the exact same document shape as before.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:respawnd1/core/utils/user_autofill.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';

class AdoptionApplicationService {
  AdoptionApplicationService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore,
        _storage = storage,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  // Resolved lazily (same as the original direct `.instance` calls) so
  // constructing the service never touches Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _st => _storage ?? FirebaseStorage.instance;
  FirebaseAuth get _au => _auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _adoptions =>
      _db.collection('adoptions');

  String? get currentUserEmail => _au.currentUser?.email;

  /// The signed-in user's `users/{uid}` doc, or null when signed out or
  /// missing.
  Future<Map<String, dynamic>?> fetchCurrentUserProfile() async {
    final uid = _au.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<Map<String, dynamic>?> fetchApplication(String id) async {
    final doc = await _adoptions.doc(id).get();
    return doc.data();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchApplication(String id) =>
      _adoptions.doc(id).snapshots();

  /// Why [animal] can't take a new application from the signed-in user
  /// ('reserved', 'adopted' or 'unavailable'), or null when it can. Other
  /// people's open applications never block: staff choose between
  /// applicants, and only a reservation or completed adoption closes the
  /// animal. The animal record and other applications aren't readable from
  /// the client (firestore.rules), so the hasBlockingAdoption callable
  /// (functions/adoptions.js) checks and returns only the reason.
  Future<String?> blockingReason(Animal animal) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('hasBlockingAdoption')
        .call<Object?>({
      'animalId': '${animal.id}',
      'animalRecordId': animal.animalRecordId,
    });
    final data = result.data;
    if (data is! Map || data['blocked'] != true) return null;
    return data['reason'] as String? ?? 'unavailable';
  }

  //upload helper
  Future<String?> _uploadFile(
      File? file,
      String pathSegment,
      String adoptionId,
      ) async {
    if (file == null) return null;
    final ref = _st.ref('adoptions/$adoptionId/$pathSegment.jpg');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Uploads every picked Home Photo (any count — no fixed maximum) in
  /// parallel and returns the resulting URLs in the same order the files
  /// were picked. Kept entirely separate from _uploadFile's single-file
  /// Future.wait list on purpose: unpacking a variable-length upload by a
  /// fixed position is exactly what caused the RangeError this replaces.
  Future<List<String>> _uploadHomePhotos(
      List<File> files,
      String adoptionId,
      ) async {
    if (files.isEmpty) return const [];
    final urls = await Future.wait([
      for (var i = 0; i < files.length; i++)
            () async {
          final ref = _st.ref('adoptions/$adoptionId/home_photos/img_$i.jpg');
          await ref.putFile(files[i]);
          return ref.getDownloadURL();
        }(),
    ]);
    return urls;
  }

  /// Uploads the form's files and creates the application doc. Writes the
  /// uploaded ID / proof-of-address URLs back onto [form] (as before) and
  /// returns the new application id.
  Future<String> submitApplication({
    required Animal animal,
    required AdoptionFormController form,
  }) async {
    final uid = _au.currentUser!.uid;
    final docRef = _adoptions.doc();

    // Government ID is the only single-file upload. (Proof of Address is
    // no longer asked for.) Home Photos is a variable-length list,
    // uploaded separately via _uploadHomePhotos.
    final governmentIdUrl =
        await _uploadFile(form.governmentIdFile, 'government_id', docRef.id);

    // Nothing newly picked: keep the file uploaded in an earlier session.
    form.governmentIdUrl = governmentIdUrl ?? form.governmentIdUrl;

    ///_digitalSignatureUrl = results[2];

    final newHomePhotoUrls = await _uploadHomePhotos(
      form.homePhotosFiles,
      docRef.id,
    );
    final homePhotoUrls = [...form.existingHomePhotoUrls, ...newHomePhotoUrls];

    // The application belongs to the organization that owns the animal.
    String? organizationId;
    if (animal.animalRecordId.isNotEmpty) {
      final animalSnap = await _db.collection('publicAnimals').doc(animal.animalRecordId).get();
      final orgId = animalSnap.data()?['organizationId'] as String?;
      if (orgId != null && orgId.isNotEmpty) organizationId = orgId;
    }

    // So the next form that asks for an address can fill it in.
    UserAutofill.rememberAddress(form.homeAddressCtrl.text);

    await docRef.set({
    'organizationId': ?organizationId,
    'personal': {
    'adopterId': uid,
    // Legacy join key — a stringified stableIntIdFor hash, kept only
    // for matching against applications written the same way before
    // animalRecordId existed. Never reliably reversible to a real
    // animals/{id} doc; see AdoptionProcess's class doc comment.
    'animalId': '${animal.id}',
    // The real animals/{id} Firestore document id — the reliable join
    // key going forward for admin-side "View Applications" and any
    // other lookup that needs to resolve back to the actual
    // AnimalRecord. Omitted (not written as '') if unavailable.
    if (animal.animalRecordId.isNotEmpty)
    'animalRecordId': animal.animalRecordId,
    'animalName': animal.name,
    'adopterName': form.nameCtrl.text.trim(),
    'adopterEmail': form.emailCtrl.text.trim(),
    'adopterAge': form.ageCtrl.text.trim(),
    'adopterPhone': form.phoneCtrl.text.trim(),
    'homeAddress': form.homeAddressCtrl.text.trim(),
    'homeLat': ?form.homeLat,
    'homeLng': ?form.homeLng,
    // Legacy field kept for backward compatibility with older reads.
    'adopterCity': form.homeAddressCtrl.text.trim(),
    },
    'household': {
    'residenceType': form.residenceType,
    'residenceOther': form.residenceType == 'Other'
    ? form.residenceOtherCtrl.text.trim()
        : null,
    'ownershipStatus': form.ownershipStatus,
    'householdMembers': form.householdMembers,
    },
    'petExperience': {
    'hadPetsBefore': form.hadPetsBefore,
    'hasCurrentPets': form.hasCurrentPets,
    'currentPets': {
    'dogs': form.currentDogs,
    'cats': form.currentCats,
    'birds': form.currentBirds,
    'fish': form.currentFish,
    'reptiles': form.currentReptiles,
    'other': form.currentOther,
    'otherType': form.currentOtherTypeCtrl.text.trim(),
    },
    // No current pets: the two questions weren't asked.
    'currentPetsVaccinated': form.hasCurrentPets ? form.petsVaccinated : 'Not Applicable',
    'currentPetsSpayedNeutered': form.hasCurrentPets ? form.petsSpayedNeutered : 'Not Applicable',
    },
    'lifestyle': {
    'hoursAlone': form.hoursAlone,
    'primaryCaregiver': form.primaryCaregiver,
    'petStayLocation': form.petStayLocation,
    'canAfford': {
    'food': form.canAffordFood,
    'vaccinations': form.canAffordVaccinations,
    'vetVisits': form.canAffordVetVisits,
    'emergencyMedicalCare': form.canAffordEmergencyCare,
    'grooming': form.canAffordGrooming,
    'careSupplies': form.canAffordCareSupplies,
    },
    },
    'uploads': {
    'governmentId': form.governmentIdUrl,
    // No longer asked for; only carried over from an application resumed
    // from an earlier session that already had one.
    if ((form.proofOfAddressUrl ?? '').isNotEmpty)
    'proofOfAddress': form.proofOfAddressUrl,
    //'digitalSignature': _digitalSignatureUrl,
    // A list, not a single URL — every uploaded home photo is kept,
    // never overwritten by only the most recent one. The admin
    // Required Documents reader already accepts either shape.
    'homePhotos': homePhotoUrls,
    },
    'agreement': {
    'reason': form.reasonCtrl.text.trim(),
    'care': form.agreeCare,
    'noAbandon': form.agreeNoAbandon,
    'followUp': form.agreeFollowup,
    'infoAccurate': form.agreeAccurate,
    'approvalNotGuaranteed': form.agreeNotGuaranteed,
    },
    'status': 'pending',
    'statusHistory': [
    {'status': 'Form submitted.', 'timestamp': Timestamp.now()},
    ],
    'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  Future<void> saveAppointment(String adoptionId, AdoptionFormController form) {
    return _adoptions.doc(adoptionId).update({
      'appointmentType': form.appointmentType,
      'appointmentDate': Timestamp.fromDate(form.appointmentDate!),
      'appointmentTime': form.appointmentTime,
      // Deliberately NOT writing 'status' here — the application stays
      // Pending (whatever it already was) until the admin's Confirm
      // Interview action moves it into Interview. This used to jump
      // straight to 'interview' the moment the applicant booked a slot,
      // skipping the admin confirmation step entirely.
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Appointment booked.', 'timestamp': Timestamp.now()},
      ]),
    });
  }

  /// Before release the application is withdrawn. After release the
  /// animal is already home with the adopter, so a withdrawal is really a
  /// return (Adoption gap 8): it opens the return procedure as an
  /// adopter-requested return and returns true. Staff then approve it,
  /// schedule the retrieval and take the animal back through Intake, as for
  /// any other return.
  Future<bool> withdraw({
    required String adoptionId,
    required String animalRecordId,
  }) async {
    final repo = AdoptionApplicationRepository();
    final current = (await _adoptions.doc(adoptionId).get()).data() ?? const <String, dynamic>{};
    if (current['status'] == 'adopted' || current['releasedAt'] != null) {
      // A return already in progress isn't opened twice.
      final open = current['returnRequest'];
      if (open is Map && !['declined', 'cancelled', 'intake'].contains(open['status'])) return true;
      await repo.requestReturn(
        applicationId: adoptionId,
        reason: 'Other',
        reasonOther: 'Withdrew after release',
        urgency: 'Within 1 Week',
        explanation: 'The adopter withdrew the adoption after the animal was released to them.',
        images: const [],
        actorUid: _au.currentUser?.uid ?? '',
      );
      return true;
    }
    await _adoptions.doc(adoptionId).update({
      'status': 'withdrawn',
      'withdrawnAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Application withdrawn by adopter.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });

    // If this application had reserved the animal, safely release that
    // reservation so it becomes available again — never touches an
    // already-completed release (see the repository method's own doc
    // comment on why that's flagged for manual resolution instead).
    // Must be the real animals/{id} doc id (animalRecordId) — this is a
    // direct document lookup, not a query, so the stringified
    // stableIntIdFor hash (Animal.id) would never resolve to the actual
    // animal document and this call would silently no-op.
    if (animalRecordId.isNotEmpty) {
      await repo.clearReservationOnWithdrawal(
        applicationId: adoptionId,
        animalId: animalRecordId,
      );
    }
    // Adoption gap 7.
    await repo.logAdopterWithdrawal(adoptionId);
    return false;
  }

  Future<void> requestDeliveryReschedule({
    required String adoptionId,
    required int nextAttempt,
    required int maxAttempts,
  }) {
    return _adoptions.doc(adoptionId).update({
      'deliveryAttempts': nextAttempt,
      'rescheduleRequested': true,
      'rescheduleRequestedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':
          'Adopter requested a delivery reschedule (attempt $nextAttempt of $maxAttempts).',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
  }
}
