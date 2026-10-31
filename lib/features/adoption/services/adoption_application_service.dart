// Firestore / Storage reads and writes for the applicant's adoption flow,
// split out of adoption_process.dart (behavior-preserving refactor). The
// page keeps validation messages, busy flags and step changes; this class
// only moves data, using the exact same document shape as before.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  /// True when [animal] already has an application that isn't rejected or
  /// withdrawn. Checked by both keys: personal.animalId (legacy — matches
  /// older applications written before animalRecordId existed) and
  /// personal.animalRecordId (the real animal doc id, reliable for every
  /// application submitted after that fix). Neither alone is guaranteed to
  /// see every prior application for this exact animal.
  Future<bool> hasBlockingApplication(Animal animal) async {
    final legacyExisting = _adoptions
        .where('personal.animalId', isEqualTo: '${animal.id}')
        .get();
    final byRecordIdExisting = animal.animalRecordId.isEmpty
        ? Future.value(null)
        : _adoptions
              .where(
                'personal.animalRecordId',
                isEqualTo: animal.animalRecordId,
              )
              .get();
    final existingResults = await Future.wait([
      legacyExisting,
      byRecordIdExisting,
    ]);

    bool blocks(QuerySnapshot<Map<String, dynamic>>? snap) {
      if (snap == null) return false;
      return snap.docs.any((doc) {
        final status = doc.data()['status'] as String? ?? '';
        return status != 'rejected' && status != 'withdrawn';
      });
    }

    return blocks(existingResults[0]) || blocks(existingResults[1]);
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

    // Government ID / Proof of Address are the only two single-file
    // uploads left in this Future.wait — this list's length must always
    // match the two unpack lines directly below it. Home Photos is a
    // variable-length list and is uploaded separately via
    // _uploadHomePhotos precisely so it can never desync this fixed-size
    // unpack again (this positional mismatch — a disabled third upload
    // shrinking this list without the indices below being renumbered —
    // was the exact cause of the RangeError this replaces).
    final results = await Future.wait([
      _uploadFile(form.governmentIdFile, 'government_id', docRef.id),
      _uploadFile(form.proofOfAddressFile, 'proof_of_address', docRef.id),
      //_uploadFile(_digitalSignatureFile, 'digital_signature', docRef.id),
    ]);

    form.governmentIdUrl = results[0];
    form.proofOfAddressUrl = results[1];

    ///_digitalSignatureUrl = results[2];

    final newHomePhotoUrls = await _uploadHomePhotos(
      form.homePhotosFiles,
      docRef.id,
    );
    final homePhotoUrls = [...form.existingHomePhotoUrls, ...newHomePhotoUrls];

    // The application belongs to the organization that owns the animal.
    String? organizationId;
    if (animal.animalRecordId.isNotEmpty) {
      final animalSnap = await _db.collection('animals').doc(animal.animalRecordId).get();
      final orgId = animalSnap.data()?['organizationId'] as String?;
      if (orgId != null && orgId.isNotEmpty) organizationId = orgId;
    }

    await docRef.set({
      if (organizationId != null) 'organizationId': organizationId,
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
        'currentPets': {
          'dogs': form.currentDogs,
          'cats': form.currentCats,
          'birds': form.currentBirds,
          'fish': form.currentFish,
          'reptiles': form.currentReptiles,
          'other': form.currentOther,
          'otherType': form.currentOtherTypeCtrl.text.trim(),
        },
        'currentPetsVaccinated': form.petsVaccinated,
        'currentPetsSpayedNeutered': form.petsSpayedNeutered,
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

  Future<void> withdraw({
    required String adoptionId,
    required String animalRecordId,
  }) async {
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
      await AdoptionApplicationRepository().clearReservationOnWithdrawal(
        applicationId: adoptionId,
        animalId: animalRecordId,
      );
    }
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
