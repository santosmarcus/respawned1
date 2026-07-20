import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';

/// A referral document under `cases/{caseId}/referrals/{referralId}`.
/// Fields are a superset across the three referral types; each type only
/// populates the fields relevant to it (see the per-type factories below).
class Referral {
  final String id;
  final String caseId;
  final ReferralType type;
  final ReferralStatus status;
  final DateTime? createdAt;
  final String? createdByUid;
  final String? createdByName;
  final String? note;

  // anotherOrganization
  final String? targetOrgId;
  final String? targetOrgName;

  // rescueVolunteer (TODO: no assignment logic yet, stub only)
  final String? targetVolunteerId;
  final String? targetVolunteerName;

  // localGovernmentUnit
  final String? barangay;
  final LguReferralReason? lguReason;
  final String? lguExplanation;
  final List<String> attachedMediaUrls;

  const Referral({
    required this.id,
    required this.caseId,
    required this.type,
    required this.status,
    this.createdAt,
    this.createdByUid,
    this.createdByName,
    this.note,
    this.targetOrgId,
    this.targetOrgName,
    this.targetVolunteerId,
    this.targetVolunteerName,
    this.barangay,
    this.lguReason,
    this.lguExplanation,
    this.attachedMediaUrls = const [],
  });

  factory Referral.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String caseId,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['createdAt'];
    return Referral(
      id: doc.id,
      caseId: caseId,
      type: ReferralType.fromName(data['type'] as String?),
      status: ReferralStatus.fromName(data['status'] as String?),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      createdByUid: data['createdByUid'] as String?,
      createdByName: data['createdByName'] as String?,
      note: data['note'] as String?,
      targetOrgId: data['targetOrgId'] as String?,
      targetOrgName: data['targetOrgName'] as String?,
      targetVolunteerId: data['targetVolunteerId'] as String?,
      targetVolunteerName: data['targetVolunteerName'] as String?,
      barangay: data['barangay'] as String?,
      lguReason: data['lguReason'] != null
          ? LguReferralReason.fromName(data['lguReason'] as String?)
          : null,
      lguExplanation: data['lguExplanation'] as String?,
      attachedMediaUrls: List<String>.from(data['attachedMediaUrls'] ?? const []),
    );
  }
}
