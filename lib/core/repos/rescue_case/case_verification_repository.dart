import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/media_ref.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Report verification before a case is accepted: asking the reporter for a
/// fresh photo, recording the desk check result, sending a rider, and what
/// the rider found. See core/models/rescue/report_verification.dart for the
/// fields these write.
class CaseVerificationRepository {
  CaseVerificationRepository(this._store);

  final RescueCaseStore _store;

  /// Statuses a report can be verified in. Once a case is accepted, rejected
  /// or closed the desk check is over.
  static bool canVerify(RescueStatus status) =>
      status == RescueStatus.pendingReview || status == RescueStatus.verifying;

  /// Asks the reporter for a photo or video taken now, in the app. The
  /// request shows on their Track Case page and in the case chat.
  Future<void> requestLiveProof({
    required String caseId,
    required String actorUid,
    required String actorName,
    String? note,
  }) {
    final batch = _store.db.batch();
    _store.recordActionInBatch(
      batch,
      caseId: caseId,
      action: 'live_proof_requested',
      statusLine: 'The rescue team asked for a new photo or video of the animal.',
      actorUid: actorUid,
      actorName: actorName,
      fields: {
        'liveProofRequest': {
          'requestedAt': FieldValue.serverTimestamp(),
          'requestedBy': actorUid,
          'requestedByName': actorName,
          'note': ?note,
        },
      },
    );
    batch.set(_store.caseDoc(caseId).collection('messages').doc(), {
      'senderId': 'admin',
      'senderName': 'Loved by the Gapz',
      'text': 'Please send a new photo or short video of the animal from where it is now. '
          'Open this case and tap "Take a photo now".${note == null ? '' : '\n\n$note'}',
      'timestamp': FieldValue.serverTimestamp(),
    });
    return batch.commit();
  }

  /// The reporter's answer to [requestLiveProof]. [lat]/[lng] is where their
  /// phone was when they sent it.
  Future<void> submitLiveProof({
    required String caseId,
    required List<MediaRef> media,
    double? lat,
    double? lng,
    double? accuracyM,
  }) {
    return _store.recordAction(
      caseId: caseId,
      action: 'live_proof_submitted',
      statusLine: 'The reporter sent a new photo or video of the animal.',
      fields: {
        'liveProof': {
          'mediaUrls': [for (final m in media) m.url],
          'mediaTypes': [for (final m in media) m.type],
          'submittedAt': FieldValue.serverTimestamp(),
          'lat': ?lat,
          'lng': ?lng,
          'accuracyM': ?accuracyM,
        },
      },
    );
  }

  /// Saves the desk check result. [DeskOutcome.needsRider] also names the
  /// rider ([riderId] when they have an account, otherwise just
  /// [riderName]) and moves the case to Verifying; the other two outcomes
  /// put a Verifying case back in review.
  Future<void> recordDeskOutcome({
    required String caseId,
    required DeskOutcome outcome,
    String? note,
    required String actorUid,
    required String actorName,
    String? organizationId,
    String? riderId,
    String? riderName,
  }) {
    final sendsRider = outcome == DeskOutcome.needsRider;
    if (sendsRider && (riderName == null || riderName.trim().isEmpty)) {
      throw ArgumentError('Choose who is going to check the location.');
    }
    final caseRef = _store.caseDoc(caseId);
    return _store.db.runTransaction((tx) async {
      final data = (await tx.get(caseRef)).data();
      if (data == null) throw StateError('This case no longer exists.');
      final status = RescueStatus.fromFirestoreValue(data['status'] as String?);
      if (!canVerify(status)) {
        throw StateError('This report is already ${status.label.toLowerCase()}.');
      }
      _store.recordActionIn(
        tx,
        caseId: caseId,
        action: 'verification_desk_result',
        statusLine: switch (outcome) {
          DeskOutcome.confirmedRemotely => 'The report has been verified.',
          DeskOutcome.needsRider => 'A rider is being sent to confirm the location.',
          DeskOutcome.couldNotConfirm => null,
        },
        actorUid: actorUid,
        actorName: actorName,
        details: {'outcome': outcome.name, if (sendsRider) 'riderName': riderName, 'note': ?note},
        fields: {
          'verification.deskOutcome': outcome.name,
          'verification.deskNote': note ?? FieldValue.delete(),
          'verification.deskBy': actorUid,
          'verification.deskByName': actorName,
          'verification.deskAt': FieldValue.serverTimestamp(),
          'verification.deskOrganizationId': ?organizationId,
          if (sendsRider) ...{
            'verification.riderId': riderId ?? FieldValue.delete(),
            'verification.riderName': riderName!.trim(),
            'verification.riderAssignedAt': FieldValue.serverTimestamp(),
            // A new visit starts with no result.
            for (final key in _riderResultKeys) 'verification.$key': FieldValue.delete(),
            'status': RescueStatus.verifying.firestoreValue,
            // Which organization sent the rider. Not ownership: the case
            // stays unowned until someone accepts it.
            'verifyingOrganizationId': ?organizationId,
          } else if (status == RescueStatus.verifying)
            'status': RescueStatus.pendingReview.firestoreValue,
        },
      );
    });
  }

  /// What a rider may write about their own visit (firestore.rules
  /// `verifierUpdate` allows exactly these keys under `verification`).
  static const _riderResultKeys = [
    'riderOutcome',
    'riderNote',
    'riderMediaUrls',
    'riderMediaTypes',
    'riderRecordedAt',
    'riderRecordedBy',
    'riderRecordedByName',
    'riderLat',
    'riderLng',
  ];

  /// What the rider found. Called by the rider from their own app, or by
  /// staff on behalf of a rider who phoned it in. A Verifying case goes back
  /// to review so staff can accept or reject it.
  Future<void> recordRiderOutcome({
    required String caseId,
    required RiderOutcome outcome,
    String? note,
    List<MediaRef> media = const [],
    double? lat,
    double? lng,
    required String actorUid,
    required String actorName,
  }) {
    final caseRef = _store.caseDoc(caseId);
    return _store.db.runTransaction((tx) async {
      final data = (await tx.get(caseRef)).data();
      if (data == null) throw StateError('This case no longer exists.');
      final status = RescueStatus.fromFirestoreValue(data['status'] as String?);
      _store.recordActionIn(
        tx,
        caseId: caseId,
        action: 'verification_rider_result',
        statusLine: switch (outcome) {
          RiderOutcome.found => 'A rider confirmed the animal at the reported location.',
          RiderOutcome.notFound => 'A rider could not find the animal at the reported location.',
        },
        actorUid: actorUid,
        actorName: actorName,
        details: {'outcome': outcome.name, 'note': ?note},
        fields: {
          'verification.riderOutcome': outcome.name,
          'verification.riderNote': note ?? FieldValue.delete(),
          'verification.riderMediaUrls': [for (final m in media) m.url],
          'verification.riderMediaTypes': [for (final m in media) m.type],
          'verification.riderRecordedAt': FieldValue.serverTimestamp(),
          'verification.riderRecordedBy': actorUid,
          'verification.riderRecordedByName': actorName,
          'verification.riderLat': lat ?? FieldValue.delete(),
          'verification.riderLng': lng ?? FieldValue.delete(),
          if (status == RescueStatus.verifying) 'status': RescueStatus.pendingReview.firestoreValue,
        },
      );
    });
  }

  /// How this reporter's other reports turned out.
  Future<ReporterTrackRecord> reporterTrackRecord(String reporterId, {String? excludeCaseId}) async {
    final snap = await _store.cases.where('reporterId', isEqualTo: reporterId).limit(200).get();
    return ReporterTrackRecord.fromCases([
      for (final doc in snap.docs)
        if (doc.id != excludeCaseId) doc.data(),
    ]);
  }

  /// The location checks waiting on [riderId]: assigned to them, case still
  /// Verifying, no result recorded.
  Stream<List<RescueCase>> streamVerificationVisits(String riderId) {
    return _store.cases.where('verification.riderId', isEqualTo: riderId).snapshots().map(
          (snap) => snap.docs
              .map(RescueCase.fromFirestore)
              .where((c) =>
                  c.status == RescueStatus.verifying &&
                  (CaseVerification.fromMap(c.raw['verification'])?.awaitingRider ?? false))
              .toList(),
        );
  }
}
