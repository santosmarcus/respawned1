import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';

/// Firestore access for the admin rescue module. Reads/writes the existing
/// `cases` collection (shared with the reporter and pet-transporter apps —
/// see the doc comment on [RescueCase]) plus its new
/// `reports` / `referrals` / `activityLogs` subcollections.
///
/// Every write here is a partial `update()`/`set(..., merge: true)` or a
/// transaction — never a full-document overwrite — so fields owned by
/// other features are never clobbered.
class RescueCaseRepository {
  RescueCaseRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _cases => _db.collection('cases');
  DocumentReference<Map<String, dynamic>> _caseDoc(String caseId) => _cases.doc(caseId);
  CollectionReference<Map<String, dynamic>> _reportsOf(String caseId) =>
      _caseDoc(caseId).collection('reports');
  CollectionReference<Map<String, dynamic>> _referralsOf(String caseId) =>
      _caseDoc(caseId).collection('referrals');
  CollectionReference<Map<String, dynamic>> _activityLogsOf(String caseId) =>
      _caseDoc(caseId).collection('activityLogs');
  // Same subcollection the user-side track_case_page.dart's
  // _CommunityReportSection already reads/writes — reused here read-only,
  // not a second storage structure.
  CollectionReference<Map<String, dynamic>> _communityReportsOf(String caseId) =>
      _caseDoc(caseId).collection('communityReports');
  CollectionReference<Map<String, dynamic>> _transportAssignmentsOf(String caseId) =>
      _caseDoc(caseId).collection('transportAssignments');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> _treatmentLogsOf(String caseId) =>
      _caseDoc(caseId).collection('treatmentLogs');
  CollectionReference<Map<String, dynamic>> _expensesOf(String caseId) =>
      _caseDoc(caseId).collection('expenses');
  // Top-level collection — see create_animal_record_page.dart /
  // animal_record_detail_page.dart, both already established. Reused as-is
  // (linkedCaseId is the existing case-reference field); only
  // sourceAnimalIndex is genuinely new, for multi-animal duplicate
  // prevention.
  CollectionReference<Map<String, dynamic>> get _animals => _db.collection('animals');

  // ---- Reads ----------------------------------------------------------

  /// Streams every case whose status resolves to one of [statuses]. Client
  /// filters (urgency/species/date/location/search) are applied on top by
  /// the caller — Firestore can't combine an array-membership status query
  /// with several other equality/range filters efficiently on this schema.
  Stream<List<RescueCase>> streamCasesByStatuses(List<RescueStatus> statuses) {
    final values = statuses.expand((s) => s.queryValues).toSet().toList();
    if (values.isEmpty) return Stream.value(const []);
    // Firestore whereIn supports up to 30 values; our alias lists are well
    // under that even for the broadest status (ongoing).
    return _cases
        .where('status', whereIn: values)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(RescueCase.fromFirestore).where(_isPrimaryGroupMember).toList());
  }

  /// Backward compatibility for reports submitted before multi-animal
  /// reports were consolidated into a single doc with an `animals` array:
  /// older multi-animal reports wrote one case doc per animal, linked by a
  /// shared `groupId` (see rescue_page.dart's prior submission logic).
  /// Without this filter, Rescue Reports would still show one card per
  /// sibling doc for any of that older data. Keeps only the "primary" doc
  /// of a group (the one whose own id equals the shared groupId) — mirrors
  /// the same collapsing already done in public_rescue_feed.dart and
  /// activity_feed.dart. New submissions never set `groupId`, so they pass
  /// through untouched.
  bool _isPrimaryGroupMember(RescueCase c) {
    final groupId = c.raw['groupId'] as String?;
    return groupId == null || groupId.isEmpty || groupId == c.id;
  }

  Stream<RescueCase?> streamCase(String caseId) {
    return _caseDoc(caseId).snapshots().map(
          (doc) => doc.exists ? RescueCase.fromFirestore(doc) : null,
        );
  }

  /// Chronological (oldest first) treatment history for a case — merges the
  /// new append-only `treatmentLogs` subcollection with any entries still
  /// sitting only in the legacy `treatmentLog` array field on the case doc
  /// itself (written by the old treatment_detail_page.dart before this
  /// subcollection existed). Legacy entries are read-only here — every new
  /// write goes to the subcollection exclusively, so the array field never
  /// grows again; it just isn't discarded for cases that already have it.
  Stream<List<TreatmentLogEntry>> streamTreatmentLogs(String caseId) {
    return _treatmentLogsOf(caseId).orderBy('timestamp').snapshots().asyncMap((snap) async {
      final subcollectionLogs = snap.docs.map((d) => TreatmentLogEntry.fromFirestore(d, caseId)).toList();
      if (subcollectionLogs.isNotEmpty) return subcollectionLogs;

      // Only fall back to the legacy array if the subcollection is
      // genuinely empty — once a case has any real log entries, those are
      // the source of truth and legacy data (if any) has already been
      // migrated forward by the first new write's own read, avoiding a
      // second Firestore read on every snapshot for cases with real data.
      final caseSnap = await _caseDoc(caseId).get();
      final legacy = List<Map<String, dynamic>>.from(caseSnap.data()?['treatmentLog'] ?? const []);
      return [
        for (var i = 0; i < legacy.length; i++) TreatmentLogEntry.fromLegacyMap(legacy[i], caseId, i),
      ];
    });
  }

  Stream<List<Expense>> streamExpenses(String caseId) {
    return _expensesOf(caseId).orderBy('incurredAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => Expense.fromFirestore(d, caseId)).toList(),
        );
  }

  /// Which animal-array indexes already have a created record for this
  /// case — drives both the "N of M records created" progress and
  /// duplicate-prevention in the multi-animal creation flow (checked
  /// client-side against this single query rather than a second
  /// composite-indexed query per animal).
  Stream<Set<int>> streamCompletedAnimalRecordIndexes(String caseId) {
    return _animals.where('linkedCaseId', isEqualTo: caseId).snapshots().map(
          (snap) => snap.docs
              .map((d) => (d.data()['sourceAnimalIndex'] as num?)?.toInt())
              .whereType<int>()
              .toSet(),
        );
  }

  Stream<List<RescueReport>> streamReports(String caseId) {
    return _reportsOf(caseId).orderBy('submittedAt').snapshots().map(
          (snap) => snap.docs.map((d) => RescueReport.fromFirestore(d, caseId)).toList(),
        );
  }

  Stream<List<Referral>> streamReferrals(String caseId) {
    return _referralsOf(caseId).orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => Referral.fromFirestore(d, caseId)).toList(),
        );
  }

  Stream<List<ActivityLogEntry>> streamActivityLogs(String caseId) {
    return _activityLogsOf(caseId).orderBy('timestamp', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => ActivityLogEntry.fromFirestore(d, caseId)).toList(),
        );
  }

  Stream<List<CommunityReport>> streamCommunityReports(String caseId) {
    return _communityReportsOf(caseId).orderBy('timestamp', descending: true).snapshots().map(
          (snap) => snap.docs.map(CommunityReport.fromFirestore).toList(),
        );
  }

  /// Every account with role == 'pet_transporter' — the exact string
  /// onboard_screen.dart / role_screen.dart write to `users/{uid}.role`.
  /// Excludes general users, org admins/staff, and rescue volunteers, none
  /// of which share that value. If Firestore ever needs a composite index
  /// for this (it currently doesn't — it's a single equality filter with no
  /// orderBy), the console error surfaces a direct link to create it.
  Stream<List<PetTransporter>> streamPetTransporters() {
    return _users.where('role', isEqualTo: 'pet_transporter').snapshots().map(
          (snap) => snap.docs.map(PetTransporter.fromFirestore).toList(),
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
      final plate =
          uid == 'demo-rider-a' ? 'DEMO-001' : (uid == 'demo-rider-b' ? 'DEMO-002' : 'Not provided');
      return TransporterProfile(
          uid: uid, name: fallbackName, type: type, vehicle: vehicle, plate: plate, isDemo: true);
    }
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists) {
        return TransporterProfile(
            uid: uid, name: fallbackName, type: type, vehicle: 'Not provided', plate: 'Not provided', isDemo: false);
      }
      final pt = PetTransporter.fromFirestore(doc);
      return TransporterProfile(
        uid: uid,
        name: pt.name.isNotEmpty && pt.name != 'Unnamed Transporter' ? pt.name : fallbackName,
        type: type,
        photoUrl: pt.photoUrl,
        phone: pt.phone,
        vehicle: pt.vehicleType ?? 'Not provided',
        plate: pt.licensePlate ?? 'Not provided',
        isDemo: false,
      );
    } catch (_) {
      return TransporterProfile(
          uid: uid, name: fallbackName, type: type, vehicle: 'Not provided', plate: 'Not provided', isDemo: false);
    }
  }

  /// The most recently offered rider assignment for a case, regardless of
  /// its status — this is what gates AdminTrackCasePage between the
  /// Pending / Rejected / actual tracking views. A newer offer (e.g. after
  /// "Choose Another Rider" following a rejection) naturally supersedes an
  /// older rejected one just by having a later `offeredAt`.
  Stream<TransportAssignment?> streamLatestAssignment(String caseId) {
    return _transportAssignmentsOf(caseId)
        .orderBy('offeredAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : TransportAssignment.fromFirestore(snap.docs.first, caseId));
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
  Stream<Map<String, TransportAssignmentStatus>> streamActiveAssignmentsByRider() {
    return _db
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
        latestByRider[riderId] = TransportAssignmentStatus.fromName(doc.data()['status'] as String?);
      }
      return latestByRider;
    });
  }

  /// Naive possible-duplicate lookup: other active cases (pending/awaiting
  /// assignment/ongoing) of the same species, ranked by distance from
  /// [source]. There's no geohashing index on this collection, so this
  /// pulls a bounded window of same-species active cases and computes
  /// distance client-side rather than doing a true geo query.
  Future<List<RescueCase>> findPossibleDuplicates(
    RescueCase source, {
    double radiusKm = 1.0,
    int limit = 20,
  }) async {
    if (source.animalType == null || source.lat == null || source.lng == null) {
      return const [];
    }
    final activeStatuses = [
      RescueStatus.pendingReview,
      RescueStatus.awaitingAssignment,
      RescueStatus.ongoing,
    ].expand((s) => s.queryValues).toSet().toList();

    final snap = await _cases
        .where('animalType', isEqualTo: source.animalType)
        .where('status', whereIn: activeStatuses)
        .limit(50)
        .get();

    final candidates = snap.docs
        .map(RescueCase.fromFirestore)
        .where((c) => c.id != source.id && c.lat != null && c.lng != null)
        .toList();

    candidates.sort((a, b) {
      final da = _distanceKm(source.lat!, source.lng!, a.lat!, a.lng!);
      final db = _distanceKm(source.lat!, source.lng!, b.lat!, b.lng!);
      return da.compareTo(db);
    });

    return candidates
        .where((c) => _distanceKm(source.lat!, source.lng!, c.lat!, c.lng!) <= radiusKm)
        .take(limit)
        .toList();
  }

  double distanceKmBetween(RescueCase a, RescueCase b) {
    if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) {
      return double.infinity;
    }
    return _distanceKm(a.lat!, a.lng!, b.lat!, b.lng!);
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double deg2rad(double deg) => deg * (math.pi / 180.0);
    final dLat = deg2rad(lat2 - lat1);
    final dLng = deg2rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(deg2rad(lat1)) * math.cos(deg2rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  // ---- Actions ----------------------------------------------------------

  /// [openForTransfer] only saves a flag on the case (RescueCase.openForTransfer)
  /// — there is no open-transfer listing, cross-org browsing, or transfer
  /// request/acceptance workflow yet. That's intentionally deferred.
  Future<void> acceptCase({
    required String caseId,
    required String actorUid,
    required String actorName,
    bool openForTransfer = false,
  }) async {
    await _caseDoc(caseId).update({
      'status': RescueStatus.awaitingAssignment.firestoreValue,
      'openForTransfer': openForTransfer,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': openForTransfer
              ? 'Rescue case has been accepted and marked open for transfer to another organization.'
              : 'Rescue case has been accepted.',
          'timestamp': Timestamp.now(),
        }
      ]),
    });
    await addActivityLog(
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
    await _caseDoc(caseId).update({
      'status': RescueStatus.rejected.firestoreValue,
      'rejectionReason': reason.name,
      if (reason == RejectionReason.other && otherText != null)
        'rejectionReasonOther': otherText,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Case rejected: ${reason == RejectionReason.other ? (otherText ?? reason.label) : reason.label}.',
          'timestamp': Timestamp.now(),
        }
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'rejected',
      actorUid: actorUid,
      actorName: actorName,
      details: {'reason': reason.name, if (otherText != null) 'otherText': otherText},
    );
  }

  Future<void> flagPossibleDuplicate({
    required String caseId,
    required String duplicateOfCaseId,
    required String actorUid,
    required String actorName,
  }) async {
    await _caseDoc(caseId).update({
      'status': RescueStatus.possibleDuplicate.firestoreValue,
      'possibleDuplicateOfCaseId': duplicateOfCaseId,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Flagged as a possible duplicate report.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'flagged_possible_duplicate',
      actorUid: actorUid,
      actorName: actorName,
      details: {'duplicateOfCaseId': duplicateOfCaseId},
    );
  }

  /// Reverts a possibleDuplicate case back to normal triage after the org
  /// decides the two reports are NOT the same incident.
  Future<void> keepSeparate({
    required String caseId,
    required String actorUid,
    required String actorName,
  }) async {
    await _caseDoc(caseId).update({
      'status': RescueStatus.pendingReview.firestoreValue,
      'possibleDuplicateOfCaseId': FieldValue.delete(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Confirmed as a separate, unrelated report.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'kept_separate',
      actorUid: actorUid,
      actorName: actorName,
    );
  }

  /// Merges [duplicateCaseId] into [primaryCaseId]. The duplicate case is
  /// never deleted: it's marked `merged` with `mergedIntoCaseId` set, its
  /// own reporter/media/location/description are copied into a new report
  /// under the primary case's `reports` subcollection, and both case docs
  /// get a matching statusHistory entry so each reporter's own tracker
  /// (which reads its own case doc) sees the update. Each case's private
  /// `messages` subcollection is untouched, so per-reporter chats stay
  /// private while both see the same shared status update.
  Future<void> mergeDuplicate({
    required String primaryCaseId,
    required String duplicateCaseId,
    required String actorUid,
    required String actorName,
  }) async {
    final primaryRef = _caseDoc(primaryCaseId);
    final duplicateRef = _caseDoc(duplicateCaseId);
    final newReportRef = _reportsOf(primaryCaseId).doc(duplicateCaseId);

    await _db.runTransaction((tx) async {
      final primarySnap = await tx.get(primaryRef);
      final duplicateSnap = await tx.get(duplicateRef);
      if (!primarySnap.exists || !duplicateSnap.exists) {
        throw StateError('Both cases must exist to merge.');
      }
      final duplicateData = duplicateSnap.data()!;

      tx.set(newReportRef, {
        'reporterId': duplicateData['reporterId'],
        'reporterName': duplicateData['reporterName'],
        'reporterPhone': duplicateData['reporterPhone'],
        'description': duplicateData['condition'],
        'photoUrls': duplicateData['photoUrls'] ?? const [],
        'address': duplicateData['address'],
        'lat': duplicateData['lat'],
        'lng': duplicateData['lng'],
        'species': duplicateData['animalType'],
        'urgency': duplicateData['urgency'],
        'submittedAt': duplicateData['createdAt'] ?? FieldValue.serverTimestamp(),
        'isPrimary': false,
        'sourceCaseId': duplicateCaseId,
      });

      final sharedUpdateText =
          'This report was merged with another matching report for the same rescue.';

      tx.update(duplicateRef, {
        'status': RescueStatus.merged.firestoreValue,
        'mergedIntoCaseId': primaryCaseId,
        'statusHistory': FieldValue.arrayUnion([
          {'status': sharedUpdateText, 'timestamp': Timestamp.now()}
        ]),
      });

      tx.update(primaryRef, {
        'mergedCaseIds': FieldValue.arrayUnion([duplicateCaseId]),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'A duplicate report for this case was merged in.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      final logBase = ActivityLogEntry(
        id: '',
        caseId: '',
        action: 'merged',
        actorUid: actorUid,
        actorName: actorName,
      );
      tx.set(_activityLogsOf(primaryCaseId).doc(), {
        ...logBase.toFirestore(),
        'details': {'duplicateCaseId': duplicateCaseId, 'role': 'primary'},
      });
      tx.set(_activityLogsOf(duplicateCaseId).doc(), {
        ...logBase.toFirestore(),
        'details': {'mergedIntoCaseId': primaryCaseId, 'role': 'duplicate'},
      });
    });
  }

  Future<String> referToOrganization({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
  }) async {
    final referralRef = _referralsOf(caseId).doc();
    await referralRef.set({
      'type': ReferralType.anotherOrganization.name,
      'status': ReferralStatus.referredPending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'note': note,
      'targetOrgId': targetOrgId,
      'targetOrgName': targetOrgName,
    });
    await _caseDoc(caseId).update({
      'status': RescueStatus.referred.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Referred to $targetOrgName for review.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'referred_to_organization',
      actorUid: actorUid,
      actorName: actorName,
      details: {'targetOrgId': targetOrgId, 'targetOrgName': targetOrgName},
    );
    return referralRef.id;
  }

  Future<String> referToLgu({
    required String caseId,
    required String barangay,
    required LguReferralReason reason,
    required String explanation,
    bool attachReportMedia = true,
    required String actorUid,
    required String actorName,
  }) async {
    final caseSnap = await _caseDoc(caseId).get();
    final mediaUrls = attachReportMedia
        ? List<String>.from(caseSnap.data()?['photoUrls'] ?? const [])
        : <String>[];

    final referralRef = _referralsOf(caseId).doc();
    await referralRef.set({
      'type': ReferralType.localGovernmentUnit.name,
      'status': ReferralStatus.notified.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'barangay': barangay,
      'lguReason': reason.name,
      'lguExplanation': explanation,
      'attachedMediaUrls': mediaUrls,
    });
    await _caseDoc(caseId).update({
      'status': RescueStatus.referred.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Referred to the $barangay LGU/barangay: ${reason.label}.',
          'timestamp': Timestamp.now(),
        }
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'referred_to_lgu',
      actorUid: actorUid,
      actorName: actorName,
      details: {'barangay': barangay, 'reason': reason.name},
    );
    return referralRef.id;
  }

  /// TODO: rescue-volunteer referral has no assignment/matching logic yet.
  /// This only records the referral so the modal has something to call;
  /// wire up actual volunteer notification once that flow is designed.
  Future<String> referToVolunteer({
    required String caseId,
    String? note,
    required String actorUid,
    required String actorName,
  }) async {
    final referralRef = _referralsOf(caseId).doc();
    await referralRef.set({
      'type': ReferralType.rescueVolunteer.name,
      'status': ReferralStatus.referredPending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'note': note,
    });
    await addActivityLog(
      caseId: caseId,
      action: 'referred_to_volunteer',
      actorUid: actorUid,
      actorName: actorName,
    );
    return referralRef.id;
  }

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
  }) async {
    await _caseDoc(caseId).update({
      'vetClinicName': clinicName,
      'vetClinicAddress': clinicAddress,
      'vetClinicPlaceId': clinicPlaceId,
      'vetClinicLat': clinicLat,
      'vetClinicLng': clinicLng,
      'vetClinicPhone': clinicPhone,
      'vetClinicSelectedAt': Timestamp.now(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Assigned to clinic: $clinicName.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'assigned_clinic',
      actorUid: actorUid,
      actorName: actorName,
      details: {'clinicPlaceId': clinicPlaceId, 'clinicName': clinicName},
    );
  }

  /// Creates a new pending rider offer. Guarded by a transaction against
  /// creating a second active (pending/accepted) offer for the same case —
  /// the case doc's own `currentAssignmentId` pointer is read and checked
  /// inside the same transaction, so two admins tapping "Confirm" at the
  /// same moment can't both succeed. Does NOT touch the case's own
  /// RescueStatus or assignedVolunteer* fields — those only change once the
  /// rider actually accepts (see [acceptAssignment]).
  Future<String> createAssignmentOffer({
    required String caseId,
    required String riderId,
    required String riderName,
    required String riderType,
    bool isDemo = false,
  }) async {
    final caseRef = _caseDoc(caseId);
    final assignmentsCol = _transportAssignmentsOf(caseId);
    final newRef = assignmentsCol.doc();

    await _db.runTransaction((tx) async {
      final caseSnap = await tx.get(caseRef);
      final currentId = caseSnap.data()?['currentAssignmentId'] as String?;
      if (currentId != null) {
        final currentSnap = await tx.get(assignmentsCol.doc(currentId));
        final currentStatus = currentSnap.data()?['status'] as String?;
        if (currentStatus == 'pending' || currentStatus == 'accepted') {
          throw StateError('This case already has an active rider assignment.');
        }
      }
      tx.set(newRef, {
        'caseId': caseId,
        'riderId': riderId,
        'riderName': riderName,
        'riderType': riderType,
        'status': 'pending',
        'offeredAt': Timestamp.now(),
        'respondedAt': null,
        'acceptedAt': null,
        'rejectedAt': null,
        'rejectionReason': null,
        'completedAt': null,
        'isDemo': isDemo,
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
    final caseRef = _caseDoc(caseId);
    final assignmentRef = _transportAssignmentsOf(caseId).doc(assignmentId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      if (!snap.exists || snap.data()?['status'] != 'pending') return;
      final now = Timestamp.now();
      tx.update(assignmentRef, {
        'status': 'accepted',
        'respondedAt': now,
        'acceptedAt': now,
      });
      tx.update(caseRef, {
        'status': 'assigned',
        'riderId': riderId,
        'assignedVolunteerId': riderId,
        'assignedVolunteerName': riderName,
        'assignedVehicle': riderVehicle,
        'assignedPlate': riderPlate,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Pet transporter assigned: $riderName.', 'timestamp': now},
        ]),
      });
    });
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
    final assignmentRef = _transportAssignmentsOf(caseId).doc(assignmentId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      if (!snap.exists || snap.data()?['status'] != 'pending') return;
      final now = Timestamp.now();
      tx.update(assignmentRef, {
        'status': 'rejected',
        'respondedAt': now,
        'rejectedAt': now,
        'rejectionReason': reason,
      });
    });
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
  Future<void> cancelAssignment({
    required String caseId,
    required String assignmentId,
    String? reason,
  }) async {
    final caseRef = _caseDoc(caseId);
    final assignmentRef = _transportAssignmentsOf(caseId).doc(assignmentId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      if (!snap.exists || snap.data()?['status'] != 'pending') return;
      final now = Timestamp.now();
      tx.update(assignmentRef, {
        'status': 'cancelled',
        'respondedAt': now,
        'cancelledAt': now,
        if (reason != null && reason.isNotEmpty) 'cancellationReason': reason,
      });
      final caseSnap = await tx.get(caseRef);
      if (caseSnap.data()?['currentAssignmentId'] == assignmentId) {
        tx.update(caseRef, {'currentAssignmentId': FieldValue.delete()});
      }
    });
  }

  /// Closes out an accepted assignment once the animal has reached
  /// treatment — this is what frees a demo/real rider back to "Available"
  /// (streamActiveAssignmentsByRider only counts pending/accepted).
  Future<void> completeAssignment({
    required String caseId,
    required String assignmentId,
  }) async {
    await _transportAssignmentsOf(caseId).doc(assignmentId).update({
      'status': 'completed',
      'completedAt': Timestamp.now(),
    });
  }

  // ---- Treatment ----------------------------------------------------

  /// Appends one treatment log entry (never edits/overwrites a prior one)
  /// and updates the case-level "latest state" fields that drive the
  /// Treatment Details header and the Rescue Reports card: currentCondition,
  /// latestTreatmentUpdateType, treatmentUpdatedAt, statusHistory. A
  /// Discharge entry additionally sets readyForDischarge/dischargedAt; a
  /// Death Report entry sets deceasedAt/causeOfDeath (and the legacy
  /// animalStatus:'Deceased' flag some older screens still read).
  Future<void> addTreatmentLog({
    required String caseId,
    required TreatmentLogEntry entry,
  }) async {
    await _treatmentLogsOf(caseId).add(entry.toFirestore());

    final now = Timestamp.now();
    final isDischarge = entry.type == TreatmentUpdateType.discharge.label;
    final isDeath = entry.type == TreatmentUpdateType.deathReport.label;

    await _caseDoc(caseId).update({
      if (entry.condition != null) 'currentCondition': entry.condition,
      'latestTreatmentUpdateType': entry.type,
      'treatmentUpdatedAt': now,
      'statusHistory': FieldValue.arrayUnion([
        {'status': '${entry.type}: ${entry.notes}', 'timestamp': now},
      ]),
      if (isDischarge) 'readyForDischarge': true,
      if (isDischarge) 'dischargedAt': now,
      if (isDeath) 'deceasedAt': now,
      if (isDeath) 'animalStatus': 'Deceased',
      if (isDeath && entry.causeOfDeath != null) 'causeOfDeath': entry.causeOfDeath,
    });
  }

  Future<void> transferAnimal({
    required String caseId,
    required String targetOrganizationId,
    required String targetOrganizationName,
    String? notes,
    required String actorUid,
    required String actorName,
  }) async {
    await _caseDoc(caseId).update({
      'status': RescueStatus.completed.firestoreValue,
      'targetOrganizationId': targetOrganizationId,
      'targetOrganizationName': targetOrganizationName,
      'transferNotes': notes,
      'transferRequestedAt': Timestamp.now(),
      // TODO(transfer): this is a simplified, one-way record — there is no
      // receiving-organization acceptance workflow yet. 'pending' here just
      // means "handed off, not yet acknowledged by the receiving org."
      'transferStatus': 'pending',
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Animal transferred to $targetOrganizationName.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'transferred_animal',
      actorUid: actorUid,
      actorName: actorName,
      details: {'targetOrganizationId': targetOrganizationId, 'targetOrganizationName': targetOrganizationName},
    );
  }

  /// Temporary handoff record only — this is NOT a completed adoption. See
  /// the TODO on the release UI: formal adoption approval/forms are a
  /// separate, not-yet-built feature.
  Future<void> releaseToReporter({
    required String caseId,
    required String reporterId,
    required String reporterName,
    String? notes,
    required String actorUid,
    required String actorName,
  }) async {
    await _caseDoc(caseId).update({
      'status': RescueStatus.completed.firestoreValue,
      'releasedToReporterId': reporterId,
      'releasedToReporterName': reporterName,
      'releasedAt': Timestamp.now(),
      'releaseNotes': notes,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Release confirmed — handed off to $reporterName.', 'timestamp': Timestamp.now()}
      ]),
    });
    await addActivityLog(
      caseId: caseId,
      action: 'released_to_reporter',
      actorUid: actorUid,
      actorName: actorName,
      details: {'reporterId': reporterId, 'reporterName': reporterName},
    );
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
    await _caseDoc(caseId).update({
      'status': 'closed',
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Case closed. Animal deceased.', 'timestamp': Timestamp.now()}
      ]),
    });
  }

  // ---- Intake -----------------------------------------------------------

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
    final caseRef = _caseDoc(caseId);
    final assignmentRef = _transportAssignmentsOf(caseId).doc();

    await _db.runTransaction((tx) async {
      final caseSnap = await tx.get(caseRef);
      if (!caseSnap.exists) throw StateError('Case not found.');
      if (caseSnap.data()?['intakeConfirmedAt'] != null) return; // already confirmed

      final now = Timestamp.now();
      tx.update(caseRef, {
        'status': RescueStatus.intake.firestoreValue,
        'intakeDestinationName': destinationName,
        'intakeDestinationAddress': destinationAddress,
        'intakeDestinationPlaceId': destinationPlaceId,
        'intakeDestinationLat': destinationLat,
        'intakeDestinationLng': destinationLng,
        'intakeConfirmedAt': now,
        'statusHistory': FieldValue.arrayUnion([
          {'status': 'Intake confirmed — transport to $destinationName arranged.', 'timestamp': now}
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
  Future<void> confirmAnimalReceived({
    required String caseId,
    String? currentAssignmentId,
  }) async {
    await _caseDoc(caseId).update({
      'intakeReceivedAt': Timestamp.now(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Animal received at the shelter.', 'timestamp': Timestamp.now()}
      ]),
    });
    if (currentAssignmentId != null) {
      await completeAssignment(caseId: caseId, assignmentId: currentAssignmentId);
    }
  }

  // ---- Quarantine (optional) ---------------------------------------------

  Future<void> startQuarantine({
    required String caseId,
    required int durationDays,
  }) async {
    final now = DateTime.now();
    await _caseDoc(caseId).update({
      'quarantineStatus': 'active',
      'quarantineStartedAt': FieldValue.serverTimestamp(),
      'quarantineDurationDays': durationDays,
      // The scheduled END is a future instant, which FieldValue.serverTimestamp()
      // can't express (it only stamps "now") — computed from the device
      // clock here. The START above still uses the server clock.
      'quarantineScheduledEndAt': Timestamp.fromDate(now.add(Duration(days: durationDays))),
      'quarantineEndedAt': null,
      'quarantineEndReason': null,
    });
  }

  Future<void> endQuarantine({
    required String caseId,
    String? reason,
  }) async {
    await _caseDoc(caseId).update({
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
    await _caseDoc(caseId).update({'quarantineStatus': 'skipped'});
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
    await _caseDoc(c.id).update({
      'quarantineStatus': 'completed',
      'quarantineEndedAt': Timestamp.fromDate(scheduledEnd),
      'quarantineEndReason': 'Automatic — scheduled duration elapsed.',
    });
  }

  // ---- Cost tracking --------------------------------------------------

  Future<void> addExpense({required String caseId, required Expense expense}) async {
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    await _expensesOf(caseId).add({
      ...expense.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateExpense({required String caseId, required Expense expense}) async {
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    await _expensesOf(caseId).doc(expense.id).update(expense.toFirestore());
  }

  Future<void> deleteExpense({required String caseId, required String expenseId}) async {
    await _expensesOf(caseId).doc(expenseId).delete();
  }

  Future<void> addActivityLog({
    required String caseId,
    required String action,
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) async {
    await _activityLogsOf(caseId).add(
      ActivityLogEntry(
        id: '',
        caseId: caseId,
        action: action,
        actorUid: actorUid,
        actorName: actorName,
        actorRole: actorRole,
        details: details,
      ).toFirestore(),
    );
  }
}
