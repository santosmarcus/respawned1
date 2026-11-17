// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Referrals of a case to another organization, an LGU, or a volunteer.
class CaseReferralRepository {
  CaseReferralRepository(this._store);

  final RescueCaseStore _store;

  Stream<List<Referral>> streamReferrals(String caseId) {
    return _store
        .referralsOf(caseId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Referral.fromFirestore(d, caseId)).toList(),
        );
  }

  /// Refers the case to another organization. The target is stored on the
  /// case (`referredToOrgId`, plus a `referral` summary), so only that
  /// organization's staff (and platform staff) see it in their Referred
  /// queue and can accept or decline it (firestore.rules isReferralTarget).
  /// An unowned case is stamped with the referring organization, which gets
  /// it back if the target declines or doesn't answer in time
  /// (functions/index.js followUpCaseReferrals).
  Future<String> referToOrganization({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
  }) async {
    final caseSnap = await _store.caseDoc(caseId).get();
    final caseData = caseSnap.data() ?? const <String, dynamic>{};
    final userSnap = await _store.db.collection('users').doc(actorUid).get();
    final actorOrgId = (userSnap.data()?['organizationId'] as String?) ?? '';
    final caseOrgId = (caseData['organizationId'] as String?) ?? '';
    final fromOrgId = caseOrgId.isNotEmpty ? caseOrgId : actorOrgId;
    if (fromOrgId.isNotEmpty && fromOrgId == targetOrgId) {
      throw StateError('This case already belongs to $targetOrgName.');
    }
    var fromOrgName = '';
    if (fromOrgId.isNotEmpty) {
      final org = await _store.db.collection('organizations').doc(fromOrgId).get();
      fromOrgName = (org.data()?['name'] as String?)?.trim() ?? '';
    }

    final referralRef = _store.referralsOf(caseId).doc();
    final batch = _store.db.batch();
    batch.set(referralRef, {
      'type': ReferralType.anotherOrganization.name,
      'status': ReferralStatus.referredPending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'note': note,
      'targetOrgId': targetOrgId,
      'targetOrgName': targetOrgName,
      'fromOrgId': fromOrgId,
      'fromOrgName': fromOrgName,
    });
    _store.recordActionInBatch(
      batch,
      caseId: caseId,
      statusLine: 'Referred to $targetOrgName for review.',
      fields: {
        'status': RescueStatus.referred.firestoreValue,
        'referredToOrgId': targetOrgId,
        'referral': {
          'referralId': referralRef.id,
          'targetOrgId': targetOrgId,
          'targetOrgName': targetOrgName,
          'fromOrgId': fromOrgId,
          'fromOrgName': fromOrgName,
          'referredAt': FieldValue.serverTimestamp(),
          'referredByUid': actorUid,
          'referredByName': actorName,
          'note': note,
          'previousStatus': caseData['status'],
        },
        if (caseOrgId.isEmpty && fromOrgId.isNotEmpty) 'organizationId': fromOrgId,
        'referralOutcome': FieldValue.delete(),
      },
      action: 'referred_to_organization',
      actorUid: actorUid,
      actorName: actorName,
      details: {'targetOrgId': targetOrgId, 'targetOrgName': targetOrgName, 'referralId': referralRef.id},
    );
    await batch.commit();
    return referralRef.id;
  }

  /// The organization a case was referred to takes it: it becomes the owner
  /// and the case enters its Rescue Review. The referring organization's
  /// staff are notified (functions/index.js notifyReferralOutcome).
  Future<void> acceptReferral({
    required String caseId,
    required String actorUid,
    required String actorName,
  }) => _answer(caseId: caseId, accept: true, actorUid: actorUid, actorName: actorName);

  /// The organization a case was referred to turns it down with [reason].
  /// The case goes back to the referring organization's Rescue Review with
  /// the reason shown on it (`referralOutcome`).
  Future<void> declineReferral({
    required String caseId,
    required String reason,
    required String actorUid,
    required String actorName,
  }) => _answer(caseId: caseId, accept: false, reason: reason, actorUid: actorUid, actorName: actorName);

  Future<void> _answer({
    required String caseId,
    required bool accept,
    String? reason,
    required String actorUid,
    required String actorName,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    final userSnap = await _store.db.collection('users').doc(actorUid).get();
    final actorOrgId = (userSnap.data()?['organizationId'] as String?) ?? '';
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final c = snap.data() ?? const <String, dynamic>{};
      final referral = c['referral'] is Map
          ? Map<String, dynamic>.from(c['referral'] as Map)
          : const <String, dynamic>{};
      final targetOrgId = c['referredToOrgId'] as String? ?? '';
      if (c['status'] != RescueStatus.referred.firestoreValue || targetOrgId.isEmpty) {
        throw StateError('This referral was already answered.');
      }
      if (actorOrgId.isNotEmpty && actorOrgId != targetOrgId) {
        throw StateError('Only ${referral['targetOrgName'] ?? 'the receiving organization'} can answer this referral.');
      }
      final targetOrgName = referral['targetOrgName'] as String? ?? 'The receiving organization';
      final fromOrgName = referral['fromOrgName'] as String? ?? '';
      final referralId = referral['referralId'] as String?;
      if (referralId != null) {
        tx.update(_store.referralsOf(caseId).doc(referralId), {
          'status': accept ? ReferralStatus.accepted.name : ReferralStatus.declined.name,
          'respondedAt': FieldValue.serverTimestamp(),
          'respondedByUid': actorUid,
          'respondedByName': actorName,
          if (!accept) 'declineReason': reason,
        });
      }
      _store.recordActionIn(
        tx,
        caseId: caseId,
        statusLine: accept
            ? '$targetOrgName accepted the referral and is reviewing the case.'
            : '$targetOrgName declined the referral. The case is back with '
                '${fromOrgName.isEmpty ? 'the referring organization' : fromOrgName} for review.',
        fields: {
          'status': RescueStatus.pendingReview.firestoreValue,
          'referredToOrgId': FieldValue.delete(),
          if (accept) 'organizationId': targetOrgId,
          'referralOutcome': {
            'status': accept ? 'accepted' : 'declined',
            'referralId': referralId,
            'targetOrgId': targetOrgId,
            'targetOrgName': targetOrgName,
            'fromOrgId': referral['fromOrgId'],
            'fromOrgName': fromOrgName,
            'reason': reason,
            'byUid': actorUid,
            'byName': actorName,
            'at': FieldValue.serverTimestamp(),
          },
        },
        action: accept ? 'referral_accepted' : 'referral_declined',
        actorUid: actorUid,
        actorName: actorName,
        details: {
          'referralId': referralId,
          'targetOrgId': targetOrgId,
          'targetOrgName': targetOrgName,
          'reason': ?reason,
        },
      );
    });
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
    final caseSnap = await _store.caseDoc(caseId).get();
    final mediaUrls = attachReportMedia
        ? List<String>.from(caseSnap.data()?['photoUrls'] ?? const [])
        : <String>[];

    final referralRef = _store.referralsOf(caseId).doc();
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
    await _store.recordAction(
      caseId: caseId,
      statusLine: 'Referred to the $barangay LGU/barangay: ${reason.label}.',
      fields: {'status': RescueStatus.referred.firestoreValue},
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
    final referralRef = _store.referralsOf(caseId).doc();
    final batch = _store.db.batch();
    batch.set(referralRef, {
      'type': ReferralType.rescueVolunteer.name,
      'status': ReferralStatus.referredPending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'note': note,
    });
    _store.recordActionInBatch(
      batch,
      caseId: caseId,
      action: 'referred_to_volunteer',
      actorUid: actorUid,
      actorName: actorName,
    );
    await batch.commit();
    return referralRef.id;
  }
}
