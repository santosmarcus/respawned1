// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/case_claim_rules.dart';
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
  ///
  /// [type] rescueVolunteer: the target is an independent rescuer (an
  /// organization with kind 'independent'); the flow is the same.
  Future<String> referToOrganization({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
    ReferralType type = ReferralType.anotherOrganization,
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
      'type': type.name,
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
      action: type == ReferralType.rescueVolunteer ? 'referred_to_volunteer' : 'referred_to_organization',
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
      // An independent rescuer accepts only while under capacity.
      var targetIndependent = false;
      if (accept) {
        final target = await tx.get(_store.db.collection('organizations').doc(targetOrgId));
        final refusal = independentCapacityRefusal(target.data());
        if (refusal != null) throw refusal;
        targetIndependent = target.data()?['kind'] == 'independent';
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
          if (accept) 'ownerKind': targetIndependent ? 'independent' : FieldValue.delete(),
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

  /// The referring organization takes a still-unanswered referral back
  /// (organization or LGU). The case returns to the status it had before
  /// the referral (Rescue Review for older referrals that didn't record
  /// one), the receiving organization loses access to it, and the existing
  /// refer sheet can send it somewhere else. Organization referrals also
  /// come back by themselves after 48 hours with no answer
  /// (functions/index.js followUpCaseReferrals); LGU referrals only come
  /// back this way.
  Future<void> withdraw({
    required String caseId,
    required String reason,
    required String actorUid,
    required String actorName,
  }) async {
    final caseRef = _store.caseDoc(caseId);
    // LGU referrals don't keep their id on the case; find the open one.
    final open = await _store
        .referralsOf(caseId)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();
    await _store.db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      final c = snap.data() ?? const <String, dynamic>{};
      if (c['status'] != RescueStatus.referred.firestoreValue) {
        throw StateError('This case is no longer waiting on a referral.');
      }
      final referral = c['referral'] is Map
          ? Map<String, dynamic>.from(c['referral'] as Map)
          : const <String, dynamic>{};
      final targetOrgId = c['referredToOrgId'] as String? ?? '';
      var referralId = targetOrgId.isNotEmpty ? referral['referralId'] as String? : null;
      String? barangay;
      if (referralId == null) {
        for (final d in open.docs) {
          final status = d.data()['status'];
          if (status == ReferralStatus.notified.name || status == ReferralStatus.referredPending.name) {
            referralId = d.id;
            barangay = d.data()['barangay'] as String?;
            break;
          }
        }
      }
      final previous = targetOrgId.isNotEmpty ? referral['previousStatus'] as String? : null;
      final backTo = (previous == null || previous.isEmpty || previous == RescueStatus.referred.firestoreValue)
          ? RescueStatus.pendingReview.firestoreValue
          : previous;
      final targetName = targetOrgId.isNotEmpty
          ? (referral['targetOrgName'] as String? ?? 'the receiving organization')
          : (barangay == null || barangay.isEmpty ? 'the LGU/barangay' : 'the $barangay LGU/barangay');
      if (referralId != null) {
        tx.update(_store.referralsOf(caseId).doc(referralId), {
          'status': ReferralStatus.withdrawn.name,
          'respondedAt': FieldValue.serverTimestamp(),
          'respondedByUid': actorUid,
          'respondedByName': actorName,
          'withdrawReason': reason,
        });
      }
      _store.recordActionIn(
        tx,
        caseId: caseId,
        statusLine: 'Referral to $targetName withdrawn. The case is open again.',
        fields: {
          'status': backTo,
          'referredToOrgId': FieldValue.delete(),
          'referralOutcome': {
            'status': 'withdrawn',
            'referralId': referralId,
            'targetOrgId': targetOrgId.isEmpty ? null : targetOrgId,
            'targetOrgName': targetOrgId.isEmpty ? targetName : referral['targetOrgName'],
            'fromOrgId': referral['fromOrgId'],
            'fromOrgName': referral['fromOrgName'],
            'reason': reason,
            'byUid': actorUid,
            'byName': actorName,
            'at': FieldValue.serverTimestamp(),
          },
        },
        action: 'referral_withdrawn',
        actorUid: actorUid,
        actorName: actorName,
        details: {
          'referralId': referralId,
          'targetOrgId': targetOrgId.isEmpty ? null : targetOrgId,
          'targetName': targetName,
          'reason': reason,
          'restoredStatus': backTo,
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

  /// Refers the case to an independent rescuer (Refer → Rescue Volunteer):
  /// the same flow as [referToOrganization] — they accept or decline, with
  /// the 24 h reminder and 48 h return to the referring organization.
  Future<String> referToVolunteer({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
  }) => referToOrganization(
        caseId: caseId,
        targetOrgId: targetOrgId,
        targetOrgName: targetOrgName,
        note: note,
        actorUid: actorUid,
        actorName: actorName,
        type: ReferralType.rescueVolunteer,
      );
}
