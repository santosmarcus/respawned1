import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';

/// Firestore access for the existing `adoptions` collection (written by
/// adoption_process.dart) plus the `animals` collection's reservation/
/// adopted fields — the admin Adoption Application Review module reuses
/// both rather than introducing a second application model. Reservation,
/// unreservation, and release all run as transactions across both
/// collections so two admins can never both reserve the same animal, and a
/// release can never target an animal that's already adopted.
class AdoptionApplicationRepository {
  AdoptionApplicationRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _adoptions => _db.collection('adoptions');
  CollectionReference<Map<String, dynamic>> get _animals => _db.collection('animals');
  DocumentReference<Map<String, dynamic>> _adoptionDoc(String id) => _adoptions.doc(id);
  CollectionReference<Map<String, dynamic>> _notesOf(String id) => _adoptionDoc(id).collection('notesLog');

  // ---- Reads --------------------------------------------------------

  Stream<AdoptionApplication?> streamApplication(String id) {
    return _adoptionDoc(id).snapshots().map((doc) => doc.exists ? AdoptionApplication.fromFirestore(doc) : null);
  }

  /// Every application whose raw `status` matches any of [statuses]'
  /// queryValues (canonical + legacy aliases — see AdoptionStatus). Client
  /// filters (sort/animal filter) apply on top, same pattern as
  /// RescueCaseRepository.streamCasesByStatuses.
  Stream<List<AdoptionApplication>> streamByStatuses(List<AdoptionStatus> statuses) {
    final values = statuses.expand((s) => s.queryValues).toSet().toList();
    if (values.isEmpty) return Stream.value(const []);
    return _adoptions
        .where('status', whereIn: values)
        .snapshots()
        .map((snap) => snap.docs.map(AdoptionApplication.fromFirestore).toList());
  }

  /// Every application, regardless of status — used for the Adopted tab's
  /// history and for full applicant-history lookups where status shouldn't
  /// filter anything out.
  Stream<List<AdoptionApplication>> streamAll() {
    return _adoptions.snapshots().map((snap) => snap.docs.map(AdoptionApplication.fromFirestore).toList());
  }

  /// Every application for one animal record — powers both the Animal
  /// Record's "View Applications" link and the review list's animal
  /// filter. Keyed by animalId (Firestore field `personal.animalId`), not
  /// by animal name.
  Stream<List<AdoptionApplication>> streamForAnimal(String animalId) {
    return _adoptions
        .where('personal.animalId', isEqualTo: animalId)
        .snapshots()
        .map((snap) => snap.docs.map(AdoptionApplication.fromFirestore).toList());
  }

  /// Every application from one applicant — Applicant History section.
  /// Keyed by UID (Firestore field `personal.adopterId`), never by name.
  Stream<List<AdoptionApplication>> streamForApplicant(String adopterId) {
    return _adoptions
        .where('personal.adopterId', isEqualTo: adopterId)
        .snapshots()
        .map((snap) => snap.docs.map(AdoptionApplication.fromFirestore).toList());
  }

  Stream<List<Map<String, dynamic>>> streamNotes(String applicationId) {
    return _notesOf(applicationId).orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  // ---- Interview ------------------------------------------------------

  Future<void> completeInterview({
    required String applicationId,
    required String actorUid,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'interviewCompletedAt': FieldValue.serverTimestamp(),
      'interviewCompletedBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Interview completed by $actorName.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  Future<void> markNoShow({
    required String applicationId,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'noShowAt': FieldValue.serverTimestamp(),
      'noShowBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Applicant marked as no-show by $actorName.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  // ---- Fit assessment (manual only — see FitAssessmentValue doc comment) --

  Future<void> setManualFitAssessment({
    required String applicationId,
    required FitAssessmentValue value,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'fitAssessment': {
        'value': value.name,
        'assessedBy': actorName,
        'assessedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  // ---- Notes (append-only audit trail) ---------------------------------

  Future<void> addNote({
    required String applicationId,
    required String text,
    required String actorUid,
    required String actorName,
  }) async {
    await _notesOf(applicationId).add({
      'text': text,
      'createdBy': actorName,
      'createdByUid': actorUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Accept / Reject --------------------------------------------------

  Future<void> accept({
    required String applicationId,
    required String actorUid,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'status': AdoptionStatus.approved.firestoreValue,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Application approved by $actorName.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  Future<void> reject({
    required String applicationId,
    required List<String> reasons,
    String? notes,
    required String actorUid,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'status': AdoptionStatus.rejected.firestoreValue,
      'rejectionReasons': reasons,
      if (notes != null && notes.isNotEmpty) 'rejectionNotes': notes,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Application rejected: ${reasons.join(', ')}.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  // ---- Reserve / Unreserve / Release (transactional) ---------------------

  /// Reserves the animal for this application's applicant. Blocks a second
  /// active reservation for the same animal (whether from this or another
  /// application) — the whole point of running this as a transaction.
  Future<void> reserve({
    required String applicationId,
    required String animalId,
  }) async {
    final appRef = _adoptionDoc(applicationId);
    final animalRef = _animals.doc(animalId);

    await _db.runTransaction((tx) async {
      final appSnap = await tx.get(appRef);
      final animalSnap = await tx.get(animalRef);
      if (!appSnap.exists) throw StateError('Application not found.');
      if (!animalSnap.exists) throw StateError('Animal record not found.');

      final appData = appSnap.data()!;
      final animalData = animalSnap.data()!;
      final adoptionStatus = animalData['adoptionStatus'] as String?;

      if (adoptionStatus == 'adopted') {
        throw StateError('This animal has already been adopted.');
      }
      if (adoptionStatus == 'reserved' && animalData['reservedApplicationId'] != applicationId) {
        throw StateError('This animal is already reserved for another applicant.');
      }

      final now = Timestamp.now();
      tx.update(animalRef, {
        'adoptionStatus': 'reserved',
        'reservedForUserId': appData['personal']?['adopterId'],
        'reservedApplicationId': applicationId,
        'reservedAt': now,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(appRef, {
        'reservedAt': now,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Animal reserved for this applicant.', 'timestamp': now}
        ]),
      });
    });
  }

  /// Clears only the reservation that matches [applicationId] — never
  /// another applicant's. Returns the animal to 'adoptable'. The
  /// application itself is untouched (stays approved).
  Future<void> unreserve({
    required String applicationId,
    required String animalId,
  }) async {
    final appRef = _adoptionDoc(applicationId);
    final animalRef = _animals.doc(animalId);

    await _db.runTransaction((tx) async {
      final animalSnap = await tx.get(animalRef);
      if (!animalSnap.exists) return;
      final animalData = animalSnap.data()!;
      if (animalData['reservedApplicationId'] != applicationId) {
        // Already unreserved, or reserved by a different application by
        // now — nothing for this call to safely undo.
        return;
      }

      tx.update(animalRef, {
        'adoptionStatus': 'adoptable',
        'reservedForUserId': FieldValue.delete(),
        'reservedApplicationId': FieldValue.delete(),
        'reservedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final now = Timestamp.now();
      tx.update(appRef, {
        'reservedAt': FieldValue.delete(),
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Reservation cleared.', 'timestamp': now}
        ]),
      });
    });
  }

  /// The actual adoption handoff — application must already be approved,
  /// and the animal must not already be adopted. Clears any reservation as
  /// part of the same write (adoption supersedes it).
  Future<void> release({
    required String applicationId,
    required String animalId,
    required String actorName,
    String? notes,
  }) async {
    final appRef = _adoptionDoc(applicationId);
    final animalRef = _animals.doc(animalId);

    await _db.runTransaction((tx) async {
      final appSnap = await tx.get(appRef);
      final animalSnap = await tx.get(animalRef);
      if (!appSnap.exists) throw StateError('Application not found.');
      if (!animalSnap.exists) throw StateError('Animal record not found.');

      final appData = appSnap.data()!;
      final animalData = animalSnap.data()!;

      final appStatus = AdoptionStatus.fromFirestoreValue(appData['status'] as String?);
      if (appStatus != AdoptionStatus.approved) {
        throw StateError('Only an approved application can be released.');
      }
      if (animalData['adoptionStatus'] == 'adopted') {
        throw StateError('This animal has already been adopted.');
      }

      final now = Timestamp.now();
      final adopterId = appData['personal']?['adopterId'];

      tx.update(animalRef, {
        'adoptionStatus': 'adopted',
        'status': 'adopted',
        'adoptedByUserId': adopterId,
        'adoptedApplicationId': applicationId,
        'adoptedAt': now,
        'reservedForUserId': FieldValue.delete(),
        'reservedApplicationId': FieldValue.delete(),
        'reservedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(appRef, {
        'status': AdoptionStatus.adopted.firestoreValue,
        'adoptedAt': now,
        'releasedBy': actorName,
        if (notes != null && notes.isNotEmpty) 'releaseNotes': notes,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Animal released — adoption completed.', 'timestamp': now}
        ]),
      });
    });
  }

  /// Called from the user-side withdrawal flow (adoption_process.dart) —
  /// if the withdrawn application had reserved the animal, safely clears
  /// that reservation so it becomes available again. A no-op if it wasn't
  /// reserved, or if withdrawal happens after release (that's flagged for
  /// manual resolution instead of being auto-reversed — see the class doc
  /// comment on why release is never automatically undone).
  Future<void> clearReservationOnWithdrawal({
    required String applicationId,
    required String animalId,
  }) async {
    final animalRef = _animals.doc(animalId);
    await _db.runTransaction((tx) async {
      final animalSnap = await tx.get(animalRef);
      if (!animalSnap.exists) return;
      final animalData = animalSnap.data()!;
      if (animalData['reservedApplicationId'] != applicationId) return;
      if (animalData['adoptionStatus'] == 'adopted') return; // already released — do not reverse
      tx.update(animalRef, {
        'adoptionStatus': 'adoptable',
        'reservedForUserId': FieldValue.delete(),
        'reservedApplicationId': FieldValue.delete(),
        'reservedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
