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
}
