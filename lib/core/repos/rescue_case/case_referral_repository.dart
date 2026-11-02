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

  Future<String> referToOrganization({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
  }) async {
    final referralRef = _store.referralsOf(caseId).doc();
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
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.referred.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Referred to $targetOrgName for review.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
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
    await _store.caseDoc(caseId).update({
      'status': RescueStatus.referred.firestoreValue,
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Referred to the $barangay LGU/barangay: ${reason.label}.',
          'timestamp': Timestamp.now(),
        },
      ]),
    });
    await _store.addActivityLog(
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
    final referralRef = _store.referralsOf(caseId).doc();
    await referralRef.set({
      'type': ReferralType.rescueVolunteer.name,
      'status': ReferralStatus.referredPending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': actorUid,
      'createdByName': actorName,
      'note': note,
    });
    await _store.addActivityLog(
      caseId: caseId,
      action: 'referred_to_volunteer',
      actorUid: actorUid,
      actorName: actorName,
    );
    return referralRef.id;
  }
}
