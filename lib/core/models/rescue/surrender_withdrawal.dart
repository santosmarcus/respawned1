/// Withdrawing a Pet Surrender (cases/{id}.surrenderWithdrawal), written by
/// CommunityAdoptionRequestRepository.withdrawSurrender. The case goes to
/// status 'withdrawn' and is kept: nothing is deleted.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';

/// Why the reporter withdrew. Stored as [name].
enum SurrenderWithdrawalReason {
  keeping('I have decided to keep my pet'),
  foundAdopter('I found an adopter on my own'),
  alreadyRehomed('My pet has already been rehomed'),
  cannotProceed('I can no longer go ahead with the surrender'),
  other('Other');

  const SurrenderWithdrawalReason(this.label);
  final String label;

  static SurrenderWithdrawalReason? fromName(Object? v) {
    for (final r in values) {
      if (r.name == v) return r;
    }
    return null;
  }
}

/// A Pet Surrender the reporter can still withdraw: listed for Community
/// Adoption, or (older reports) still waiting in review.
bool canWithdrawSurrender(Map<String, dynamic> caseData) {
  if (!isSurrenderRescueType(caseData['rescueType'] as String?)) return false;
  final status = (caseData['status'] as String? ?? '').toLowerCase();
  return status == kCommunityAdoptionStatus || status == 'pending';
}

/// The stored withdrawal details, or null when the case wasn't withdrawn.
class SurrenderWithdrawal {
  const SurrenderWithdrawal({required this.reason, this.otherText, this.details, this.withdrawnAt});

  final SurrenderWithdrawalReason? reason;
  final String? otherText;
  final String? details;
  final DateTime? withdrawnAt;

  /// "Other" shows what the reporter typed.
  String get reasonLabel {
    if (reason == SurrenderWithdrawalReason.other && (otherText ?? '').trim().isNotEmpty) {
      return otherText!.trim();
    }
    return reason?.label ?? 'Not stated';
  }

  static SurrenderWithdrawal? fromCase(Map<String, dynamic> caseData) {
    final raw = caseData['surrenderWithdrawal'];
    if (raw is! Map) return null;
    final at = raw['withdrawnAt'];
    return SurrenderWithdrawal(
      reason: SurrenderWithdrawalReason.fromName(raw['reason']),
      otherText: raw['otherText'] as String?,
      details: raw['details'] as String?,
      withdrawnAt: at is Timestamp ? at.toDate() : null,
    );
  }
}
