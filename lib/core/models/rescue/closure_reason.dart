/// Why a rescue case was closed through the shared Close Case flow (see
/// RescueCaseRepository.closeCase / close_case_sheet.dart). Stable
/// internal `.name` values are what's actually persisted
/// (`closureReason`); `.label` is the only thing ever shown to a user, so
/// relabeling later never requires a data migration.
///
/// Reduced to exactly the 5 approved reasons — every previously-offered
/// reason not on this list (hasOwner, animalMoved, clinicUnavailable,
/// duplicateReport, resolvedWithoutTransport, reporterWithdrew,
/// transferredOutsideWorkflow, other) is gone from the picker. Owner-found
/// and reunited-with-owner collapsed into the single [reunited] reason;
/// "requires specialized transport" is now just [requiresTransport].
enum ClosureReason {
  requiresTransport,
  died,
  aggressive,
  reunited,
  rescuedOutsideWorkflow,
  // Never shown in the Close Case picker (see [selectable]) — exists only
  // so [fromName] has somewhere safe to land for a `closureReason` value
  // written before this reduction to 5 reasons (hasOwner/animalMoved/
  // clinicUnavailable/duplicateReport/resolvedWithoutTransport/
  // requiresSpecializedTransport/reporterWithdrew/
  // transferredOutsideWorkflow/other). No current write path ever
  // persists this value.
  legacyOther;

  String get label => switch (this) {
    ClosureReason.requiresTransport => 'Requires transport',
    ClosureReason.died => 'Died',
    ClosureReason.aggressive => 'Aggressive',
    ClosureReason.reunited => 'Reunited',
    ClosureReason.rescuedOutsideWorkflow => 'Rescued outside ResPAWnd',
    ClosureReason.legacyOther => 'Other (legacy closure reason)',
  };

  /// The only 5 reasons ever offered in the Close Case picker
  /// (close_case_sheet.dart iterates this, not `ClosureReason.values`,
  /// specifically so [legacyOther] never appears as a 6th option).
  static const List<ClosureReason> selectable = [
    ClosureReason.requiresTransport,
    ClosureReason.died,
    ClosureReason.aggressive,
    ClosureReason.reunited,
    ClosureReason.rescuedOutsideWorkflow,
  ];

  /// The only reason with a genuine per-animal outcome to record — see
  /// RescueCaseRepository.closeCase's animalIndexes handling. Every other
  /// reason ends the whole case, since none of them have a per-animal field
  /// this codebase can independently resolve.
  bool get isDeathReason => this == ClosureReason.died;

  /// The org must say exactly what kind of transport the animal actually
  /// needs (e.g. a van/enclosed vehicle, a secure crate, two-person
  /// handling) — this is what later shows up on the case's service
  /// request so whoever picks it up next (Assign Transporter) knows what's
  /// required instead of finding out on-site again.
  bool get needsServiceType => this == ClosureReason.requiresTransport;

  static ClosureReason fromName(String? value) => ClosureReason.values
      .firstWhere((v) => v.name == value, orElse: () => ClosureReason.legacyOther);
}
