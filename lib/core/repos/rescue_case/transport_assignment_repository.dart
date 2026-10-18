// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Pet-transporter roster and the transport-assignment lifecycle: offer,
/// accept, reject, cancel, reconcile, complete, and safety follow-ups.
class TransportAssignmentRepository {
  TransportAssignmentRepository(this._store);

  final RescueCaseStore _store;

  /// Every account with role == 'pet_transporter' — the exact string
  /// onboard_screen.dart / role_screen.dart write to `users/{uid}.role`.
  /// Excludes general users, org admins/staff, and rescue volunteers, none
  /// of which share that value. If Firestore ever needs a composite index
  /// for this (it currently doesn't — it's a single equality filter with no
  /// orderBy), the console error surfaces a direct link to create it.
  Stream<List<PetTransporter>> streamPetTransporters() {
    return _store.users
        .where('role', isEqualTo: 'pet_transporter')
        .snapshots()
        .map((snap) => snap.docs.map(PetTransporter.fromFirestore).toList());
  }

  /// Every account with role == 'rescue_volunteer' — the other real
  /// signup role from onboard_screen.dart / role_screen.dart, currently
  /// routed to the same ServiceScreen as pet_transporter (see main.dart's
  /// AuthWrapper), so it writes the exact same users/{uid} shape
  /// (name/phone/online/lastSeenAt/transporterVerification) that
  /// [PetTransporter] already models — reused as-is rather than a second
  /// near-identical model, since the Volunteers directory (spec §7) needs
  /// the same fields (name, online/availability, contact).
  Stream<List<PetTransporter>> streamRescueVolunteers() {
    return _store.users
        .where('role', isEqualTo: 'rescue_volunteer')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => PetTransporter.fromFirestore(
                  doc,
                  unnamedLabel: 'Unnamed Volunteer',
                ),
              )
              .toList(),
        );
  }

  /// Resolves display-ready transporter details (vehicle/plate/photo/phone)
  /// for the Intake Details default-transporter display and the shared
  /// TransporterDetailsCard on Track Case — an accepted transportAssignment
  /// only carries riderId/riderName/riderType, never vehicle/plate, so
  /// those come from `users/{uid}` for real transporters, or the same
  /// fixed values assign_rider_page.dart uses for the two demo
  /// transporters. Never throws — an unresolvable/missing profile falls
  /// back to safe placeholder text rather than surfacing an error.
  Future<TransporterProfile> resolveTransporterProfile({
    required String uid,
    required String fallbackName,
    required String type,
    required bool isDemo,
  }) async {
    if (isDemo) {
      final vehicle = uid == 'demo-rider-a'
          ? 'Yamaha NMAX'
          : (uid == 'demo-rider-b' ? 'Honda Click' : 'Not provided');
      final plate = uid == 'demo-rider-a'
          ? 'DEMO-001'
          : (uid == 'demo-rider-b' ? 'DEMO-002' : 'Not provided');
      return TransporterProfile(
        uid: uid,
        name: fallbackName,
        type: type,
        vehicle: vehicle,
        plate: plate,
        isDemo: true,
      );
    }
    try {
      final doc = await _store.users.doc(uid).get();
      if (!doc.exists) {
        return TransporterProfile(
          uid: uid,
          name: fallbackName,
          type: type,
          vehicle: 'Not provided',
          plate: 'Not provided',
          isDemo: false,
        );
      }
      final pt = PetTransporter.fromFirestore(doc);
      return TransporterProfile(
        uid: uid,
        name: pt.name.isNotEmpty && pt.name != 'Unnamed Transporter'
            ? pt.name
            : fallbackName,
        type: type,
        photoUrl: pt.photoUrl,
        phone: pt.phone,
        vehicle: pt.vehicleType ?? 'Not provided',
        plate: pt.licensePlate ?? 'Not provided',
        isDemo: false,
      );
    } catch (_) {
      return TransporterProfile(
        uid: uid,
        name: fallbackName,
        type: type,
        vehicle: 'Not provided',
        plate: 'Not provided',
        isDemo: false,
      );
    }
  }

  /// The most recently offered rider assignment for a case, regardless of
  /// its status — this is what gates AdminTrackCasePage between the
  /// Pending / Rejected / actual tracking views. A newer offer (e.g. after
  /// "Choose Another Rider" following a rejection) naturally supersedes an
  /// older rejected one just by having a later `offeredAt`.
  Stream<TransportAssignment?> streamLatestAssignment(String caseId) {
    return _store
        .transportAssignmentsOf(caseId)
        .orderBy('offeredAt', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snap) => snap.docs.isEmpty
              ? null
              : TransportAssignment.fromFirestore(snap.docs.first, caseId),
        );
  }

  /// Each transporter's status, derived from their single most-recent
  /// assignment doc across ALL cases (any status) — one collection-group
  /// query instead of one per rider card. The caller (Assign Transporter's
  /// availability bucketing) treats a `rejected` latest assignment the same
  /// as `accepted` — i.e. Busy, not immediately Available again — per the
  /// current testing workflow's requirement that a transporter who just
  /// declined doesn't loop straight back into the selectable pool; only a
  /// later `completed`/`cancelled` (or no assignment at all) reads as
  /// Available. Requires a Firestore collection-group index on
  /// `transportAssignments` for `offeredAt` (single-field, collection-group
  /// scope) — the first live query prints the console's direct
  /// create-index link if it's still missing.
  Stream<Map<String, TransportAssignmentStatus>>
  streamActiveAssignmentsByRider() {
    return _store.db
        .collectionGroup('transportAssignments')
        .orderBy('offeredAt', descending: true)
        .snapshots()
        .map((snap) {
          final latestByRider = <String, TransportAssignmentStatus>{};
          for (final doc in snap.docs) {
            final riderId = doc.data()['riderId'] as String?;
            // Docs arrive newest-first, so the first one seen per rider is
            // already their most recent — never overwrite after that.
            if (riderId == null || latestByRider.containsKey(riderId)) continue;
            latestByRider[riderId] = TransportAssignmentStatus.fromName(
              doc.data()['status'] as String?,
            );
          }
          return latestByRider;
        });
  }

  /// Every still-`pending` offer across every case whose own [expiresAt] has
  /// already passed (see [TransportAssignment.isStalePending]) — this is a
  /// genuine "needs attention" signal (spec's "Rejected, expired, or
  /// unanswered transporter offers" Action Required item), not a fabricated
  /// threshold: staleness is judged against the offer's own already-recorded
  /// `expiresAt`/`kTransportOfferTtl`, never an admin-configurable cutoff
  /// invented here. Filters `status == pending` server-side, then
  /// `isStalePending` client-side (Firestore can't compare two fields), so
  /// the read stays bounded to the (normally small) set of open offers
  /// rather than every assignment doc ever created.
  Stream<List<TransportAssignment>> streamStalePendingAssignments() {
    return _store.db
        .collectionGroup('transportAssignments')
        .where('status', isEqualTo: TransportAssignmentStatus.pending.name)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => TransportAssignment.fromFirestore(
                  d,
                  d.reference.parent.parent!.id,
                ),
              )
              .where((a) => a.isStalePending)
              .toList(),
        );
  }

  /// Creates a new pending transporter offer. Guarded by a transaction
  /// against creating a second active (pending/accepted) offer for the same
  /// case — the case doc's own `currentAssignmentId` pointer is read and
  /// checked inside the same transaction, so two admins tapping "Confirm" at
  /// the same moment can't both succeed. Does NOT touch the case's own
  /// RescueStatus or assignedVolunteer* fields — those only change once the
  /// transporter actually accepts (see [acceptAssignment]).
  ///
  /// Deliberately never looks at `acceptedBy`/the accepting admin's uid, or
  /// the case's own RescueStatus — a case being accepted (by any admin) is
  /// a separate concept from a transporter being assigned, and does not
  /// block this call on its own. The only thing that can block a new offer
  /// is the assignment document the pointer resolves to, read fresh inside
  /// this same transaction:
  ///  - pointer -> pending assignment: blocked, [ActiveAssignmentConflictException]
  ///  - pointer -> accepted assignment: blocked unless [allowReassign] is
  ///    true (the explicit Reassign Transporter path), in which case the
  ///    prior assignment is marked `cancelled` (superseded) in the same
  ///    transaction so that transporter frees back up elsewhere.
  ///  - pointer -> rejected/cancelled/completed, or a missing (dangling)
  ///    document: never blocks — the stale pointer is simply overwritten by
  ///    the new offer's id below, which is itself the reconciliation (no
  ///    separate clear-then-write race is possible since it's all one
  ///    transaction).
  Future<String> createAssignmentOffer({
    required String caseId,
    required String riderId,
    required String riderName,
    required String riderType,
    bool isDemo = false,
    bool allowReassign = false,
    String? vehicle,
    String? plate,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentsCol = _store.transportAssignmentsOf(caseId);
    final newRef = assignmentsCol.doc();

    await _store.db.runTransaction((tx) async {
      final caseSnap = await tx.get(caseRef);
      // Revalidate presence here, not just in the UI's rider list — that
      // list may already be stale by the time the admin taps Confirm (the
      // transporter could have gone offline moments ago). Demo riders have
      // no real presence data and are exempt.
      if (!isDemo) {
        final riderSnap = await tx.get(_store.users.doc(riderId));
        final riderData = riderSnap.data();
        final online = riderData?['online'] as bool? ?? false;
        final lastSeen = riderData?['lastSeenAt'];
        final lastSeenAt = lastSeen is Timestamp ? lastSeen.toDate() : null;
        final stillOnline =
            online &&
            lastSeenAt != null &&
            DateTime.now().difference(lastSeenAt) <=
                kTransporterPresenceThreshold;
        if (!stillOnline) {
          throw const TransporterNoLongerOnlineException();
        }
      }
      final currentId = caseSnap.data()?['currentAssignmentId'] as String?;
      if (currentId != null) {
        final currentSnap = await tx.get(assignmentsCol.doc(currentId));
        final currentData = currentSnap.data();
        final currentStatus = currentData?['status'] as String?;

        if (currentStatus == 'pending') {
          throw ActiveAssignmentConflictException.fromMap(
            currentId,
            currentData!,
          );
        }
        if (currentStatus == 'accepted') {
          if (!allowReassign) {
            throw ActiveAssignmentConflictException.fromMap(
              currentId,
              currentData!,
            );
          }
          // Explicit Reassign Transporter workflow: supersede the prior
          // accepted assignment rather than leaving it dangling as
          // "accepted" forever (which would otherwise keep that
          // transporter showing Busy elsewhere).
          final now = Timestamp.now();
          tx.update(assignmentsCol.doc(currentId), {
            'status': 'cancelled',
            'respondedAt': now,
            'cancelledAt': now,
            'cancellationReason': 'Reassigned to a different transporter',
          });
        } else if (currentStatus == null && kDebugMode) {
          // Dangling pointer: currentId is set but the doc it references no
          // longer exists. Not an error — just logged for visibility — the
          // pointer is reconciled below by being overwritten unconditionally.
          debugPrint(
            'RescueCaseRepository: currentAssignmentId=$currentId on case $caseId points to a missing assignment document — clearing.',
          );
        }
        // rejected / cancelled / completed: nothing to do here, the
        // pointer overwrite below is the reconciliation.
      }
      final offeredAt = Timestamp.now();
      tx.set(newRef, {
        'caseId': caseId,
        'riderId': riderId,
        'riderName': riderName,
        'riderType': riderType,
        'status': 'pending',
        'offeredAt': offeredAt,
        'expiresAt': Timestamp.fromDate(
          offeredAt.toDate().add(kTransportOfferTtl),
        ),
        'respondedAt': null,
        'acceptedAt': null,
        'rejectedAt': null,
        'rejectionReason': null,
        'completedAt': null,
        'isDemo': isDemo,
        if (vehicle != null) 'vehicle': vehicle,
        if (plate != null) 'plate': plate,
      });
      tx.update(caseRef, {'currentAssignmentId': newRef.id});
    });
    return newRef.id;
  }

  /// Marks an offer accepted and, in the same transaction, updates the
  /// case's existing assignedVolunteer*/status fields the same way the
  /// original direct-write flow did — so treatment_detail_page.dart,
  /// intake_detail_page.dart, etc. keep working unmodified. A no-op if the
  /// offer is no longer pending (already accepted/rejected elsewhere),
  /// guarding against a double-accept (e.g. a duplicate demo timer or two
  /// taps racing each other).
  Future<void> acceptAssignment({
    required String caseId,
    required String assignmentId,
    required String riderId,
    required String riderName,
    required String riderVehicle,
    required String riderPlate,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentRef = _store
        .transportAssignmentsOf(caseId)
        .doc(assignmentId);

    try {
      await _store.db.runTransaction((tx) async {
        // All reads before any writes — a transaction that interleaves a
        // read after a write (as this method used to for the case doc, and
        // as cancelAssignment used to as well) throws on every run and the
        // write silently never commits. See cancelAssignment's doc comment
        // for the full incident this class of bug caused.
        final snap = await tx.get(assignmentRef);
        final caseSnap = await tx.get(caseRef);

        if (!snap.exists) {
          throw const OfferNoLongerAvailableException(
            'assignment no longer exists',
          );
        }
        final data = snap.data()!;
        if (data['status'] != 'pending') {
          throw OfferNoLongerAvailableException(
            'status is ${data['status']}, not pending',
          );
        }
        if (caseSnap.data()?['currentAssignmentId'] != assignmentId) {
          // The case has moved on to a newer offer (or none) since this one
          // was created — a stale/superseded offer trying to resurrect
          // itself. Ignore rather than accept.
          throw const OfferNoLongerAvailableException(
            'a newer offer has superseded this one',
          );
        }
        final expiresAt = data['expiresAt'];
        final now = Timestamp.now();
        if (expiresAt is Timestamp && now.compareTo(expiresAt) > 0) {
          // Clean up in place instead of accepting a stale offer.
          tx.update(assignmentRef, {'status': 'expired', 'respondedAt': now});
          tx.update(caseRef, {'currentAssignmentId': FieldValue.delete()});
          throw const OfferNoLongerAvailableException('offer expired');
        }

        tx.update(assignmentRef, {
          'status': 'accepted',
          'respondedAt': now,
          'acceptedAt': now,
          'vehicle': riderVehicle,
          'plate': riderPlate,
        });
        tx.update(caseRef, {
          'status': 'assigned',
          'riderId': riderId,
          'assignedVolunteerId': riderId,
          'assignedVolunteerName': riderName,
          'assignedVehicle': riderVehicle,
          'assignedPlate': riderPlate,
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': 'Pet transporter assigned: $riderName.',
              'timestamp': now,
            },
          ]),
        });
      });
    } on FirebaseException catch (error, stackTrace) {
      _logAssignmentFailure(
        operation: 'acceptAssignment',
        caseId: caseId,
        assignmentId: assignmentId,
        riderId: riderId,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Marks an offer rejected with [reason]. Deliberately never changes the
  /// rescue case's own RescueStatus or clears assignedVolunteer* fields —
  /// those were never set for a merely-pending offer in the first place, so
  /// the case is already back in its assignable state as soon as this
  /// resolves; a rider's rejection is not a rescue-case rejection. A no-op
  /// if the offer is no longer pending, guarding against a double-reject.
  Future<void> rejectAssignment({
    required String caseId,
    required String assignmentId,
    required String reason,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentRef = _store
        .transportAssignmentsOf(caseId)
        .doc(assignmentId);
    try {
      await _store.db.runTransaction((tx) async {
        final snap = await tx.get(assignmentRef);
        final caseSnap = await tx.get(caseRef);
        if (!snap.exists) {
          throw const OfferNoLongerAvailableException(
            'assignment no longer exists',
          );
        }
        final data = snap.data()!;
        if (data['status'] != 'pending') {
          throw OfferNoLongerAvailableException(
            'status is ${data['status']}, not pending',
          );
        }
        final expiresAt = data['expiresAt'];
        final now = Timestamp.now();
        if (expiresAt is Timestamp && now.compareTo(expiresAt) > 0) {
          tx.update(assignmentRef, {'status': 'expired', 'respondedAt': now});
          if (caseSnap.data()?['currentAssignmentId'] == assignmentId) {
            tx.update(caseRef, {'currentAssignmentId': FieldValue.delete()});
          }
          throw const OfferNoLongerAvailableException('offer expired');
        }
        tx.update(assignmentRef, {
          'status': 'rejected',
          'respondedAt': now,
          'rejectedAt': now,
          'rejectionReason': reason,
        });
      });
    } on FirebaseException catch (error, stackTrace) {
      _logAssignmentFailure(
        operation: 'rejectAssignment',
        caseId: caseId,
        assignmentId: assignmentId,
        riderId: null,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Organization-initiated cancellation of a still-pending offer — the
  /// "Back" path out of the pending-assignment modal, for a transporter
  /// (typically a real one, with no accept/reject UI of their own yet)
  /// whose response might never come. Never deletes the assignment doc —
  /// full offer history (including this cancellation) is preserved, only
  /// the status changes. Clears the case's `currentAssignmentId` pointer
  /// only if it still points at *this* assignment (guards against a race
  /// where a newer offer was already created by the time this resolves).
  /// A no-op if the offer is no longer pending, guarding against
  /// double-cancellation.
  ///
  /// IMPORTANT: both `tx.get()` calls must happen before either `tx.update()`
  /// call — Firestore transactions require every read to precede every write
  /// in the same transaction, or the transaction throws on every attempt and
  /// silently never commits. An earlier version of this method read the
  /// assignment, wrote to it, and only then read the case doc — which meant
  /// cancellation *always* failed (surfacing as "Could not cancel this
  /// offer.") while leaving the assignment doc's status as 'pending' in
  /// Firestore. That, combined with the demo-response timer in
  /// assign_rider_page.dart re-reading the doc fresh a few seconds later and
  /// finding it still 'pending', is what let a "cancelled" demo transporter
  /// become "accepted" after the fact. Do not reorder these calls.
  Future<void> cancelAssignment({
    required String caseId,
    required String assignmentId,
    String? reason,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentRef = _store
        .transportAssignmentsOf(caseId)
        .doc(assignmentId);
    try {
      await _store.db.runTransaction((tx) async {
        final snap = await tx.get(assignmentRef);
        final caseSnap = await tx.get(caseRef);
        if (!snap.exists || snap.data()?['status'] != 'pending') return;
        final now = Timestamp.now();
        tx.update(assignmentRef, {
          'status': 'cancelled',
          'respondedAt': now,
          'cancelledAt': now,
          if (reason != null && reason.isNotEmpty) 'cancellationReason': reason,
        });
        if (caseSnap.data()?['currentAssignmentId'] == assignmentId) {
          tx.update(caseRef, {'currentAssignmentId': FieldValue.delete()});
        }
      });
    } on FirebaseException catch (error, stackTrace) {
      _logAssignmentFailure(
        operation: 'cancelAssignment',
        caseId: caseId,
        assignmentId: assignmentId,
        riderId: null,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Opportunistic cleanup for a pending offer whose TTL has elapsed,
  /// without an accept/reject/cancel ever having been attempted on it.
  /// Called from screens that read the latest assignment for a case (spec
  /// §4's startup-resolution behavior), never on a timer of its own — there
  /// is no server-side expiry job. Safe to call redundantly; a no-op unless
  /// the offer is still 'pending' and past its `expiresAt`.
  Future<void> reconcileStaleOffer({
    required String caseId,
    required String assignmentId,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final assignmentRef = _store
        .transportAssignmentsOf(caseId)
        .doc(assignmentId);
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      final caseSnap = await tx.get(caseRef);
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['status'] != 'pending') return;
      final expiresAt = data['expiresAt'];
      if (expiresAt is! Timestamp) return;
      if (Timestamp.now().compareTo(expiresAt) <= 0) return;
      tx.update(assignmentRef, {
        'status': 'expired',
        'respondedAt': Timestamp.now(),
      });
      if (caseSnap.data()?['currentAssignmentId'] == assignmentId) {
        tx.update(caseRef, {'currentAssignmentId': FieldValue.delete()});
      }
    });
  }

  /// Development diagnostics only (spec §6) — never surfaced in production
  /// UI copy, which stays a plain user-facing message at the call site.
  void _logAssignmentFailure({
    required String operation,
    required String caseId,
    required String assignmentId,
    required String? riderId,
    required FirebaseException error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) return;
    debugPrint('Transporter assignment operation failed: $operation');
    debugPrint('caseId: $caseId');
    debugPrint('assignmentId: $assignmentId');
    if (riderId != null) debugPrint('riderId: $riderId');
    debugPrint('code: ${error.code}');
    debugPrint('message: ${error.message}');
    debugPrint('plugin: ${error.plugin}');
    debugPrintStack(stackTrace: stackTrace);
  }

  /// Closes out an accepted assignment once the animal has reached
  /// treatment — this is what frees a demo/real rider back to "Available"
  /// (streamActiveAssignmentsByRider only counts pending/accepted).
  Future<void> completeAssignment({
    required String caseId,
    required String assignmentId,
  }) async {
    await _store.transportAssignmentsOf(caseId).doc(assignmentId).update({
      'status': 'completed',
      'completedAt': Timestamp.now(),
    });
  }

  /// "Retry with a different transporter" after a transporter's safety
  /// report (needsSpecializedAssistance, set by the real transporter app's
  /// own End Reason flow in transit_progress_page.dart — see
  /// [RescueStatus.needsSpecializedAssistance]'s own doc comment). Returns
  /// the case to [RescueStatus.awaitingAssignment] so Assign Transporter
  /// is reachable again, WITHOUT touching `endReason`/`endReasonNotes` —
  /// the original transporter's report is never erased, it just stops
  /// being the case's *current* blocking state. Does not itself pick or
  /// assign anyone; the caller still navigates to Assign Transporter and
  /// the admin manually selects someone.
  Future<void> resumeAssignmentAfterSafetyReport({
    required String caseId,
    required String actorUid,
    required String actorName,
  }) async {
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.awaitingAssignment.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':
              'Case returned to Assign after a transporter safety report — a different transporter may now be selected.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'resumed_after_safety_report',
      actorUid: actorUid,
      actorName: actorName,
    );
  }

  /// "Keep current transporter and provide instructions" — records the
  /// admin's guidance without changing status (the case stays
  /// needsSpecializedAssistance until the admin explicitly resolves it some
  /// other way) or touching the original report.
  Future<void> addSafetyResponseNote({
    required String caseId,
    required String note,
    required String actorUid,
    required String actorName,
  }) async {
    await _store.caseDoc(caseId).update({
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Instructions provided to transporter: $note',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'safety_response_instructions',
      actorUid: actorUid,
      actorName: actorName,
      details: {'note': note},
    );
  }
}
