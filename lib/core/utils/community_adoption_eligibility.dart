import 'package:respawnd1/core/models/rescue/rejection_reason.dart';

/// A case counts as "Community Adoption eligible" once an organization has
/// rejected it specifically because the animal was assessed as healthy /
/// low urgency (RejectionReason.healthyAnimalLowUrgency) — see
/// rescue_case_repository.dart's rejectCase, which writes
/// status: 'rejected' + rejectionReason: reason.name.
///
/// Lost Pet reports are always excluded, even if rejected for this same
/// reason: a lost pet still has an owner, so it is never a rehoming
/// candidate — only unowned/stray reports can transition into a Community
/// Adoption listing (see NEW-CAP-2507-IT-PROPOSAL.pdf §1.4.5).
///
/// Used by explore_reports_map.dart / public_rescue_feed.dart (so these
/// cases stay visible instead of being hidden like a normal rejection) and
/// by track_case_page.dart (so the "List for Community Adoption" button
/// only shows up for cases that actually qualify).
bool isCommunityAdoptionEligible({
  required String? status,
  required String? rejectionReason,
  required String? rescueType,
}) {
  final normalizedStatus = (status ?? '').trim().toLowerCase();
  if (normalizedStatus != 'rejected') return false;

  if (rejectionReason != RejectionReason.healthyAnimalLowUrgency.name) {
    return false;
  }

  final normalizedRescueType = (rescueType ?? '').trim().toLowerCase();
  if (normalizedRescueType == 'lost pet') return false;

  return true;
}