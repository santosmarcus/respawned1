import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/adoption/follow_up_schedule.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';

/// Result of [AdoptionApplicationRepository.checkAvailability] — what a
/// prospective adopter should see/do right now for a given animal.
enum AnimalAdoptionAvailability {
  /// Free to submit a brand-new application.
  available,

  /// The current user already has their own active (non-rejected, non-
  /// withdrawn) application for this animal — resume it, don't duplicate.
  ownApplicationActive,

  /// `animals/{id}.adoptionStatus == 'reserved'` for a DIFFERENT applicant.
  reservedForOther,

  /// `animals/{id}.adoptionStatus == 'adopted'`.
  adopted,

  /// Not reserved/adopted, but also not currently open for applications
  /// (e.g. still `not_ready`, archived, or the animal doc is missing).
  unavailable,
}

class AnimalAvailabilityResult {
  final AnimalAdoptionAvailability availability;

  /// Set only when [availability] is [AnimalAdoptionAvailability.
  /// ownApplicationActive] — the existing `adoptions/{id}` to resume.
  final String? ownApplicationId;

  const AnimalAvailabilityResult(this.availability, {this.ownApplicationId});
}

/// Firestore access for the existing `adoptions` collection (written by
/// adoption_process.dart) plus the `animals` collection's reservation/
/// adopted fields — the admin Adoption Application Review module reuses
/// both rather than introducing a second application model. Reservation,
/// unreservation, and release all run as transactions across both
/// collections so two admins can never both reserve the same animal, and a
/// release can never target an animal that's already adopted.
///
/// Release/follow-up/return methods (added for the Adoption Release &
/// Post-Adoption Follow-up & Animal Return module) follow the exact same
/// shape: guard reads, then a transaction wherever more than one doc is
/// touched. Follow-up scheduling state lives on the adoption doc itself
/// (`followUpSchedules`) and its `followUps` subcollection; return state
/// lives in the adoption doc's `returnRequest` map — see
/// core/models/adoption/{follow_up_schedule,follow_up_record,
/// return_request}.dart for the field shapes.
class AdoptionApplicationRepository {
  AdoptionApplicationRepository({
    FirebaseFirestore? firestore,
    AnimalRecordRepository? animalRecordRepository,
    RescueCaseRepository? rescueCaseRepository,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _animalRepo = animalRecordRepository ?? AnimalRecordRepository(firestore: firestore),
        _caseRepo = rescueCaseRepository ?? RescueCaseRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final AnimalRecordRepository _animalRepo;
  final RescueCaseRepository _caseRepo;

  CollectionReference<Map<String, dynamic>> get _adoptions => _db.collection('adoptions');
  CollectionReference<Map<String, dynamic>> get _animals => _db.collection('animals');
  DocumentReference<Map<String, dynamic>> _adoptionDoc(String id) => _adoptions.doc(id);
  CollectionReference<Map<String, dynamic>> _notesOf(String id) => _adoptionDoc(id).collection('notesLog');
  CollectionReference<Map<String, dynamic>> _followUpsOf(String id) => _adoptionDoc(id).collection('followUps');
  CollectionReference<Map<String, dynamic>> _warningsOf(String id) => _adoptionDoc(id).collection('warnings');

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
    // Same diagnostic as RescueCaseRepository.streamCasesByStatuses — see
    // its comment for why this matters even though rules are wide open.
    debugPrint('[AdoptionApplicationRepository] projectId=${Firebase.app().options.projectId} '
        'uid=${FirebaseAuth.instance.currentUser?.uid} statuses=$values');
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
  /// filter. [animalRecordId] must be the real `animals/{id}` Firestore
  /// document id (see AdoptionApplication's own doc comment) — deliberately
  /// queries `personal.animalRecordId`, never the legacy `personal.animalId`
  /// (a stringified hash or pre-migration catalog int that never equals a
  /// real document id), so this only ever returns applications submitted
  /// after animalRecordId started being written. Older applications for the
  /// same animal won't surface here; there is no reliable way to reverse
  /// their legacy animalId back into this animal's real id.
  Stream<List<AdoptionApplication>> streamForAnimal(String animalRecordId) {
    return _adoptions
        .where('personal.animalRecordId', isEqualTo: animalRecordId)
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

  /// Whether a NEW application can be submitted right now for this animal,
  /// and what to tell the user if not — the single source of truth for
  /// both the "Adopt" tap gate (animal_page.dart) and the actual submit
  /// gate (adoption_process.dart), replacing two independent, incorrect
  /// copies that used to block a new applicant merely because *any* other
  /// non-terminal application existed for the animal (regardless of who
  /// owned it, and regardless of whether the animal was ever actually
  /// reserved/adopted).
  ///
  /// Correct rule: multiple people may have pending/interview/under-review
  /// applications for the same animal simultaneously — only the animal's
  /// own `animals/{id}.adoptionStatus` (set exclusively by [reserve]/
  /// [release]/[releaseWithFollowUps], all transactional) determines
  /// whether it's actually taken. [legacyAnimalId] is only ever consulted
  /// as a fallback join key for pre-animalRecordId applications, never as
  /// the primary availability signal.
  Future<AnimalAvailabilityResult> checkAvailability({
    required String legacyAnimalId,
    required String animalRecordId,
    required String uid,
  }) async {
    // "Active" here deliberately excludes the terminal-success statuses too
    // (completed/return_requested/return_approved) — those are handled by
    // the caller's own post-adoption routing (see animal_page.dart's
    // myCompletedDoc), not by this "should I resume an in-progress form"
    // check.
    bool isActive(String status) =>
        status != 'rejected' &&
        status != 'withdrawn' &&
        status != 'completed' &&
        status != 'return_requested' &&
        status != 'return_approved';

    // 1. Does the CURRENT user already have their own active application
    // for this exact animal? If so, that takes priority over anything
    // else — they should resume it, never start a second one.
    final legacyFuture = _adoptions
        .where('personal.animalId', isEqualTo: legacyAnimalId)
        .where('personal.adopterId', isEqualTo: uid)
        .get();
    final byRecordFuture = animalRecordId.isEmpty
        ? Future<QuerySnapshot<Map<String, dynamic>>?>.value(null)
        : _adoptions
            .where('personal.animalRecordId', isEqualTo: animalRecordId)
            .where('personal.adopterId', isEqualTo: uid)
            .get();
    final ownResults = await Future.wait([legacyFuture, byRecordFuture]);

    for (final snap in ownResults) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        final status = doc.data()['status'] as String? ?? '';
        if (isActive(status)) {
          return AnimalAvailabilityResult(AnimalAdoptionAvailability.ownApplicationActive, ownApplicationId: doc.id);
        }
      }
    }

    // 2. No animalRecordId to check against (very old/legacy submission
    // path) — nothing further to gate on; allow it through rather than
    // blocking on missing data.
    if (animalRecordId.isEmpty) {
      return const AnimalAvailabilityResult(AnimalAdoptionAvailability.available);
    }

    // 3. The animal's own authoritative state — this is what [reserve]
    // actually checks/sets transactionally, so it's the only thing that
    // can genuinely make the animal unavailable to a new applicant.
    final animalSnap = await _animals.doc(animalRecordId).get();
    final animalData = animalSnap.data();
    if (animalData == null) {
      return const AnimalAvailabilityResult(AnimalAdoptionAvailability.unavailable);
    }
    if (animalData['archived'] == true) {
      return const AnimalAvailabilityResult(AnimalAdoptionAvailability.unavailable);
    }

    final adoptionStatus = animalData['adoptionStatus'] as String?;
    switch (adoptionStatus) {
      case 'adopted':
        return const AnimalAvailabilityResult(AnimalAdoptionAvailability.adopted);
      case 'reserved':
        return const AnimalAvailabilityResult(AnimalAdoptionAvailability.reservedForOther);
      case 'adoptable':
        return const AnimalAvailabilityResult(AnimalAdoptionAvailability.available);
      default:
        // 'not_ready' or any unrecognized/missing value — not currently
        // open for applications, but not reserved/adopted either.
        return const AnimalAvailabilityResult(AnimalAdoptionAvailability.unavailable);
    }
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

  /// Admin confirms the interview the applicant booked — moves the
  /// application from Pending into Interview. New applications (and a
  /// freshly-booked appointment) stay Pending until this runs; the user's
  /// own Book Appointment step only ever saves appointmentDate/Time/Type,
  /// it never sets status itself (see adoption_process.dart's
  /// _saveAppointment).
  Future<void> confirmInterview({
    required String applicationId,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'status': AdoptionStatus.interview.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Interview confirmed by organization.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  /// Admin-side interview reschedule — edits the SAME appointment fields
  /// the user's own Book Appointment step writes (appointmentDate/Time/
  /// Type), never a second/parallel schedule. Preserves the original
  /// application `createdAt`/submission date untouched, and never touches
  /// release/adoption scheduling fields (scheduledReleaseDate etc.) — those
  /// are a deliberately separate schedule.
  Future<void> rescheduleInterview({
    required String applicationId,
    required DateTime date,
    required String time,
    required String type,
    required String actorName,
  }) async {
    await _adoptionDoc(applicationId).update({
      'appointmentDate': Timestamp.fromDate(date),
      'appointmentTime': time,
      'appointmentType': type,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Interview rescheduled by organization.', 'timestamp': Timestamp.now()}
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

  /// Same append-only pattern as [addNote], but explicitly flagged private
  /// so it's unambiguous in the audit trail that this was never surfaced
  /// to the adopter (the Post-Adoption Details "Add Note" action, spec
  /// §4). Reads back from the same `notesLog` subcollection/[streamNotes]
  /// as [addNote] — callers distinguish private notes via the `private`
  /// flag, not a separate collection.
  Future<void> addPrivateNote({
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
      'private': true,
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

  // ---- Follow-up reads -------------------------------------------------

  Stream<List<FollowUpRecord>> streamFollowUps(String applicationId) {
    return _followUpsOf(applicationId).orderBy('sequenceNumber').snapshots().map(
          (snap) => snap.docs.map(FollowUpRecord.fromFirestore).toList(),
    );
  }

  /// Every follow-up across every application that is overdue right now —
  /// "overdue" here is [FollowUpRecord.displayStatus]'s own existing
  /// definition (past its own [FollowUpRecord.scheduledDate] while still
  /// scheduled/reminderSent), never an invented admin-configurable window.
  /// Filters to the two non-terminal statuses server-side (a follow-up
  /// that's completed/cancelled/submitted/confirmed can never be "overdue"),
  /// then the actual date comparison client-side, so this stays a bounded
  /// read of only-still-open follow-ups rather than the whole collection
  /// group.
  Stream<List<FollowUpRecord>> streamOverdueFollowUps() {
    return _db
        .collectionGroup('followUps')
        .where('status', whereIn: [FollowUpStatus.scheduled.name, FollowUpStatus.reminderSent.name])
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map(FollowUpRecord.fromFirestore)
          .where((f) => f.displayStatus(now) == 'Overdue')
          .toList();
    });
  }

  // ---- Release Details (pre-release) ------------------------------------

  Future<void> setScheduledReleaseDate({required String applicationId, required DateTime date}) async {
    await _adoptionDoc(applicationId).update({'scheduledReleaseDate': Timestamp.fromDate(date)});
  }

  /// Persists the draft schedule-rule configuration so it survives closing
  /// and reopening Release Details, before the animal is actually released
  /// (spec §3/§6). The same field is reused as the final record once
  /// released — see [releaseWithFollowUps].
  Future<void> saveFollowUpScheduleDraft({
    required String applicationId,
    required List<FollowUpScheduleRule> rules,
    required bool noFollowUpsPlanned,
  }) async {
    await _adoptionDoc(applicationId).update({
      'followUpSchedules': rules.map((r) => r.toMap()).toList(),
      'noFollowUpsPlanned': noFollowUpsPlanned,
    });
  }

  /// The real Release + follow-up-generation transaction. Validates the
  /// same preconditions as [release] (approved application, animal not
  /// already adopted) plus the two new guards spec §6 asks for (animal not
  /// reserved for a different application; a valid, non-empty follow-up
  /// schedule unless [noFollowUpsPlanned] is explicitly set), then writes
  /// the animal/application release fields and materializes one
  /// `followUps/{id}` doc per generated date in the same transaction so the
  /// application, animal, and follow-up records can never end up
  /// inconsistent with each other.
  Future<void> releaseWithFollowUps({
    required String applicationId,
    required String animalId,
    required String actorName,
    required DateTime releaseDate,
    required List<FollowUpScheduleRule> rules,
    bool noFollowUpsPlanned = false,
    String? notes,
  }) async {
    if (!noFollowUpsPlanned) {
      if (rules.isEmpty) {
        throw StateError('Add at least one follow-up schedule, or turn on "No follow-ups needed".');
      }
      for (final r in rules) {
        if (r.intervalValue <= 0 || r.durationValue <= 0) {
          throw StateError('Every follow-up schedule needs a positive interval and duration.');
        }
      }
    }

    final generated = noFollowUpsPlanned ? const <GeneratedFollowUpDate>[] : generateFollowUpDates(rules, releaseDate);
    if (!noFollowUpsPlanned && generated.isEmpty) {
      throw StateError('This follow-up schedule produced no dates — check each rule\'s interval and duration.');
    }

    final appRef = _adoptionDoc(applicationId);
    final animalRef = _animals.doc(animalId);
    final followUpRefs = [for (var i = 0; i < generated.length; i++) _followUpsOf(applicationId).doc()];

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
      if (animalData['adoptionStatus'] == 'reserved' && animalData['reservedApplicationId'] != applicationId) {
        throw StateError('This animal is reserved for a different applicant.');
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
        'scheduledReleaseDate': Timestamp.fromDate(releaseDate),
        'releasedAt': now,
        'adoptedAt': now,
        'releasedBy': actorName,
        // Delivery attempt tracking (spent by the adopter's own Request
        // Reschedule action — see AdoptionProcess._requestDeliveryReschedule)
        // starts fresh at every release, since this is the first time a
        // delivery is actually scheduled for this application.
        'deliveryAttempts': 0,
        'rescheduleRequested': false,
        if (notes != null && notes.isNotEmpty) 'releaseNotes': notes,
        'followUpSchedules': rules.map((r) => r.toMap()).toList(),
        'noFollowUpsPlanned': noFollowUpsPlanned,
        'postAdoptionStatus': noFollowUpsPlanned ? 'completed' : 'inProgress',
        if (noFollowUpsPlanned) 'postAdoptionCompletedAt': now,
        if (noFollowUpsPlanned) 'postAdoptionCompletedBy': actorName,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Animal released — adoption completed.', 'timestamp': now}
        ]),
      });

      for (var i = 0; i < generated.length; i++) {
        tx.set(followUpRefs[i], {
          'sequenceNumber': i + 1,
          'scheduledDate': Timestamp.fromDate(generated[i].date),
          'status': FollowUpStatus.scheduled.name,
          'scheduleRuleId': generated[i].ruleId,
          'reminderCount': 0,
          'createdAt': now,
        });
      }
    });
  }

  // ---- Post-Adoption follow-up review ------------------------------------

  Future<void> confirmFollowUpReceipt({
    required String applicationId,
    required String followUpId,
    required String actorName,
    String? notes,
  }) async {
    await _followUpsOf(applicationId).doc(followUpId).update({
      'status': FollowUpStatus.confirmed.name,
      'confirmedAt': FieldValue.serverTimestamp(),
      'confirmedBy': actorName,
      if (notes != null && notes.isNotEmpty) 'confirmationNotes': notes,
    });
    await _adoptionDoc(applicationId).update({
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Follow-up submission confirmed by $actorName.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  /// Only allowed by the UI once a response was submitted and confirmed —
  /// unless [manualOverride] is set (admin closing an unanswered follow-up),
  /// which requires [reason] and is recorded as such (spec §12).
  Future<void> completeFollowUp({
    required String applicationId,
    required String followUpId,
    required String actorName,
    bool manualOverride = false,
    String? reason,
  }) async {
    if (manualOverride && (reason == null || reason.isEmpty)) {
      throw StateError('A reason is required to manually close an unanswered follow-up.');
    }
    await _followUpsOf(applicationId).doc(followUpId).update({
      'status': FollowUpStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
      'completedBy': actorName,
      if (manualOverride) 'manualCompletionReason': reason,
    });
  }

  /// Guards against rapid duplicate taps by rejecting a second reminder for
  /// the same follow-up within 5 minutes (spec §11).
  Future<void> sendFollowUpReminder({
    required String applicationId,
    required String followUpId,
    required String actorName,
  }) async {
    final ref = _followUpsOf(applicationId).doc(followUpId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Follow-up not found.');
      final data = snap.data()!;
      final lastSent = data['reminderSentAt'];
      if (lastSent is Timestamp && DateTime.now().difference(lastSent.toDate()) < const Duration(minutes: 5)) {
        throw StateError('A reminder was already sent for this follow-up a few minutes ago.');
      }
      final currentStatus = FollowUpStatus.fromName(data['status'] as String?);
      final now = Timestamp.now();
      tx.update(ref, {
        'reminderSentAt': now,
        'reminderCount': (data['reminderCount'] as num? ?? 0).toInt() + 1,
        if (currentStatus == FollowUpStatus.scheduled) 'status': FollowUpStatus.reminderSent.name,
      });
    });
    await _adoptionDoc(applicationId).update({
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Follow-up reminder sent.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  /// Reschedules one future follow-up date without regenerating the rest of
  /// the schedule (spec §14) — [originalScheduledDate] is only ever set the
  /// first time a given follow-up is rescheduled, so later reschedules don't
  /// overwrite the true original.
  Future<void> rescheduleFollowUp({
    required String applicationId,
    required String followUpId,
    required DateTime newDate,
    required String actorName,
    String? reason,
  }) async {
    final ref = _followUpsOf(applicationId).doc(followUpId);
    final snap = await ref.get();
    final data = snap.data();
    final hasOriginal = data?['originalScheduledDate'] != null;
    final currentScheduledDate = data?['scheduledDate'];

    await ref.update({
      'scheduledDate': Timestamp.fromDate(newDate),
      if (!hasOriginal && currentScheduledDate is Timestamp) 'originalScheduledDate': currentScheduledDate,
      'rescheduledAt': FieldValue.serverTimestamp(),
      'rescheduledBy': actorName,
      if (reason != null && reason.isNotEmpty) 'rescheduleReason': reason,
    });
    await _adoptionDoc(applicationId).update({
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'A follow-up was rescheduled by $actorName.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  Future<void> markPostAdoptionComplete({
    required String applicationId,
    required String actorName,
  }) async {
    final followUpsSnap = await _followUpsOf(applicationId).get();
    final incomplete = followUpsSnap.docs.where((d) {
      final status = FollowUpStatus.fromName(d.data()['status'] as String?);
      return status != FollowUpStatus.completed && status != FollowUpStatus.cancelled;
    });
    if (incomplete.isNotEmpty) {
      throw StateError('Every follow-up must be completed (or cancelled) first.');
    }
    final now = Timestamp.now();
    await _adoptionDoc(applicationId).update({
      'postAdoptionStatus': 'completed',
      'postAdoptionCompletedAt': now,
      'postAdoptionCompletedBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Post-adoption monitoring completed.', 'timestamp': now}
      ]),
    });
  }

  // ---- Post-adoption warnings (adoptions/{id}/warnings) ------------------

  /// Writes the warning doc `_WarningsSection`/`_WarningRow` in
  /// PostAdoptionDetailsPage stream directly (`orderBy('sentAt', descending:
  /// true)`) — field names below must match exactly what those widgets
  /// read: `category`, `message`, `requiredAction`, `responseDeadline`,
  /// `sentAt`, `sentBy`, `resolved` (spec §4/Send Warning sheet).
  Future<void> sendWarning({
    required String applicationId,
    required String category,
    required String message,
    String? requiredAction,
    DateTime? responseDeadline,
    required String actorUid,
    required String actorName,
  }) async {
    final now = Timestamp.now();
    await _warningsOf(applicationId).add({
      'category': category,
      'message': message,
      if (requiredAction != null && requiredAction.isNotEmpty) 'requiredAction': requiredAction,
      if (responseDeadline != null) 'responseDeadline': Timestamp.fromDate(responseDeadline),
      'sentAt': now,
      'sentBy': actorName,
      'sentByUid': actorUid,
      'resolved': false,
    });
    await _adoptionDoc(applicationId).update({
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Warning sent: $category.', 'timestamp': now}
      ]),
    });
  }

  /// Marks a warning resolved — does not notify the adopter (per the
  /// confirmation dialog copy in PostAdoptionDetailsPage._resolveWarning),
  /// purely an internal record-keeping action.
  Future<void> resolveWarning({
    required String applicationId,
    required String warningId,
    required String actorName,
  }) async {
    final now = Timestamp.now();
    await _warningsOf(applicationId).doc(warningId).update({
      'resolved': true,
      'resolvedAt': now,
      'resolvedBy': actorName,
    });
    await _adoptionDoc(applicationId).update({
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Warning marked resolved by $actorName.', 'timestamp': now}
      ]),
    });
  }

  // ---- Animal Return --------------------------------------------------

  /// Ports the write AdoptionReturnForm (post_adoption_page.dart) already
  /// performs, but into the `returnRequest.status` state machine instead of
  /// overloading the top-level `status`/AdoptionStatus field — the
  /// application stays AdoptionStatus.adopted throughout the whole return
  /// process (spec: "don't move to Intake just because a return was
  /// approved," adoption history is preserved).
  Future<void> requestReturn({
    required String applicationId,
    required String reason,
    String? reasonOther,
    required String urgency,
    required String explanation,
    required List<String> images,
    required String actorUid,
  }) async {
    await _adoptionDoc(applicationId).update({
      'returnRequest': {
        'reason': reason,
        if (reasonOther != null && reasonOther.isNotEmpty) 'reasonOther': reasonOther,
        'urgency': urgency,
        'explanation': explanation,
        'images': images,
        'requestedBy': actorUid,
        'requestedAt': Timestamp.now(),
        'status': ReturnRequestStatus.pendingReview.name,
        // Adopter-initiated is the default source; see [adminInitiateReturn]
        // for the organization-initiated counterpart. Explicit here so a
        // return request document is never ambiguous about its origin.
        'source': 'adopter',
      },
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Return requested.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  /// Starts the exact same `returnRequest` state machine [requestReturn]
  /// uses, just tagged `source: 'organization'` (so `ReturnRequest.
  /// isOrgInitiated` reads true) plus the admin-only fields the Initiate
  /// Return sheet collects (spec §4). Status still opens at pendingReview —
  /// this is the same workflow an adopter-requested return goes through,
  /// not a fast-tracked one, and it flows through approve/schedule/
  /// retrieve/intake exactly the same way afterward.
  Future<void> adminInitiateReturn({
    required String applicationId,
    required String reason,
    required String explanation,
    required String urgency,
    DateTime? proposedRetrievalDateTime,
    String? internalNotes,
    required String actorUid,
    required String actorName,
  }) async {
    final now = Timestamp.now();
    await _adoptionDoc(applicationId).update({
      'returnRequest': {
        'reason': reason,
        'explanation': explanation,
        'urgency': urgency,
        'images': <String>[],
        if (proposedRetrievalDateTime != null)
          'proposedRetrievalDateTime': Timestamp.fromDate(proposedRetrievalDateTime),
        if (internalNotes != null && internalNotes.isNotEmpty) 'internalNotes': internalNotes,
        'source': 'organization',
        'requestedBy': actorUid,
        'requestedAt': now,
        'status': ReturnRequestStatus.pendingReview.name,
      },
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Return initiated by organization ($actorName).', 'timestamp': now}
      ]),
    });
  }

  Future<void> approveReturn({required String applicationId, required String actorName}) async {
    final now = Timestamp.now();
    await _adoptionDoc(applicationId).update({
      'returnRequest.status': ReturnRequestStatus.approved.name,
      'returnRequest.approvedAt': now,
      'returnRequest.approvedBy': actorName,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Return approved.', 'timestamp': now}
      ]),
    });
  }

  Future<void> declineReturn({
    required String applicationId,
    required String actorName,
    required String reason,
  }) async {
    final now = Timestamp.now();
    await _adoptionDoc(applicationId).update({
      'returnRequest.status': ReturnRequestStatus.declined.name,
      'returnRequest.declinedAt': now,
      'returnRequest.declinedBy': actorName,
      'returnRequest.declineReason': reason,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Return declined: $reason.', 'timestamp': now}
      ]),
    });
  }

  /// Also used to reschedule an already-scheduled retrieval — same fields,
  /// same call, per spec §18/§19 ("Reschedule remains available").
  Future<void> setRetrievalSchedule({
    required String applicationId,
    required DateTime dateTime,
    String? address,
    double? lat,
    double? lng,
    String? notes,
    required String actorName,
  }) async {
    final now = Timestamp.now();
    await _adoptionDoc(applicationId).update({
      'returnRequest.status': ReturnRequestStatus.retrievalScheduled.name,
      'returnRequest.retrievalScheduledAt': now,
      'returnRequest.retrievalDateTime': Timestamp.fromDate(dateTime),
      if (address != null && address.isNotEmpty) 'returnRequest.retrievalAddress': address,
      if (lat != null) 'returnRequest.retrievalLat': lat,
      if (lng != null) 'returnRequest.retrievalLng': lng,
      if (notes != null && notes.isNotEmpty) 'returnRequest.retrievalNotes': notes,
      'returnRequest.scheduledBy': actorName,
      // A (re)schedule always resets the adopter's own acknowledgement —
      // they're confirming this specific date/time, not just "a" schedule.
      'returnRequest.confirmedByAdopter': false,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Retrieval scheduled.', 'timestamp': now}
      ]),
    });
  }

  /// Marks the animal physically retrieved. Deliberately light-touch on the
  /// animal doc (a transitional `currentStatus` only) — the full "un-adopt"
  /// transition happens in [proceedToIntake], since spec §19/§20 keep
  /// "Retrieved" and "Proceed to Intake" as two separate, explicit steps.
  Future<void> confirmAnimalRetrieved({
    required String applicationId,
    required String animalId,
    required String actorName,
  }) async {
    final appRef = _adoptionDoc(applicationId);
    final animalRef = _animals.doc(animalId);
    await _db.runTransaction((tx) async {
      final now = Timestamp.now();
      tx.update(appRef, {
        'returnRequest.status': ReturnRequestStatus.retrieved.name,
        'returnRequest.retrievedAt': now,
        'returnRequest.retrievedBy': actorName,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Animal retrieved from adopter.', 'timestamp': now}
        ]),
      });
      tx.update(animalRef, {'currentStatus': 'returning', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// The final "un-adopt" + hand-off-to-Intake step. Reuses
  /// AnimalRecordRepository.returnFromAdoption for the animal-doc transition
  /// (never clears adoption history) and
  /// RescueCaseRepository.createReturnIntakeCase to open the case — no new
  /// `animals/{id}` doc is ever created. Returns the new case id so the
  /// caller can navigate straight into the existing IntakeDetailPage.
  Future<String> proceedToIntake({
    required String applicationId,
    required String animalId,
    required String actorUid,
    required String actorName,
    required double shelterLat,
    required double shelterLng,
    String? shelterAddress,
  }) async {
    final appSnap = await _adoptionDoc(applicationId).get();
    final appData = appSnap.data();
    if (appData == null) throw StateError('Application not found.');
    final application = AdoptionApplication.fromFirestore(appSnap);
    final returnRequest = ReturnRequest.fromMap(appData['returnRequest'] as Map<String, dynamic>?);
    if (returnRequest == null || returnRequest.status != ReturnRequestStatus.retrieved) {
      throw StateError('The animal must be confirmed retrieved before proceeding to Intake.');
    }
    final animalSnap = await _animals.doc(animalId).get();
    final species = animalSnap.data()?['species'] as String? ?? '';

    final caseId = await _caseRepo.createReturnIntakeCase(
      sourceAnimalRecordId: animalId,
      animalName: application.animalName,
      species: species,
      returnRequestId: applicationId,
      previousAdoptionId: applicationId,
      adopterName: application.adopterName,
      returnReason: returnRequest.reason,
      returnExplanation: returnRequest.explanation,
      returnPhotos: returnRequest.images,
      retrievedAt: returnRequest.retrievedAt ?? DateTime.now(),
      lat: shelterLat,
      lng: shelterLng,
      shelterAddress: shelterAddress,
      actorUid: actorUid,
      actorName: actorName,
    );

    await _animalRepo.returnFromAdoption(
      animalId: animalId,
      returnRequestId: applicationId,
      previousAdoptionId: applicationId,
    );

    await _adoptionDoc(applicationId).update({
      'returnRequest.status': ReturnRequestStatus.intake.name,
      'returnRequest.intakeCaseId': caseId,
      'returnRequest.proceededToIntakeAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Animal proceeded to Intake as an Adoption Return.', 'timestamp': Timestamp.now()}
      ]),
    });

    return caseId;
  }
}