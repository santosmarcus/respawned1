/// Reasons an organization can give when rejecting a rescue report.
/// Persisted on the case doc as `rejectionReason` (enum name) plus an
/// optional free-text `rejectionReasonOther` when [other] is chosen.
enum RejectionReason {
  noAvailableRiders,
  healthyAnimalLowUrgency,
  noShelterSpace,
  invalidOrFalseReport,
  animalAlreadyRescued,
  duplicateReport,
  outsideServiceArea,
  insufficientInformation,
  other;

  String get label => switch (this) {
        RejectionReason.noAvailableRiders => 'No available riders',
        RejectionReason.healthyAnimalLowUrgency =>
          'Healthy animal / low urgency',
        RejectionReason.noShelterSpace => 'No shelter space',
        RejectionReason.invalidOrFalseReport => 'Invalid or false report',
        RejectionReason.animalAlreadyRescued => 'Animal already rescued',
        RejectionReason.duplicateReport => 'Duplicate report',
        RejectionReason.outsideServiceArea => 'Outside service area',
        RejectionReason.insufficientInformation =>
          'Insufficient information',
        RejectionReason.other => 'Other',
      };

  static RejectionReason fromName(String? value) => RejectionReason.values
      .firstWhere((e) => e.name == value, orElse: () => RejectionReason.other);
}
