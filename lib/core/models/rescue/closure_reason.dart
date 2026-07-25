/// Why a rescue case was closed through the shared Close Case flow (see
/// RescueCaseRepository.closeCase / close_case_sheet.dart). Stable
/// internal `.name` values are what's actually persisted
/// (`closureReason`); `.label` is the only thing ever shown to a user, so
/// relabeling later never requires a data migration.
enum ClosureReason {
  hasOwner,
  reunitedWithOwner,
  aggressiveAnimal,
  diedDuringRescue,
  animalMoved,
  clinicUnavailable,
  duplicateReport,
  resolvedWithoutTransport,
  other;

  String get label => switch (this) {
        ClosureReason.hasOwner => 'Animal has an owner',
        ClosureReason.reunitedWithOwner => 'Animal reunited with owner',
        ClosureReason.aggressiveAnimal => 'Aggressive animal / unsafe rescue',
        ClosureReason.diedDuringRescue => 'Animal died during rescue',
        ClosureReason.animalMoved => 'Animal moved / could not be located',
        ClosureReason.clinicUnavailable => 'Clinic unavailable',
        ClosureReason.duplicateReport => 'Duplicate report',
        ClosureReason.resolvedWithoutTransport => 'Resolved without transport',
        ClosureReason.other => 'Other',
      };

  /// Reasons where the closure form asks for a specific extra field beyond
  /// the always-required detailed explanation (spec §2 "Conditionally
  /// require additional information depending on the reason").
  bool get needsLastKnownLocation => this == ClosureReason.animalMoved;
  bool get needsClinicDetails => this == ClosureReason.clinicUnavailable;

  static ClosureReason fromName(String? value) =>
      ClosureReason.values.firstWhere((v) => v.name == value, orElse: () => ClosureReason.other);
}
