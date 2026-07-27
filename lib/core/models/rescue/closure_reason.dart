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
  requiresSpecializedTransport,
  // Added for the controlled Close Case flow (Ongoing/Treatment/Intake) —
  // two suggested reasons with no existing equivalent. Every other
  // suggested reason from that spec already has a close match above
  // (reunitedWithOwner covers "Owner reclaimed animal", animalMoved covers
  // "could not be located", aggressiveAnimal covers "safety risk").
  reporterWithdrew,
  transferredOutsideWorkflow,
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
    ClosureReason.requiresSpecializedTransport =>
      'Animal requires specialized transport we cannot provide',
    ClosureReason.reporterWithdrew => 'Reporter withdrew',
    ClosureReason.transferredOutsideWorkflow =>
      'Transferred outside the ResPAWnd workflow',
    ClosureReason.other => 'Other',
  };

  /// The only reason with a genuine per-animal outcome to record — see
  /// RescueCaseRepository.closeCase's animalIndexes handling. Every other
  /// reason ends the whole case, since none of them have a per-animal field
  /// this codebase can independently resolve (a duplicate report, a
  /// reclaimed owner, etc. describe the case as a whole, not one animal
  /// among several).
  bool get isDeathReason => this == ClosureReason.diedDuringRescue;

  /// Reasons where the closure form asks for a specific extra field beyond
  /// the always-required detailed explanation (spec §2 "Conditionally
  /// require additional information depending on the reason").
  bool get needsLastKnownLocation => this == ClosureReason.animalMoved;
  bool get needsClinicDetails => this == ClosureReason.clinicUnavailable;

  /// The org must say exactly what kind of transport the animal actually
  /// needs (e.g. a van/enclosed vehicle, a secure crate, two-person
  /// handling) — this is what later shows up on the case's service
  /// request so whoever picks it up next (Assign Transporter) knows what's
  /// required instead of finding out on-site again.
  bool get needsServiceType =>
      this == ClosureReason.requiresSpecializedTransport;

  static ClosureReason fromName(String? value) => ClosureReason.values
      .firstWhere((v) => v.name == value, orElse: () => ClosureReason.other);
}
