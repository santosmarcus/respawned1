/// Result of the rule-based Fit Assessment (see
/// core/services/adoption_fit_assessment_service.dart). This is an
/// administrative decision-support summary only — it never approves,
/// rejects, reserves, or ranks an applicant on its own; every field here
/// exists to explain a score in plain language, not to automate a
/// decision. Computed at runtime from the current AdoptionApplication +
/// AnimalRecord (see the service's own doc comment on why nothing here is
/// persisted yet), so this class has no `fromFirestore` — only the plain
/// constructor a fresh calculation returns.
library;

/// Neutral score bands — never phrased as "approved"/"rejected" and never
/// styled like an approval/rejection status in the UI.
enum FitAssessmentBand {
  strong, // 80-100
  moderate, // 60-79
  needsReview, // 40-59
  significantConcerns; // 0-39

  String get label => switch (this) {
        FitAssessmentBand.strong => 'Strong potential fit',
        FitAssessmentBand.moderate => 'Moderate potential fit',
        FitAssessmentBand.needsReview => 'Needs further review',
        FitAssessmentBand.significantConcerns => 'Significant concerns',
      };

  static FitAssessmentBand fromScore(int score) {
    if (score >= 80) return FitAssessmentBand.strong;
    if (score >= 60) return FitAssessmentBand.moderate;
    if (score >= 40) return FitAssessmentBand.needsReview;
    return FitAssessmentBand.significantConcerns;
  }
}

/// One scored category's contribution — e.g. "Housing and permission: 18/20".
class FitAssessmentCategoryScore {
  final String label;
  final int score;
  final int maxScore;
  const FitAssessmentCategoryScore({required this.label, required this.score, required this.maxScore});
}

class AdoptionFitAssessment {
  /// 0-100. Always the sum of [categoryScores] — never a separately
  /// invented number — so the admin UI's "category totals equal the
  /// overall score" check always holds by construction.
  final int score;
  final FitAssessmentBand band;

  /// 0-100 — the percentage of individually-assessable rubric line items
  /// that actually had usable data (see the service's doc comment on how
  /// "not applicable" differs from "not assessed"). Low completeness means
  /// the score above is built on mostly-missing data, not that the
  /// applicant scored poorly.
  final int completeness;
  final List<FitAssessmentCategoryScore> categoryScores;

  /// Plain-language sentences — never raw field names like
  /// `landlordAllowsPets`.
  final List<String> strengths;
  final List<String> concerns;
  final List<String> unassessedItems;

  final int version;
  final DateTime calculatedAt;

  /// True when there wasn't enough application/animal data to produce a
  /// meaningful score at all — the UI shows "Fit assessment unavailable"
  /// instead of [score]/[band] in that case (see the service's threshold).
  final bool insufficientData;

  const AdoptionFitAssessment({
    required this.score,
    required this.band,
    required this.completeness,
    required this.categoryScores,
    required this.strengths,
    required this.concerns,
    required this.unassessedItems,
    required this.version,
    required this.calculatedAt,
    this.insufficientData = false,
  });
}
