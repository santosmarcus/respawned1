// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/rescue_status.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Assigning / changing the treating clinic of a case.
class ClinicAssignmentRepository {
  ClinicAssignmentRepository(this._store);

  final RescueCaseStore _store;

  /// Saves a clinic (picked via the map/Places search in
  /// select_clinic_sheet.dart) onto the case as flat `vetClinic*` fields —
  /// the same convention already read by treatment_detail_page.dart /
  /// intake_detail_page.dart for `vetClinicName`. This is purely
  /// informational for the admin/treatment side; it intentionally does NOT
  /// touch the `dropoff*` fields the pet-transporter app's own live routing
  /// reads (see transit_progress_page.dart) — those two "selected clinic"
  /// concepts aren't reconciled yet (see repo notes / assessment doc).
  Future<void> assignClinic({
    required String caseId,
    required String clinicName,
    String? clinicAddress,
    String? clinicPlaceId,
    double? clinicLat,
    double? clinicLng,
    String? clinicPhone,
    required String actorUid,
    required String actorName,
    // Clinic-availability warning (spec §6) — 'open'/'closed'/'unavailable'
    // from the Places result's own openNow field, never fabricated when
    // Places has no reliable hours data (openNow == null -> 'unavailable').
    // Acknowledgment fields are only set when the admin actually confirmed
    // "Proceed Anyway" on a closed clinic.
    String? availabilityStatus,
    bool closedWarningAcknowledged = false,
  }) async {
    await _store.caseDoc(caseId).update({
      'vetClinicName': clinicName,
      'vetClinicAddress': clinicAddress,
      'vetClinicPlaceId': clinicPlaceId,
      'vetClinicLat': clinicLat,
      'vetClinicLng': clinicLng,
      'vetClinicPhone': clinicPhone,
      'vetClinicSelectedAt': Timestamp.now(),
      if (availabilityStatus != null) ...{
        'clinicAvailabilityStatus': availabilityStatus,
        'clinicAvailabilityCheckedAt': Timestamp.now(),
      },
      if (closedWarningAcknowledged) ...{
        'clinicClosedWarningAcknowledgedAt': Timestamp.now(),
        'clinicClosedWarningAcknowledgedBy': actorUid,
      },
      // assignClinic is only ever called for a case's FIRST clinic (see
      // select_clinic_sheet.dart's assignClinic-vs-changeClinic branch on
      // previousClinicName), so the case is always still at
      // RescueStatus.accepted (from Rescue Review) or already at
      // RescueStatus.awaitingAssignment (animal-record admissions, which
      // start there directly — see createAdmissionCase) when this runs.
      // Writing awaitingAssignment here is a no-op for the latter and is
      // exactly the "clinic saved -> ready to assign" transition for the
      // former.
      'status': RescueStatus.awaitingAssignment.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Assigned to clinic: $clinicName.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'assigned_clinic',
      actorUid: actorUid,
      actorName: actorName,
      details: {'clinicPlaceId': clinicPlaceId, 'clinicName': clinicName},
    );
  }

  /// Clinic reselection during tracking (spec §7) — same fields/write
  /// pattern as [assignClinic] (never a new assignment/case, never marks
  /// the transporter assignment completed), just a more specific
  /// statusHistory message naming both clinics, and its own activity-log
  /// action so "changed" is distinguishable from the initial "assigned".
  /// The old clinic is never erased from history — every prior
  /// `assigned_clinic`/`changed_clinic` activity-log entry and every past
  /// `statusHistory` line naming it stays exactly as written.
  Future<void> changeClinic({
    required String caseId,
    required String previousClinicName,
    required String clinicName,
    String? clinicAddress,
    String? clinicPlaceId,
    double? clinicLat,
    double? clinicLng,
    String? clinicPhone,
    required String actorUid,
    required String actorName,
    String? availabilityStatus,
    bool closedWarningAcknowledged = false,
  }) async {
    await _store.caseDoc(caseId).update({
      'vetClinicName': clinicName,
      'vetClinicAddress': clinicAddress,
      'vetClinicPlaceId': clinicPlaceId,
      'vetClinicLat': clinicLat,
      'vetClinicLng': clinicLng,
      'vetClinicPhone': clinicPhone,
      'vetClinicSelectedAt': Timestamp.now(),
      if (availabilityStatus != null) ...{
        'clinicAvailabilityStatus': availabilityStatus,
        'clinicAvailabilityCheckedAt': Timestamp.now(),
      },
      if (closedWarningAcknowledged) ...{
        'clinicClosedWarningAcknowledgedAt': Timestamp.now(),
        'clinicClosedWarningAcknowledgedBy': actorUid,
      },
      // Clears any stale route/ETA computed for the old clinic — the
      // tracking map recalculates (or falls back to a straight line) once
      // it sees a new vetClinicLat/Lng with no matching cached route.
      'cachedRoutePolyline': FieldValue.delete(),
      'cachedRouteDistanceKm': FieldValue.delete(),
      'cachedRouteEtaMinutes': FieldValue.delete(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Clinic changed from $previousClinicName to $clinicName.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'changed_clinic',
      actorUid: actorUid,
      actorName: actorName,
      details: {
        'previousClinicName': previousClinicName,
        'clinicPlaceId': clinicPlaceId,
        'clinicName': clinicName,
      },
    );
  }
}
