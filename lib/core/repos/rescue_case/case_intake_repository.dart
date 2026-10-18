// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/repos/rescue_case/transport_assignment_repository.dart';

/// Admission and intake: shelter admission / return-intake cases, post-
/// treatment actions (intake, transfer, release), intake confirmation and
/// quarantine.
class CaseIntakeRepository {
  CaseIntakeRepository(this._store, this._transport);

  final RescueCaseStore _store;
  final TransportAssignmentRepository _transport;

  /// Creates a `cases` doc directly in the "needs a clinic + transporter"
  /// state — the entry point for AdmitAnimalPage (Animal Record -> Medical
  /// -> Admit Animal), for an animal already owned/managed by the
  /// organization that later needs vet care. Deliberately skips every
  /// rescue-report concept (Rescue Review, Accept/Reject, Possible
  /// Duplicate, Community Reports) by starting at
  /// RescueStatus.awaitingAssignment with no saved clinic yet, which is
  /// exactly the state RescueDetailPage's own "Select Clinic" branch reads
  /// — the caller opens showSelectClinicSheet directly instead of routing
  /// through that page. See streamCasesByStatuses' isReviewQueueQuery guard
  /// for how this stays out of the Rescue Reports review queue while still
  /// appearing in Ongoing/Treatment/Intake once it's moving.
  Future<String> createAdmissionCase({
    required String sourceAnimalRecordId,
    required String animalName,
    required String species,
    required String admissionReason,
    String? admissionNotes,
    required double lat,
    required double lng,
    String? shelterAddress,
    required String actorUid,
    required String actorName,
  }) async {
    final ref = _store.cases.doc();
    final now = Timestamp.now();
    await ref.set({
      'status': RescueStatus.awaitingAssignment.firestoreValue,
      'sourceType': 'animalRecordAdmission',
      'sourceAnimalRecordId': sourceAnimalRecordId,
      'admissionReason': admissionReason,
      if (admissionNotes != null && admissionNotes.isNotEmpty)
        'admissionNotes': admissionNotes,
      'animalType': species,
      'condition': admissionNotes ?? '',
      'reporterName': actorName,
      'lat': lat,
      'lng': lng,
      if (shelterAddress != null && shelterAddress.isNotEmpty)
        'address': shelterAddress,
      'urgency': 'Medium',
      'createdAt': FieldValue.serverTimestamp(),
      'statusHistory': [
        {
          'status':
              'Medical admission opened for $animalName ($admissionReason).',
          'timestamp': now,
        },
      ],
    });
    await _store.addActivityLog(
      caseId: ref.id,
      action: 'animal_record_admission_created',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'sourceAnimalRecordId': sourceAnimalRecordId,
        'reason': admissionReason,
      },
    );
    return ref.id;
  }

  /// Opens a case directly at [RescueStatus.intake] for an animal that's
  /// being returned by its adopter — same "the animal record already
  /// exists, this isn't a fresh public report" reasoning as
  /// [createAdmissionCase], so it skips Rescue Review/Accept/Assign the same
  /// way. IntakeDetailPage reads `sourceType == 'adoptionReturn'` to show
  /// the "Intake Source: Adoption Return" banner. Called from
  /// AdoptionApplicationRepository.confirmAnimalRetrieved's "Proceed to
  /// Intake" step — never creates a new `animals/{id}` doc, only this
  /// `cases` doc pointing back at the existing one.
  Future<String> createReturnIntakeCase({
    required String sourceAnimalRecordId,
    required String animalName,
    required String species,
    required String returnRequestId,
    required String previousAdoptionId,
    required String adopterName,
    required String returnReason,
    String? returnExplanation,
    List<String> returnPhotos = const [],
    required DateTime retrievedAt,
    required double lat,
    required double lng,
    String? shelterAddress,
    required String actorUid,
    required String actorName,
  }) async {
    final ref = _store.cases.doc();
    final now = Timestamp.now();
    await ref.set({
      'status': RescueStatus.intake.firestoreValue,
      'sourceType': 'adoptionReturn',
      'sourceAnimalRecordId': sourceAnimalRecordId,
      'returnRequestId': returnRequestId,
      'previousAdoptionId': previousAdoptionId,
      'animalType': species,
      'reporterName': adopterName,
      'condition': returnExplanation ?? returnReason,
      'admissionReason': returnReason,
      if (returnExplanation != null && returnExplanation.isNotEmpty)
        'admissionNotes': returnExplanation,
      'photoUrls': returnPhotos,
      'retrievedAt': Timestamp.fromDate(retrievedAt),
      'lat': lat,
      'lng': lng,
      if (shelterAddress != null && shelterAddress.isNotEmpty)
        'address': shelterAddress,
      'urgency': 'Medium',
      'createdAt': FieldValue.serverTimestamp(),
      'statusHistory': [
        {
          'status': 'Adoption return intake opened for $animalName.',
          'timestamp': now,
        },
      ],
    });
    await _store.addActivityLog(
      caseId: ref.id,
      action: 'adoption_return_intake_created',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'sourceAnimalRecordId': sourceAnimalRecordId,
        'returnRequestId': returnRequestId,
      },
    );
    // Same medicalEpisodes + currentCaseId linkage AnimalRecordRepository.
    // admitAnimal already writes for its own sourceAnimalRecordId flow —
    // without this, the existing record's Medical tab (_EpisodesSection)
    // has no way to know this new intake case exists at all, since it
    // reads sourceCaseIds from that subcollection, not from this case's own
    // sourceAnimalRecordId pointer.
    await _store.animals
        .doc(sourceAnimalRecordId)
        .collection('medicalEpisodes')
        .add({
          'animalId': sourceAnimalRecordId,
          'sourceCaseId': ref.id,
          'sourceType': 'adoptionReturn',
          'reason': 'other',
          'notes':
              'Adoption return intake${returnExplanation != null && returnExplanation.isNotEmpty ? ': $returnExplanation' : ''}',
          'createdAt': FieldValue.serverTimestamp(),
          if (actorName.isNotEmpty) 'createdBy': actorName,
        });
    await _store.animals.doc(sourceAnimalRecordId).update({
      'currentCaseId': ref.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// [targetType] is one of 'organization' | 'clinic' | 'volunteer' — the
  /// spec's three required destination types (never one untyped free-text
  /// destination). Type-specific identity (targetOrganizationId for a real
  /// OrgReferralCandidate, targetClinicPlaceId/lat/lng for a real Places
  /// result) is stored alongside the common fields every type shares
  /// (targetName/targetContact/targetAddress/reason/date/notes) — a
  /// Volunteer destination has no queryable directory in this app yet, so
  /// it only ever fills the common fields (see transfer_animal_sheet.dart).
  /// Transfer/Release stay visible on Treatment Details before discharge
  /// (spec: disabled with an explanation, never hidden) — the UI disables
  /// the buttons, but that alone is never trusted; this is the actual
  /// enforcement, so a stale page or a direct call can't bypass it.
  /// Per-animal eligibility gate for Transfer/Release (spec §8/§10/§11) —
  /// replaces the old case-wide `_ensureReadyForDischarge`. When
  /// [animalIndexes] is null/empty (every call site that predates this
  /// round, and any legacy single-animal case with no `animals[]` array),
  /// this falls back to the original single scalar `readyForDischarge`
  /// check, unchanged. Otherwise every named index must be discharged, not
  /// deceased, and not already committed to a different post-treatment
  /// action — trusted from the animal-selection sheet but revalidated here
  /// so a stale sheet or a direct call can't bypass it. Returns the
  /// freshly-read `animals` array so the caller can mutate it in the same
  /// read without a second round-trip.
  Future<List<Map<String, dynamic>>> _ensureAnimalsEligible(
    String caseId,
    List<int>? animalIndexes,
  ) async {
    final snap = await _store.caseDoc(caseId).get();
    final data = snap.data();
    final animals = List<Map<String, dynamic>>.from(
      (data?['animals'] as List? ?? const []).map(
        (a) => Map<String, dynamic>.from(a as Map),
      ),
    );
    if (animals.isEmpty || animalIndexes == null || animalIndexes.isEmpty) {
      final ready = data?['readyForDischarge'] as bool? ?? false;
      if (!ready) {
        throw StateError(
          'A Discharge update is required before this action is available.',
        );
      }
      return animals;
    }
    for (final i in animalIndexes) {
      if (i < 0 || i >= animals.length) continue;
      final a = animals[i];
      if (a['outcome'] == 'deceased' ||
          a['dischargedAt'] == null ||
          a['postTreatmentAction'] != null) {
        throw StateError(
          'One or more selected animals are not eligible for this action.',
        );
      }
    }
    return animals;
  }

  /// [animalIndexes] — the specific discharged animals this transfer
  /// applies to (spec §10). Null/empty (every pre-existing call site) keeps
  /// the original whole-case behavior exactly: the entire case moves to
  /// [RescueStatus.completed]. When provided (and the case actually has an
  /// `animals[]` array), only those animals are stamped
  /// transferred/`postTreatmentAction: 'transfer'` and the case-level
  /// `status` is safely re-derived from every animal's own state instead of
  /// being forced to `completed` — a case with animals left behind in
  /// Treatment stays visible there (spec §7/§10's "keep the case visible in
  /// Treatment for any animals left behind").
  Future<void> transferAnimal({
    required String caseId,
    required String targetType,
    required String targetName,
    String? targetContact,
    String? targetAddress,
    String? targetOrganizationId,
    String? targetClinicPlaceId,
    double? targetLat,
    double? targetLng,
    required String reason,
    DateTime? transferDate,
    String? notes,
    required String actorUid,
    required String actorName,
    List<int>? animalIndexes,
  }) async {
    final animals = await _ensureAnimalsEligible(caseId, animalIndexes);
    final now = Timestamp.now();
    final perAnimal =
        animals.isNotEmpty && animalIndexes != null && animalIndexes.isNotEmpty;
    if (perAnimal) {
      for (final i in animalIndexes) {
        if (i < 0 || i >= animals.length) continue;
        animals[i] = {
          ...animals[i],
          'postTreatmentAction': 'transfer',
          'postTreatmentStartedAt': now,
          'transferDestinationType': targetType,
          'transferDestinationName': targetName,
          'transferCompletedAt': now,
        };
      }
    }
    await _store.caseDoc(caseId).update({
      'status': perAnimal
          ? (RescueCaseStore.deriveCaseStatusOverride(animals) ??
                RescueStatus.completed.firestoreValue)
          : RescueStatus.completed.firestoreValue,
      'transferType': targetType,
      'targetName': targetName,
      // Legacy field names, kept so any existing reader of a
      // pre-this-round transfer keeps working unmodified. These reflect
      // the MOST RECENT transfer recorded on the case (this app has no
      // per-transfer-event subcollection yet); per-animal destination
      // fields above are the source of truth once several separate
      // transfers happen for different animals over time.
      if (targetType == 'organization') 'targetOrganizationName': targetName,
      if (targetContact != null && targetContact.isNotEmpty)
        'targetContact': targetContact,
      if (targetAddress != null && targetAddress.isNotEmpty)
        'targetAddress': targetAddress,
      if (targetOrganizationId != null)
        'targetOrganizationId': targetOrganizationId,
      if (targetClinicPlaceId != null)
        'targetClinicPlaceId': targetClinicPlaceId,
      if (targetLat != null) 'targetLat': targetLat,
      if (targetLng != null) 'targetLng': targetLng,
      'transferReason': reason,
      'transferDate': transferDate != null
          ? Timestamp.fromDate(transferDate)
          : now,
      'transferNotes': notes,
      'transferRequestedAt': now,
      // TODO(transfer): this is a simplified, one-way record — there is no
      // receiving-organization/clinic/volunteer acceptance workflow yet.
      // 'pending' here just means "handed off, not yet acknowledged."
      'transferStatus': 'pending',
      if (perAnimal) 'animals': animals,
      if (perAnimal) ...RescueCaseStore.stageSummaryUpdate(animals),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Animal transferred to $targetName ($targetType).',
          'timestamp': now,
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'transferred_animal',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'targetType': targetType,
        'targetName': targetName,
        if (targetOrganizationId != null)
          'targetOrganizationId': targetOrganizationId,
      },
    );
  }

  /// Temporary handoff record only — this is NOT a completed adoption. See
  /// the TODO on the release UI: formal adoption approval/forms are a
  /// separate, not-yet-built feature. [animalIndexes] follows the exact
  /// same null-means-legacy-whole-case convention as [transferAnimal].
  Future<void> releaseToReporter({
    required String caseId,
    required String reporterId,
    required String reporterName,
    String? notes,
    required String actorUid,
    required String actorName,
    List<int>? animalIndexes,
  }) async {
    final animals = await _ensureAnimalsEligible(caseId, animalIndexes);
    final now = Timestamp.now();
    final perAnimal =
        animals.isNotEmpty && animalIndexes != null && animalIndexes.isNotEmpty;
    if (perAnimal) {
      for (final i in animalIndexes) {
        if (i < 0 || i >= animals.length) continue;
        animals[i] = {
          ...animals[i],
          'postTreatmentAction': 'release',
          'postTreatmentStartedAt': now,
          'releaseCompletedAt': now,
        };
      }
    }
    await _store.caseDoc(caseId).update({
      'status': perAnimal
          ? (RescueCaseStore.deriveCaseStatusOverride(animals) ??
                RescueStatus.completed.firestoreValue)
          : RescueStatus.completed.firestoreValue,
      'releasedToReporterId': reporterId,
      'releasedToReporterName': reporterName,
      'releasedAt': now,
      'releaseNotes': notes,
      if (perAnimal) 'animals': animals,
      if (perAnimal) ...RescueCaseStore.stageSummaryUpdate(animals),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Release confirmed — handed off to $reporterName.',
          'timestamp': now,
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'released_to_reporter',
      actorUid: actorUid,
      actorName: actorName,
      details: {'reporterId': reporterId, 'reporterName': reporterName},
    );
  }

  /// Marks the given animals as committed to the Intake path (spec §8/§9)
  /// — called the moment the admin confirms their animal selection on
  /// Treatment Details' Intake action, before IntakeDetailPage even opens,
  /// so the case immediately shows up under the Intake tab for these
  /// animals (via `activeAnimalStages`) while any other animal stays under
  /// Treatment (spec §7). A no-op for a legacy case with no `animals[]`
  /// array — that flow never shows the animal-selection step at all (see
  /// TreatmentDetailPage), so this is never called for one.
  Future<void> assignIntakeAction({
    required String caseId,
    required List<int> animalIndexes,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) throw StateError('This case no longer exists.');
      final animals = List<Map<String, dynamic>>.from(
        (data['animals'] as List? ?? const []).map(
          (a) => Map<String, dynamic>.from(a as Map),
        ),
      );
      if (animals.isEmpty) return;
      final now = Timestamp.now();
      for (final i in animalIndexes) {
        if (i < 0 || i >= animals.length) continue;
        final a = animals[i];
        if (a['outcome'] == 'deceased' ||
            a['dischargedAt'] == null ||
            a['postTreatmentAction'] != null) {
          throw StateError(
            'One or more selected animals are not eligible for this action.',
          );
        }
        animals[i] = {
          ...a,
          'postTreatmentAction': 'intake',
          'postTreatmentStartedAt': now,
        };
      }
      tx.update(caseRef, {
        'animals': animals,
        ...RescueCaseStore.stageSummaryUpdate(animals),
        'status':
            RescueCaseStore.deriveCaseStatusOverride(animals) ??
            (data['status'] as String? ??
                RescueStatus.treatment.firestoreValue),
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Selected animal(s) moved to Intake.', 'timestamp': now},
        ]),
      });
    });
  }

  /// Per-animal Intake completion (spec §9) — sibling to
  /// [checkAndCompleteIntakeIfDue], for a case that has an `animals[]`
  /// array and therefore may have OTHER animals still active elsewhere
  /// (still in Treatment, or on a separate Intake/Transfer/Release path) —
  /// completing this subset's Intake must never require or wait on any
  /// other animal's own treatment/record to finish, and must never mark
  /// animals outside [animalIndexes] complete. Only touches animals that
  /// are actually mid-Intake (`postTreatmentAction == 'intake'`, not
  /// already completed) — safe to call redundantly. A no-op for a legacy
  /// case with no `animals[]` array; callers keep using
  /// [checkAndCompleteIntakeIfDue] for that case shape.
  Future<void> completeIntakeForAnimals({
    required String caseId,
    required List<int> animalIndexes,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) return;
      final animals = List<Map<String, dynamic>>.from(
        (data['animals'] as List? ?? const []).map(
          (a) => Map<String, dynamic>.from(a as Map),
        ),
      );
      if (animals.isEmpty) return;
      final now = Timestamp.now();
      var changed = false;
      for (final i in animalIndexes) {
        if (i < 0 || i >= animals.length) continue;
        if (animals[i]['postTreatmentAction'] != 'intake' ||
            animals[i]['intakeCompletedAt'] != null)
          continue;
        animals[i] = {...animals[i], 'intakeCompletedAt': now};
        changed = true;
      }
      if (!changed) return;
      tx.update(caseRef, {
        'animals': animals,
        ...RescueCaseStore.stageSummaryUpdate(animals),
        'status':
            RescueCaseStore.deriveCaseStatusOverride(animals) ??
            (data['status'] as String? ?? RescueStatus.intake.firestoreValue),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Intake completed for the selected animal(s).',
            'timestamp': now,
          },
        ]),
      });
    });
  }

  /// Moves a case into the Intake stage: saves the destination, moves
  /// `status` to 'intake' (its own alias list, disjoint from 'ongoing' —
  /// no collision like the earlier treatment-status bug), and — if a
  /// transporter is carried forward (same one or a reassignment) — records
  /// a new transportAssignment doc for this leg, written directly as
  /// 'accepted' rather than 'pending'. That's deliberate: this transporter
  /// was already trusted/accepted for an earlier leg of the same case, so
  /// re-running the full offer/pending/accept dance here would just be
  /// friction; that full dance still happens for genuine reassignment via
  /// the existing Assign Transporter screen. Writing this doc (not just
  /// updating the case's flat assignedVolunteer* fields) is what correctly
  /// keeps the transporter showing Busy elsewhere for the duration of this
  /// leg, since activeAssignmentsByRiderProvider only looks at the most
  /// recent assignment doc.
  ///
  /// Guarded against double-confirmation: a no-op if `intakeConfirmedAt` is
  /// already set.
  Future<void> confirmIntake({
    required String caseId,
    required String destinationName,
    String? destinationAddress,
    String? destinationPlaceId,
    double? destinationLat,
    double? destinationLng,
    String? transporterUid,
    String? transporterName,
    String? transporterType,
    String? transporterVehicle,
    String? transporterPlate,
    bool isDemoTransporter = false,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentRef = _store.transportAssignmentsOf(caseId).doc();

    await _store.db.runTransaction((tx) async {
      final caseSnap = await tx.get(caseRef);
      if (!caseSnap.exists) throw StateError('Case not found.');
      final caseData = caseSnap.data();
      if (caseData?['intakeConfirmedAt'] != null) return; // already confirmed

      // A mixed-stage case (spec §7) may still have another animal active
      // in Treatment while this Intake leg is confirmed — status must not
      // be forced to 'intake' in that case, or the case would wrongly
      // disappear from the Treatment tab's status-based query. Falls back
      // to the original unconditional 'intake' write for a legacy case
      // with no `animals[]` array.
      final animalsRaw = List<Map<String, dynamic>>.from(
        (caseData?['animals'] as List? ?? const []).map(
          (a) => Map<String, dynamic>.from(a as Map),
        ),
      );
      final statusOverride =
          RescueCaseStore.deriveCaseStatusOverride(animalsRaw) ??
          RescueStatus.intake.firestoreValue;

      final now = Timestamp.now();
      tx.update(caseRef, {
        'status': statusOverride,
        'intakeDestinationName': destinationName,
        'intakeDestinationAddress': destinationAddress,
        'intakeDestinationPlaceId': destinationPlaceId,
        'intakeDestinationLat': destinationLat,
        'intakeDestinationLng': destinationLng,
        'intakeConfirmedAt': now,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
                'Intake confirmed — transport to $destinationName arranged.',
            'timestamp': now,
          },
        ]),
        if (transporterUid != null) 'currentAssignmentId': assignmentRef.id,
        if (transporterUid != null) 'assignedVolunteerId': transporterUid,
        if (transporterUid != null) 'assignedVolunteerName': transporterName,
        if (transporterUid != null) 'assignedVehicle': transporterVehicle,
        if (transporterUid != null) 'assignedPlate': transporterPlate,
      });

      if (transporterUid != null) {
        tx.set(assignmentRef, {
          'caseId': caseId,
          'riderId': transporterUid,
          'riderName': transporterName ?? 'Unknown Transporter',
          'riderType': transporterType ?? 'Pet Transporter',
          'status': 'accepted',
          'offeredAt': now,
          'respondedAt': now,
          'acceptedAt': now,
          'rejectedAt': null,
          'rejectionReason': null,
          'completedAt': null,
          'isDemo': isDemoTransporter,
          'vehicle': transporterVehicle,
          'plate': transporterPlate,
        });
      }
    });
  }

  /// Organization's "Confirm Animal Received" action once the transporter
  /// has physically arrived — completes the intake-leg transport
  /// assignment (freeing the transporter back to Available) and stamps
  /// the arrival time. Never touches the case's own RescueStatus: arriving
  /// at the shelter doesn't complete the whole rescue case, it just means
  /// transport is done and quarantine/animal-record steps can begin.
  /// [animalIndexes] scopes this confirmation to specific animals in a
  /// multi-animal Intake (spec: "Multi-animal Intake must evaluate receipt
  /// per animal — one received animal should not unlock record creation
  /// for another"). Writes a per-animal `receivedAt` (see
  /// core/utils/animal_treatment_state.dart's animalIsReceived, the read
  /// side this feeds) to just those indexes, or to every animal when
  /// [animalIndexes] is null (the whole-case call every pre-existing
  /// caller still makes). The case-level `intakeReceivedAt` flag is only
  /// ever set once — a later confirmation for a different animal subset
  /// never overwrites the original received timestamp every other reader
  /// of that case-level field (View Transport Tracking's gate, the
  /// intake-mode Track Case screen, ...) already depends on.
  Future<void> confirmAnimalReceived({
    required String caseId,
    String? currentAssignmentId,
    List<int>? animalIndexes,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) return;
      final now = Timestamp.now();
      final update = <String, dynamic>{
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Animal received at the shelter.', 'timestamp': now},
        ]),
      };
      if (data['intakeReceivedAt'] == null) {
        update['intakeReceivedAt'] = now;
      }
      final rawAnimals = (data['animals'] as List?) ?? const [];
      if (rawAnimals.isNotEmpty) {
        final animals = List<Map<String, dynamic>>.from(
          rawAnimals.map((a) => Map<String, dynamic>.from(a as Map)),
        );
        final targets =
            animalIndexes ?? List.generate(animals.length, (i) => i);
        for (final i in targets) {
          if (i < 0 || i >= animals.length) continue;
          animals[i] = {...animals[i], 'receivedAt': now};
        }
        update['animals'] = animals;
      }
      tx.update(caseRef, update);
    });
    if (currentAssignmentId != null) {
      await _transport.completeAssignment(
        caseId: caseId,
        assignmentId: currentAssignmentId,
      );
    }
  }

  Future<void> startQuarantine({
    required String caseId,
    required int durationDays,
  }) async {
    final now = DateTime.now();
    await _store.caseDoc(caseId).update({
      'quarantineStatus': 'active',
      'quarantineStartedAt': FieldValue.serverTimestamp(),
      'quarantineDurationDays': durationDays,
      // The scheduled END is a future instant, which FieldValue.serverTimestamp()
      // can't express (it only stamps "now") — computed from the device
      // clock here. The START above still uses the server clock.
      'quarantineScheduledEndAt': Timestamp.fromDate(
        now.add(Duration(days: durationDays)),
      ),
      'quarantineEndedAt': null,
      'quarantineEndReason': null,
    });
  }

  Future<void> endQuarantine({required String caseId, String? reason}) async {
    await _store.caseDoc(caseId).update({
      'quarantineStatus': 'completed',
      'quarantineEndedAt': FieldValue.serverTimestamp(),
      if (reason != null && reason.isNotEmpty) 'quarantineEndReason': reason,
    });
  }

  /// Explicitly records that the organization chose not to quarantine —
  /// distinct from simply never having started one, so Intake Details
  /// stops re-prompting "Start Quarantine / Skip" once a decision has been
  /// made either way. Animal-record creation was never gated on this
  /// either way.
  Future<void> skipQuarantine({required String caseId}) async {
    await _store.caseDoc(caseId).update({'quarantineStatus': 'skipped'});
  }

  /// Client-derived automatic completion, persisted the next time the case
  /// is read/opened — RescueCase.isQuarantineActive applies the same
  /// past-the-deadline logic purely client-side (no write) so the UI never
  /// shows an overdue quarantine as still active even before this runs.
  /// TODO(quarantine): this only fires when an admin actually opens the
  /// case; replace with a scheduled Cloud Function for true server-side
  /// automatic completion that doesn't depend on the case being reopened.
  Future<void> checkAndCompleteQuarantineIfDue(RescueCase c) async {
    if (c.quarantineStatus != 'active') return;
    final scheduledEnd = c.quarantineScheduledEndAt;
    if (scheduledEnd == null || DateTime.now().isBefore(scheduledEnd)) return;
    await _store.caseDoc(c.id).update({
      'quarantineStatus': 'completed',
      'quarantineEndedAt': Timestamp.fromDate(scheduledEnd),
      'quarantineEndReason': 'Automatic — scheduled duration elapsed.',
    });
  }

  /// Intake completion = animal received at the shelter AND every expected
  /// animal record has been created — quarantine is optional and never
  /// blocks this (its own status lives on independent fields and is never
  /// read here). Reuses [RescueStatus.completed] as the "left the active
  /// pipeline, still visible in case history" terminal state — the exact
  /// same status a deceased-case close already reaches (see
  /// RescueStatus.completed's queryValues including the legacy 'closed'
  /// alias) — rather than inventing a second, parallel status field. Cheap,
  /// client-triggered reconciliation (mirrors
  /// [checkAndCompleteQuarantineIfDue]'s own pattern/TODO) called from
  /// IntakeDetailPage's live rebuild and from AnimalRecordsFlowPage the
  /// instant the last record is created — a transaction re-checks the same
  /// guard against the freshest doc, so calling this redundantly from both
  /// places (or twice in a race) is always harmless.
  Future<void> checkAndCompleteIntakeIfDue(
    RescueCase c, {
    required int totalAnimalsExpected,
    required int completedCount,
  }) async {
    if (c.intakeReceivedAt == null) return;
    if (completedCount < totalAnimalsExpected) return;
    if (c.status == RescueStatus.completed) return;

    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(_store.caseDoc(c.id));
      if (!snap.exists) return;
      final data = snap.data()!;
      if (RescueStatus.fromFirestoreValue(data['status'] as String?) ==
          RescueStatus.completed)
        return;
      if (data['intakeReceivedAt'] == null) return;

      final now = Timestamp.now();
      tx.update(_store.caseDoc(c.id), {
        'status': RescueStatus.completed.firestoreValue,
        'intakeCompletedAt': now,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Intake completed — all animal records created.',
            'timestamp': now,
          },
        ]),
      });
    });
  }
}
