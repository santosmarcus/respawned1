/// Centralized feature toggles for user-facing entry points. Flip a value
/// here to re-enable a feature — never gate the same feature with a second,
/// scattered boolean elsewhere.
class FeatureFlags {
  const FeatureFlags._();

  /// Temporarily disabled per product request — the Organizations list/
  /// profile pages, models, and repositories all stay in the codebase and
  /// admin-side organization management is untouched; only the user-facing
  /// "Organization" quick-action entry point on Home is hidden/disabled.
  /// Set back to true to re-enable that entry point.
  static const bool organizationsFeatureEnabled = false;

  /// The app is scoped to one organization for now. Off hides everything
  /// that works between organizations: referring a case to another
  /// organization, transferring an animal or record to one, the "Open for
  /// transfer" switch on Accept Case, and Organization approvals in the
  /// admin drawer (system admins approve sign-ups from their own console).
  /// The code, data and rules stay; set to true to bring them back.
  static const bool multiOrganizationEnabled = false;

  /// Independent rescuers (organizations with kind 'independent'). On shows
  /// Refer → Rescue Volunteer to shelters, and lets an independent rescuer
  /// refer a case on to a shelter or rescue group (their way to hand over a
  /// case they can't finish), even while [multiOrganizationEnabled] is off.
  static const bool independentRescuersEnabled = true;
}
