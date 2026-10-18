// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/repos/rescue_case/transport_assignment_repository.dart';

/// Case status transitions: accept / reject, ownership, reporter location
/// updates, animal death, and closing a case.
class CaseStatusRepository {
  CaseStatusRepository(this._store, this._transport);

  final RescueCaseStore _store;
  final TransportAssignmentRepository _transport;

  /// [openForTransfer] only saves a flag on the case (RescueCase.openForTransfer)
  /// — there is no open-transfer listing, cross-org browsing, or transfer
  /// request/acceptance workflow yet. That's intentionally deferred.
  Future<void> acceptCase({
    required String caseId,
    required String actorUid,
    required String actorName,
    bool openForTransfer = false,
  }) async {
    await _store.caseDoc(caseId).update({
      // Stops at RescueStatus.accepted (clinic not yet chosen) rather than
      // jumping straight to awaitingAssignment — the case stays visible
      // under Rescue Review until assignClinic actually saves a clinic and
      // advances it. See rescue_status.dart's firestoreValue doc comment.
      'status': RescueStatus.accepted.firestoreValue,
      'openForTransfer': openForTransfer,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': openForTransfer
              ? 'Rescue case has been accepted and marked open for transfer to another organization.'
              : 'Rescue case has been accepted.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'accepted',
      actorUid: actorUid,
      actorName: actorName,
      details: {'openForTransfer': openForTransfer},
    );
  }

  Future<void> rejectCase({
    required String caseId,
    required RejectionReason reason,
    String? otherText,
    required String actorUid,
    required String actorName,
  }) async {
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.rejected.firestoreValue,
      'rejectionReason': reason.name,
      if (reason == RejectionReason.other && otherText != null)
        'rejectionReasonOther': otherText,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':
              'Case rejected: ${reason == RejectionReason.other ? (otherText ?? reason.label) : reason.label}.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'rejected',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'reason': reason.name,
        if (otherText != null) 'otherText': otherText,
      },
    );
  }

  /// Records what's known about a possible/confirmed owner (lost animal,
  /// suspected neglect/abandonment, owner present at pickup, ...) —
  /// deliberately additive `raw`-only fields (`ownershipStatus`/
  /// `ownedAnimalCategory`/`ownerName`/`ownerContact`/`ownershipNotes`/
  /// `ownerConfirmedAt`), following this model's existing convention for
  /// fields that don't need to be part of every read path (see [RescueCase.
  /// raw]'s own doc comment) — never a second case-like collection. Never
  /// changes `status`/closes the case on its own — an owner being
  /// identified is information the admin acts on deliberately via a
  /// separate next action (Continue rescue / Contact owner / Close Case),
  /// never an automatic closure.
  Future<void> updateOwnershipInfo({
    required String caseId,
    required String
    ownershipStatus, // 'Unknown' | 'No known owner' | 'Possible owner' | 'Owner identified'
    String?
    ownedAnimalCategory, // 'Lost animal' | 'Neglect concern' | 'Abandonment concern' | 'Other'
    String? ownerName,
    String? ownerContact,
    String? ownershipNotes,
    required String actorUid,
    required String actorName,
  }) async {
    await _store.caseDoc(caseId).update({
      'ownershipStatus': ownershipStatus,
      if (ownedAnimalCategory != null)
        'ownedAnimalCategory': ownedAnimalCategory,
      if (ownerName != null) 'ownerName': ownerName,
      if (ownerContact != null) 'ownerContact': ownerContact,
      if (ownershipNotes != null) 'ownershipNotes': ownershipNotes,
      if (ownershipStatus == 'Owner identified')
        'ownerConfirmedAt': Timestamp.now(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Ownership status updated: $ownershipStatus.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'updated_ownership_info',
      actorUid: actorUid,
      actorName: actorName,
      // Owner contact details are never written to the activity log's own
      // details map — that log is broadly readable by staff, and contact
      // info should only live on the case doc's own ownership fields,
      // never duplicated somewhere with wider/different visibility.
      details: {
        'ownershipStatus': ownershipStatus,
        'ownedAnimalCategory': ownedAnimalCategory,
      },
    );
  }

  /// Community Location Approval spec §9 — an "Animal moved" community
  /// report never changes the case's own official address/lat/lng at
  /// submission time (confirmed: nothing in this codebase does that
  /// today); this is the ONLY path that promotes a proposed location to
  /// official, and only once an admin explicitly approves it. Uses the
  /// report's own already-canonical `newAddress`/`newLat`/`newLng` fields
  /// (set at submission) rather than inventing separate
  /// `proposedAddress`/`proposedLat`/`proposedLng` fields — same data,
  /// no duplication. One transaction so the report's approval state and
  /// the case's location update can never diverge.
  Future<void> approveLocationUpdate({
    required String caseId,
    required String reportId,
    required String actorUid,
    required String actorName,
  }) async {
    final reportRef = _store.communityReportsOf(caseId).doc(reportId);
    final caseRef = _store.caseDoc(caseId);
    await _store.db.runTransaction((tx) async {
      final reportSnap = await tx.get(reportRef);
      if (!reportSnap.exists) throw StateError('This report no longer exists.');
      final caseSnap = await tx.get(caseRef);
      if (!caseSnap.exists) throw StateError('This case no longer exists.');
      final data = reportSnap.data()!;
      final caseData = caseSnap.data()!;
      if (data['type'] != 'moved')
        throw StateError(
          'Only an "Animal moved" report can update the case location.',
        );
      if (data['approvalStatus'] != 'pending')
        throw StateError('This location update has already been reviewed.');

      final newAddress = data['newAddress'] as String?;
      final newLat = (data['newLat'] as num?)?.toDouble();
      final newLng = (data['newLng'] as num?)?.toDouble();
      if (newAddress == null || newLat == null || newLng == null) {
        throw StateError(
          'This report is missing a resolved location and cannot be approved.',
        );
      }

      final now = Timestamp.now();
      tx.update(reportRef, {
        'approvalStatus': 'approved',
        'approvedBy': actorName,
        'approvedByUid': actorUid,
        'approvedAt': now,
      });
      // The original submission location is never discarded — it stays on
      // this same report doc (newAddress/newLat/newLng), and the case's
      // prior address/lat/lng are preserved in statusHistory below rather
      // than simply overwritten with no trace.
      tx.update(caseRef, {
        'address': newAddress,
        'lat': newLat,
        'lng': newLng,
        'locationHistory': FieldValue.arrayUnion([
          {
            'previousAddress': caseData['address'],
            'previousLat': caseData['lat'],
            'previousLng': caseData['lng'],
            'address': newAddress,
            'lat': newLat,
            'lng': newLng,
            'source': 'community_report',
            'reportId': reportId,
            'approvedBy': actorName,
            'approvedByUid': actorUid,
            'approvedAt': now,
          },
        ]),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
                'Location updated to "$newAddress" (community report approved by $actorName).',
            'timestamp': now,
          },
        ]),
      });
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'community_location_approved',
      actorUid: actorUid,
      actorName: actorName,
      details: {'reportId': reportId},
    );
  }

  Future<void> rejectLocationUpdate({
    required String caseId,
    required String reportId,
    required String actorUid,
    required String actorName,
    String? reason,
  }) async {
    final reportRef = _store.communityReportsOf(caseId).doc(reportId);
    await _store.db.runTransaction((tx) async {
      final reportSnap = await tx.get(reportRef);
      if (!reportSnap.exists) throw StateError('This report no longer exists.');
      if (reportSnap.data()!['approvalStatus'] != 'pending') {
        throw StateError('This location update has already been reviewed.');
      }
      // The case's own address/lat/lng are simply never touched — rejection
      // is a no-op on the official location, by construction.
      tx.update(reportRef, {
        'approvalStatus': 'rejected',
        'rejectedBy': actorName,
        'rejectedByUid': actorUid,
        'rejectedAt': Timestamp.now(),
        if (reason != null && reason.isNotEmpty) 'rejectionReason': reason,
      });
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'community_location_rejected',
      actorUid: actorUid,
      actorName: actorName,
      details: {'reportId': reportId, if (reason != null) 'reason': reason},
    );
  }

  /// "Retry search" — keeps the case open, updates the rescue location,
  /// and preserves the original reported location under `previousLocations`
  /// (never overwritten/lost) so every prior location this case was
  /// reported/searched at stays in history. Never creates a new case.
  /// Transporter/clinic distances are computed live from `lat`/`lng`
  /// wherever they're shown (Assign Transporter's rider list, clinic
  /// search's `centerLat`/`centerLng`) — updating these fields here is
  /// what makes those already-live computations reflect the new location
  /// the next time each screen reads it, without a separate recompute step.
  Future<void> updateCaseLocation({
    required String caseId,
    required double lat,
    required double lng,
    String? address,
    required String actorUid,
    required String actorName,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) return;
      final previous = List<Map<String, dynamic>>.from(
        data['previousLocations'] as List? ?? const [],
      );
      previous.add({
        'address': data['address'],
        'lat': data['lat'],
        'lng': data['lng'],
        'replacedAt': Timestamp.now(),
      });
      tx.update(caseRef, {
        'lat': lat,
        'lng': lng,
        if (address != null) 'address': address,
        'previousLocations': previous,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Rescue location updated.', 'timestamp': Timestamp.now()},
        ]),
      });
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'location_updated',
      actorUid: actorUid,
      actorName: actorName,
    );
  }

  /// Smallest backward-compatible per-animal outcome structure: [RescueCase.
  /// animals] entries (`{species, breed, sex, size, colorMarkings}`) gain
  /// optional `outcome`/`deceasedAt`/`deceasedReason`/`deceasedConfirmedBy`/
  /// `deceasedNotes`/`deceasedPhotoUrl` keys — every existing reader that
  /// only looks at `species`/`breed`/etc. is unaffected (it already reads
  /// each animal as a loose `Map<String, dynamic>`, not a fixed-shape
  /// model). This is read-modify-write (Firestore has no per-array-element
  /// update), so it always re-reads the array fresh, never assumes the
  /// caller's copy is current.
  ///
  /// Deliberately never changes case-level `status`/closes the case, even
  /// when this is the last remaining animal — per spec §4, closing only
  /// happens when *every* animal is deceased AND the admin explicitly
  /// chooses to close (via the shared Close Case flow), never
  /// automatically here.
  Future<void> reportAnimalDeath({
    required String caseId,
    required int animalIndex,
    required String reason,
    required String confirmedBy,
    String? notes,
    String? photoUrl,
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
      if (animalIndex < 0 || animalIndex >= animals.length) return;
      animals[animalIndex] = {
        ...animals[animalIndex],
        'outcome': 'deceased',
        'deceasedAt': Timestamp.now(),
        'deceasedReason': reason,
        'deceasedConfirmedBy': confirmedBy,
        if (notes != null) 'deceasedNotes': notes,
        if (photoUrl != null) 'deceasedPhotoUrl': photoUrl,
      };
      final animalLabel =
          (animals[animalIndex]['species'] as String?) ?? 'Animal';
      tx.update(caseRef, {
        'animals': animals,
        ...RescueCaseStore.stageSummaryUpdate(animals),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal death reported during rescue: $animalLabel.',
            'timestamp': Timestamp.now(),
          },
        ]),
      });
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'animal_death_reported',
      actorName: confirmedBy,
      details: {'animalIndex': animalIndex, 'reason': reason},
    );
  }

  /// Shared "Close Case" flow — reused by every exception path (owner
  /// found, aggressive animal, died during rescue, animal moved, clinic
  /// unavailable, duplicate, resolved without transport, other) instead of
  /// each one inventing its own terminal status. Reuses [RescueStatus.
  /// cancelled], which already exists in the enum, is already excluded
  /// from every active RescuePipelineTab's `.statuses` list (Review/
  /// Assign/Ongoing/Treatment/Intake), and is already reachable through
  /// the existing filter sheet's `statusOverride`/`kSecondaryStatuses` —
  /// so closing a case already removes it from every active queue and
  /// already has a place to view it, with no new queue-filtering code
  /// needed. [RescueStatus.completed] (legacy alias `'closed'`) is
  /// deliberately left alone — it already means "successfully finished"
  /// (transferAnimal/releaseToReporter/completed intake), a different
  /// concept from "closed due to an exception".
  ///
  /// Rejects the write if the case is already terminal, including when a
  /// different admin closes it concurrently. Any pending/accepted
  /// transporter assignment is safely
  /// cancelled first (never left dangling), which also frees that
  /// transporter back to Available.
  /// True once every animal in [animals] has either a recorded death or a
  /// completed Discharge — same rule as
  /// core/utils/animal_treatment_state.dart's caseAllAnimalsResolved, kept
  /// as a raw-map twin here (like _stageSummaryUpdate/
  /// _deriveCaseStatusOverride above) since this runs mid-transaction on
  /// the map already in hand, not a full RescueCase object.
  bool _allAnimalsResolved(List<Map<String, dynamic>> animals) =>
      animals.isEmpty ||
      animals.every(
        (a) => a['outcome'] == 'deceased' || a['dischargedAt'] != null,
      );

  /// Returns true when the whole case became terminal, or false when this
  /// write only resolved selected animals and the case remains active.
  Future<bool> closeCase({
    required String caseId,
    required ClosureReason reason,
    required String details,
    required String actorUid,
    required String actorName,
    String? actorRole,
    String? organizationId,
    String? lastKnownLocation,
    String? clinicUnavailableDetails,
    String? serviceTypeNeeded,
    // Which animals this closure applies to (spec §13/§2) — only ever
    // meaningful for [ClosureReason.died] (see
    // ClosureReason.isDeathReason); null means "the whole case", matching
    // every prior caller's behavior exactly. For a death reason with a
    // genuine SUBSET of a multi-animal case's animals, only those animals
    // are marked deceased and the case itself is left in its current
    // status (still queryable under Treatment/Intake/etc.) unless that
    // leaves every animal resolved, in which case the case is also closed.
    List<int>? animalIndexes,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final preSnap = await caseRef.get();
    final preData = preSnap.data();
    if (preData == null) throw StateError('This case no longer exists.');
    if (RescueStatus.fromFirestoreValue(
      preData['status'] as String?,
    ).isTerminal) {
      throw StateError('This case is already closed.');
    }

    final currentAssignmentId = preData['currentAssignmentId'] as String?;
    if (currentAssignmentId != null) {
      final assignmentRef = _store
          .transportAssignmentsOf(caseId)
          .doc(currentAssignmentId);
      final assignmentSnap = await assignmentRef.get();
      final assignmentStatus = assignmentSnap.data()?['status'] as String?;
      if (assignmentStatus == 'pending') {
        await _transport.cancelAssignment(
          caseId: caseId,
          assignmentId: currentAssignmentId,
          reason: 'Case closed: ${reason.label}',
        );
      } else if (assignmentStatus == 'accepted') {
        // Same effect as cancelAssignment (frees the transporter, keeps
        // full history) — completeAssignment doesn't fit here, that means
        // "the transport finished successfully", not "the case closed".
        await assignmentRef.update({
          'status': 'cancelled',
          'respondedAt': Timestamp.now(),
          'cancelledAt': Timestamp.now(),
          'cancellationReason': 'Case closed: ${reason.label}',
        });
      }
    }

    final closedFromStatus = preData['status'] as String? ?? '';
    final rawAnimals = (preData['animals'] as List?) ?? const [];
    final isPerAnimalDeath =
        reason.isDeathReason &&
        animalIndexes != null &&
        animalIndexes.isNotEmpty &&
        rawAnimals.isNotEmpty;

    final wholeCaseClosed = await _store.db.runTransaction<bool>((tx) async {
      final snap = await tx.get(caseRef);
      final data = snap.data();
      if (data == null) throw StateError('This case no longer exists.');
      if (RescueStatus.fromFirestoreValue(
        data['status'] as String?,
      ).isTerminal) {
        throw StateError('This case is already closed.');
      }

      final closureMeta = {
        if (actorRole != null && actorRole.isNotEmpty)
          'closedByRole': actorRole,
        if (organizationId != null && organizationId.isNotEmpty)
          'closedByOrganizationId': organizationId,
      };

      if (isPerAnimalDeath) {
        final animals = List<Map<String, dynamic>>.from(
          (data['animals'] as List? ?? const []).map(
            (a) => Map<String, dynamic>.from(a as Map),
          ),
        );
        final targets = animalIndexes
            .where(
              (i) =>
                  i >= 0 &&
                  i < animals.length &&
                  animals[i]['outcome'] != 'deceased',
            )
            .toList();
        if (targets.isEmpty) {
          throw StateError('The selected animal outcome is already recorded.');
        }
        final now = Timestamp.now();
        for (final i in targets) {
          animals[i] = {
            ...animals[i],
            // Same field shape RescueCaseRepository.reportAnimalDeath writes
            // (outcome/deceasedAt/deceasedReason/deceasedConfirmedBy) so
            // every existing reader (animalIsDeceased, latestConditionFor,
            // the export/transfer PDF, ...) treats a death recorded through
            // Close Case identically to one recorded through the Death
            // Report treatment-log form.
            'outcome': 'deceased',
            'deceasedAt': now,
            'deceasedReason': details,
            'deceasedConfirmedBy': actorName,
          };
        }
        final allResolved = _allAnimalsResolved(animals);
        final animalLabel = targets.length == 1
            ? ((animals[targets.first]['species'] as String?) ?? 'Animal')
            : '${targets.length} animals';
        tx.update(caseRef, {
          'animals': animals,
          ...RescueCaseStore.stageSummaryUpdate(animals),
          ...closureMeta,
          // Only the animals actually died — the case itself only becomes
          // terminal once every animal is resolved (spec §13's Animal-1-
          // died/Animal-2-still-in-treatment example: the case must NOT
          // disappear from Treatment while Animal 2 is still active).
          if (allResolved) 'status': RescueStatus.cancelled.firestoreValue,
          if (allResolved) 'closureReason': reason.name,
          if (allResolved) 'closureDetails': details,
          if (allResolved) 'closedAt': now,
          if (allResolved) 'closedBy': actorUid,
          if (allResolved) 'closedByName': actorName,
          if (allResolved) 'closedFromStatus': closedFromStatus,
          'statusHistory': FieldValue.arrayUnion([
            {
              'status':
                  'Animal death reported: $animalLabel.${allResolved ? ' All animals resolved — case closed.' : ''}',
              'timestamp': now,
            },
          ]),
        });
        return allResolved;
      }

      tx.update(caseRef, {
        'status': RescueStatus.cancelled.firestoreValue,
        'closureReason': reason.name,
        'closureDetails': details,
        'closedAt': Timestamp.now(),
        'closedBy': actorUid,
        'closedByName': actorName,
        'closedFromStatus': closedFromStatus,
        ...closureMeta,
        if (lastKnownLocation != null)
          'closureLastKnownLocation': lastKnownLocation,
        if (clinicUnavailableDetails != null)
          'closureClinicDetails': clinicUnavailableDetails,
        // Read by assign_rider_page.dart / rescue_detail_page.dart so the
        // requested service type actually shows up wherever the case is
        // presented as a service request afterward, instead of only living
        // inside the free-text closureDetails.
        if (serviceTypeNeeded != null) 'closureServiceType': serviceTypeNeeded,
        // Informational/audit only for a non-death reason applied to a
        // subset of animals — this codebase has no per-animal field for
        // "this specific animal's duplicate-report/owner-reclaimed/etc.
        // story ended" the way it does for death, so the case itself still
        // closes as a whole for every reason other than isDeathReason.
        if (animalIndexes != null)
          'closureAppliesToAnimalIndexes': animalIndexes,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Case closed: ${reason.label}.',
            'timestamp': Timestamp.now(),
          },
        ]),
      });
      return true;
    });

    await _store.addActivityLog(
      caseId: caseId,
      action: wholeCaseClosed ? 'case_closed' : 'animal_deceased',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'reason': reason.name,
        'closedFromStatus': closedFromStatus,
        if (animalIndexes != null) 'animalIndexes': animalIndexes,
      },
    );
    return wholeCaseClosed;
  }

  Future<void> closeDeceasedCase({required String caseId}) async {
    // Deliberately the literal 'closed' string, NOT
    // RescueStatus.completed.firestoreValue ('completed') — several
    // reporter-facing screens (case_summary_page.dart, case_completed_page.dart,
    // history_screen.dart, activity_feed.dart, public_rescue_feed.dart,
    // track_case_page.dart) specifically check `status == 'closed'` (or a
    // string containing 'ended') to render the somber/deceased outcome
    // rather than the ordinary completed-case tone; 'completed' alone
    // doesn't trigger that. Both values already map to RescueStatus.completed
    // via its _legacyAliases, so nothing about admin-side reads changes.
    await _store.caseDoc(caseId).update({
      'status': 'closed',
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Case closed. Animal deceased.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
  }
}
