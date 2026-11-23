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

  /// Rescue volunteers (independent rescuers, organizations with kind
  /// 'independent'). Off for now: their entry points stay on screen but
  /// grayed out and not tappable (the Rescue Volunteer sign-up card, Refer →
  /// Rescue Volunteer, transferring a record to a volunteer, the Rescue
  /// Volunteers menu items), and their dashboard cards are hidden. The
  /// screens, data, functions and rules stay; set to true to turn them on.
  static const bool independentRescuersEnabled = false;

  /// Shown under a grayed-out rescue volunteer entry point.
  static const String rescueVolunteersOffNote = 'Not available yet';

  /// Care tasks (care rounds, roster, the Daily care permission box) are
  /// hidden from the admin side menu, the dashboard and the Staff access
  /// editor. The screens, data, permission and rules stay; set to true to
  /// show them again.
  static const bool careTasksEnabled = false;
}
