import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';

/// Whether a `cases/{id}` document should appear in a public-facing surface
/// (the Explore feed and map) — shared by both, previously two hand-rolled,
/// independently-drifting copies (the map's own set additionally excluded
/// `'ended'`/`'merged'`; the feed's did not). One source of truth from here
/// on, so the feed and map can never disagree about whether the same case
/// is visible.
///
/// [reporterId] / [viewerId] — a reporter's own case is hidden from the
/// public Explore surfaces (they already see it in My Reports/Track Case),
/// but this predicate is never applied to the admin Rescue Reports queue or
/// the reporter's own tracking page, which don't call this function at all.
bool isCasePublic({
  required String? reporterId,
  required String? viewerId,
  required String? status,
  required String? rejectionReason,
  required String? rescueType,
  required bool hiddenFromExplore,
  required String? groupId,
  required String docId,
}) {
  if (reporterId != null && reporterId == viewerId) return false;
  if (hiddenFromExplore) return false;

  // A duplicate multi-animal report saved before the `animals[]` array
  // existed wrote one `cases` doc per animal, linked by a shared `groupId`
  // — only the "primary" doc (its own id == groupId) represents the group
  // publicly; every sibling doc is skipped so it doesn't show up as an
  // extra, near-identical public item.
  if (groupId != null && groupId.isNotEmpty && groupId != docId) return false;

  final normalizedStatus = (status ?? '').trim().toLowerCase();

  // A report rejected specifically for being healthy/low-urgency (and not a
  // Lost Pet) transitions into Community Adoption instead of disappearing
  // like a normal rejection — stays visible either way.
  final communityAdoptionEligible = isCommunityAdoptionEligible(
    status: status,
    rejectionReason: rejectionReason,
    rescueType: rescueType,
  );
  if (communityAdoptionEligible) return true;

  const dismissedStatuses = {
    'dismissed',
    'ended',
    'cancelled',
    'withdrawn',
    'rejected',
    'merged',
  };
  if (dismissedStatuses.contains(normalizedStatus)) return false;

  final isFinalStatus = normalizedStatus == 'closed' ||
      normalizedStatus.contains('completed') ||
      normalizedStatus.contains('ended');
  if (isFinalStatus) return false;

  return true;
}
