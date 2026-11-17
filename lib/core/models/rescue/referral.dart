import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';

/// The shareable web link for a referral (`share` on the referral doc,
/// written by functions/referral_shares.js createReferralShare).
class ReferralShareLink {
  final String url;
  final bool revoked;
  final bool includeReporter;
  final DateTime? expiresAt;

  const ReferralShareLink({required this.url, this.revoked = false, this.includeReporter = false, this.expiresAt});

  bool isOpen(DateTime now) => !revoked && (expiresAt == null || now.isBefore(expiresAt!));

  static ReferralShareLink? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final exp = raw['expiresAt'];
    return ReferralShareLink(
      url: url,
      revoked: raw['revoked'] == true,
      includeReporter: raw['includeReporter'] == true,
      expiresAt: exp is Timestamp ? exp.toDate() : null,
    );
  }
}

/// The latest answer someone gave from the referral web page
/// (`lastResponse`, written by respondToReferralShare).
class ReferralShareResponse {
  final String response;
  final String name;
  final String? contact;
  final String? note;
  final DateTime? at;

  const ReferralShareResponse({required this.response, required this.name, this.contact, this.note, this.at});

  String get label => switch (response) {
        'will_handle' => 'Will handle it',
        'cannot_handle' => "Can't take it",
        'need_info' => 'Needs more information',
        _ => response,
      };

  static ReferralShareResponse? fromMap(Object? raw) {
    if (raw is! Map || raw['response'] is! String) return null;
    final at = raw['at'];
    return ReferralShareResponse(
      response: raw['response'] as String,
      name: (raw['name'] as String?) ?? '',
      contact: raw['contact'] as String?,
      note: raw['note'] as String?,
      at: at is Timestamp ? at.toDate() : null,
    );
  }
}

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
  final String? fromOrgName;
  final DateTime? respondedAt;
  final String? respondedByName;
  final String? declineReason;

  // rescueVolunteer (TODO: no assignment logic yet, stub only)
  final String? targetVolunteerId;
  final String? targetVolunteerName;

  // localGovernmentUnit
  final String? barangay;
  final LguReferralReason? lguReason;
  final String? lguExplanation;
  final List<String> attachedMediaUrls;

  /// Web link for people outside the app, and the latest answer from it.
  final ReferralShareLink? share;
  final ReferralShareResponse? lastResponse;

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
    this.fromOrgName,
    this.respondedAt,
    this.respondedByName,
    this.declineReason,
    this.targetVolunteerId,
    this.targetVolunteerName,
    this.barangay,
    this.lguReason,
    this.lguExplanation,
    this.attachedMediaUrls = const [],
    this.share,
    this.lastResponse,
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
      fromOrgName: data['fromOrgName'] as String?,
      respondedAt: data['respondedAt'] is Timestamp ? (data['respondedAt'] as Timestamp).toDate() : null,
      respondedByName: data['respondedByName'] as String?,
      declineReason: data['declineReason'] as String?,
      targetVolunteerId: data['targetVolunteerId'] as String?,
      targetVolunteerName: data['targetVolunteerName'] as String?,
      barangay: data['barangay'] as String?,
      lguReason: data['lguReason'] != null
          ? LguReferralReason.fromName(data['lguReason'] as String?)
          : null,
      lguExplanation: data['lguExplanation'] as String?,
      attachedMediaUrls: List<String>.from(data['attachedMediaUrls'] ?? const []),
      share: ReferralShareLink.fromMap(data['share']),
      lastResponse: ReferralShareResponse.fromMap(data['lastResponse']),
    );
  }
}
