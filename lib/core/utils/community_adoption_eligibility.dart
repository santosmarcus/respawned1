import 'package:respawnd1/core/models/rescue/rejection_reason.dart';

/// The status a Pet Surrender is filed with: listed for Community Adoption
/// straight away (RescueStatus.communityAdoption).
const String kCommunityAdoptionStatus = 'community_adoption';

/// Whether [rescueType] is a Pet Surrender ('Pet Surrender', or 'Surrender'
/// on older documents).
bool isSurrenderRescueType(String? rescueType) {
  final t = (rescueType ?? '').trim().toLowerCase();
  return t == 'pet surrender' || t == 'surrender';
}

/// A Pet Surrender in [kCommunityAdoptionStatus] is eligible as soon as it
/// is filed: the organization does not facilitate surrenders, so no
/// review or decision is involved.
///
/// Other reports count as "Community Adoption eligible" once an organization has
/// rejected it specifically because the animal was assessed as healthy /
/// low urgency (RejectionReason.healthyAnimalLowUrgency) — see
/// RescueCaseRepository.rejectCase, which writes
/// `status: 'rejected'` + `rejectionReason: reason.name`.
///
/// Lost Pet reports are always excluded, even if rejected for this same
/// reason: a lost pet still has an owner, so it is never a rehoming
/// candidate — only unowned/stray reports can transition into a Community
/// Adoption listing.
///
/// Used by public_case_visibility.dart (so these cases stay visible
/// instead of being hidden like a normal rejection) and by
/// community_adoption_track_page.dart (so the "Community Adoption" button
/// only shows up for cases that actually qualify).
bool isCommunityAdoptionEligible({
  required String? status,
  required String? rejectionReason,
  required String? rescueType,
}) {
  final normalizedStatus = (status ?? '').trim().toLowerCase();
  if (normalizedStatus == kCommunityAdoptionStatus) {
    return isSurrenderRescueType(rescueType);
  }
  if (normalizedStatus != 'rejected') return false;

  if (rejectionReason != RejectionReason.healthyAnimalLowUrgency.name) {
    return false;
  }

  final normalizedRescueType = (rescueType ?? '').trim().toLowerCase();
  if (normalizedRescueType == 'lost pet') return false;

  return true;
}
