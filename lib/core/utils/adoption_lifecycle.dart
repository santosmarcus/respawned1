import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';

/// Centralized post-approval classification (Adoption Tab Classification
/// spec) — the single source of truth every tab list, badge count, card,
/// and detail-page route must agree on, instead of each screen re-deriving
/// its own notion of "is this adopted yet". [pending]/[interview]/
/// [rejected]/[withdrawn] pass straight through from [AdoptionStatus];
/// [release]/[adopted]/[complete]/[returns] are all derived from the
/// `AdoptionStatus.approved`/`AdoptionStatus.adopted` buckets using the
/// richer fields release/return/post-adoption already write.
enum AdoptionLifecycleStage {
  pending,
  interview,
  release,
  adopted,
  complete,
  returns,
  rejected,
  withdrawn;

  String get label => switch (this) {
        AdoptionLifecycleStage.pending => 'Pending',
        AdoptionLifecycleStage.interview => 'Interview',
        AdoptionLifecycleStage.release => 'Release',
        AdoptionLifecycleStage.adopted => 'Adopted',
        AdoptionLifecycleStage.complete => 'Complete',
        AdoptionLifecycleStage.returns => 'Returns',
        AdoptionLifecycleStage.rejected => 'Rejected',
        AdoptionLifecycleStage.withdrawn => 'Withdrawn',
      };
}

/// True while a return request is actively in progress — the exact same
/// definition post_adoption_details_page.dart's own return banner already
/// used (not declined, not cancelled, not yet processed through intake),
/// now centralized so every caller (tabs, badges, cards, banners) agrees.
bool isReturnActive(ReturnRequest? returnRequest) {
  if (returnRequest == null) return false;
  return returnRequest.status != ReturnRequestStatus.declined &&
      returnRequest.status != ReturnRequestStatus.cancelled &&
      returnRequest.status != ReturnRequestStatus.intake;
}

/// Classifies one application into the stage its card/tab/badge should
/// agree on. Priority for anything in the `adopted` status bucket (Adoption
/// Tab Classification spec §7): active return > fully-complete monitoring >
/// plain adopted. A resolved return (declined/cancelled, or already
/// processed to intake) is NOT treated as "returns" anymore — it falls back
/// to Adopted/Complete based on its own post-adoption state, so no
/// application is stuck in Returns forever after its return is resolved.
AdoptionLifecycleStage classifyAdoptionLifecycle(AdoptionApplication app) {
  switch (app.status) {
    case AdoptionStatus.pending:
      return AdoptionLifecycleStage.pending;
    case AdoptionStatus.interview:
      return AdoptionLifecycleStage.interview;
    case AdoptionStatus.rejected:
      return AdoptionLifecycleStage.rejected;
    case AdoptionStatus.withdrawn:
      return AdoptionLifecycleStage.withdrawn;
    case AdoptionStatus.approved:
      // Approved but not yet released/handed over. Nothing reaches
      // AdoptionStatus.approved with release already completed — release
      // and the flip to AdoptionStatus.adopted happen in the same atomic
      // write (see AdoptionApplicationRepository.releaseWithFollowUps) —
      // so "approved" alone is always an accurate proxy for "release
      // incomplete", with no separate handover flag needed today.
      return AdoptionLifecycleStage.release;
    case AdoptionStatus.adopted:
      // Covers the canonical 'adopted' raw value plus every legacy raw
      // value AdoptionStatus.fromFirestoreValue folds into it ('completed',
      // 'return_requested', 'return_approved').
      if (isReturnActive(app.returnRequest)) return AdoptionLifecycleStage.returns;
      // Legacy ambiguity (spec §11): a pre-module doc may have raw status
      // 'completed' with no postAdoptionStatus field at all — that field
      // defaults to 'inProgress' in AdoptionApplication.fromFirestore, so
      // such a doc intentionally falls through to Adopted here rather than
      // being assumed Complete without follow-up evidence.
      if (app.postAdoptionStatus == 'completed') return AdoptionLifecycleStage.complete;
      return AdoptionLifecycleStage.adopted;
  }
}
