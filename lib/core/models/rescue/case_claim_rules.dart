import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/organization/org_permission.dart';

/// Thrown when Accept Case can't go ahead: someone else took the case first,
/// it hasn't opened to this rescuer yet, or the rescuer is at capacity.
/// [message] is ready to show.
class CaseClaimException implements Exception {
  const CaseClaimException(this.message, {this.alreadyTaken = false});

  final String message;

  /// Another organization accepted the case first.
  final bool alreadyTaken;

  @override
  String toString() => message;
}

/// Why [myOrgId] can't accept a case right now, or null if it can. Pure;
/// CaseStatusRepository.acceptCase runs it inside the accepting transaction
/// on fresh copies of the case and organization, and firestore.rules checks
/// the ownership and head-start parts again.
///
/// - Only an unowned case (or one already this organization's, or referred
///   to it) can be accepted: the first organization to accept wins.
/// - An independent rescuer may take an unowned case only once it has
///   opened to them (the case lists them in nearbyIndependentIds and
///   independentsOpenAt has passed), and only while under capacity and
///   taking cases.
CaseClaimException? caseClaimRefusal({
  required Map<String, dynamic> caseData,
  required String myOrgId,
  required Map<String, dynamic>? org,
  required DateTime now,
}) {
  final owner = caseData['organizationId'] as String? ?? '';
  final referredTo = caseData['referredToOrgId'] as String? ?? '';
  if (owner.isNotEmpty && owner != myOrgId) {
    return const CaseClaimException(
      'An organization already accepted this case. It has been removed from your list.',
      alreadyTaken: true,
    );
  }
  if (owner.isEmpty && referredTo.isNotEmpty && referredTo != myOrgId) {
    return const CaseClaimException('This case was referred to another organization.', alreadyTaken: true);
  }

  if (OrgKind.fromName(org?['kind'] as String?) != OrgKind.independent) return null;

  final referredToMe = referredTo == myOrgId;
  if (owner.isEmpty && !referredToMe) {
    final nearby = (caseData['nearbyIndependentIds'] as List?)?.whereType<String>() ?? const <String>[];
    final openAt = caseData['independentsOpenAt'];
    final opensAt = openAt is Timestamp ? openAt.toDate() : null;
    if (!nearby.contains(myOrgId) || opensAt == null) {
      return const CaseClaimException('This case is outside your area. An organization can refer it to you.');
    }
    if (now.isBefore(opensAt)) {
      return const CaseClaimException('Shelters get first look at this case. It opens to you shortly.');
    }
  }

  // Re-accepting a case already theirs never counts against capacity.
  return owner.isEmpty ? independentCapacityRefusal(org) : null;
}

/// Why an independent rescuer can't take one more case (paused, at its case
/// limit, or full of animals), or null. Always null for a shelter. Used by
/// Accept Case and by accepting a referral.
CaseClaimException? independentCapacityRefusal(Map<String, dynamic>? org) {
  if (OrgKind.fromName(org?['kind'] as String?) != OrgKind.independent) return null;
  if (org?['acceptingCases'] == false) {
    return const CaseClaimException("You're paused. Turn Available on to take cases.");
  }
  int n(String k, int fallback) => (org?[k] as num?)?.toInt() ?? fallback;
  final cases = n('activeCaseCount', 0);
  final maxCases = n('maxActiveCases', IndependentRescuer.maxActiveCases);
  if (cases >= maxCases) {
    return CaseClaimException(
        'You already have $cases active case(s), your limit. Finish or refer one before taking another.');
  }
  final animals = n('animalsInCareCount', 0);
  final maxAnimals = n('maxAnimalsInCare', IndependentRescuer.maxAnimalsInCare);
  if (animals >= maxAnimals) {
    return CaseClaimException(
        'You already have $animals animal(s) in care, your limit. Rehome or transfer one before taking another case.');
  }
  return null;
}
