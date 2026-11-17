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

/// The Fit Assessment as staff saw it when they accepted or rejected an
/// application, saved on the application (`adoptions/{id}.fitAtDecision`)
/// so the score behind a decision can be shown later even after the form,
/// the animal record or the rubric change. Several people can apply for one
/// animal, so this is what explains why one was chosen.
class FitAtDecision {
  /// 'approved' or 'rejected'.
  final String decision;
  final DateTime? decidedAt;
  final String? decidedBy;

  /// Null when no score could be calculated (no linked animal record).
  final AdoptionFitAssessment? assessment;

  /// The staff's own manual fit value (FitAssessmentValue name) and who set
  /// it, as they stood at the decision.
  final String? staffFitValue;
  final String? staffFitBy;

  /// The staff notes on the application at the decision, newest first.
  final List<({String text, String? by, DateTime? at})> staffNotes;

  const FitAtDecision({
    required this.decision,
    this.decidedAt,
    this.decidedBy,
    this.assessment,
    this.staffFitValue,
    this.staffFitBy,
    this.staffNotes = const [],
  });

  int? get rubricVersion => assessment?.version;

  /// Firestore map. [decidedAt] is left to the caller (server timestamp).
  static Map<String, dynamic> toMap({
    required String decision,
    required String decidedBy,
    required AdoptionFitAssessment? assessment,
    String? staffFitValue,
    String? staffFitBy,
    DateTime? staffFitAt,
    List<({String text, String? by, DateTime? at})> staffNotes = const [],
  }) =>
      {
        'decision': decision,
        'decidedBy': decidedBy,
        'rubricVersion': assessment?.version,
        if (assessment != null)
          'assessment': {
            'score': assessment.score,
            'band': assessment.band.name,
            'completeness': assessment.completeness,
            'insufficientData': assessment.insufficientData,
            'categoryScores': [
              for (final c in assessment.categoryScores) {'label': c.label, 'score': c.score, 'maxScore': c.maxScore},
            ],
            'strengths': assessment.strengths,
            'concerns': assessment.concerns,
            'unassessedItems': assessment.unassessedItems,
            'version': assessment.version,
            'calculatedAt': assessment.calculatedAt.toIso8601String(),
          },
        'staffFit': {
          'value': staffFitValue,
          'assessedBy': staffFitBy,
          'assessedAt': staffFitAt?.toIso8601String(),
        },
        'staffNotes': [
          for (final n in staffNotes) {'text': n.text, 'by': n.by, 'at': n.at?.toIso8601String()},
        ],
      };

  /// Reads the saved map back; null when there is none or it is unreadable.
  /// [decidedAt] is the Firestore timestamp converted by the caller.
  static FitAtDecision? fromMap(Object? raw, {DateTime? decidedAt}) {
    if (raw is! Map) return null;
    final decision = raw['decision'];
    if (decision is! String) return null;
    AdoptionFitAssessment? assessment;
    final a = raw['assessment'];
    if (a is Map && a['score'] is num) {
      final score = (a['score'] as num).toInt();
      List<String> strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];
      assessment = AdoptionFitAssessment(
        score: score,
        band: FitAssessmentBand.values.firstWhere(
          (b) => b.name == a['band'],
          orElse: () => FitAssessmentBand.fromScore(score),
        ),
        completeness: (a['completeness'] as num?)?.toInt() ?? 0,
        categoryScores: [
          if (a['categoryScores'] is List)
            for (final c in (a['categoryScores'] as List).whereType<Map>())
              FitAssessmentCategoryScore(
                label: c['label'] as String? ?? '',
                score: (c['score'] as num?)?.toInt() ?? 0,
                maxScore: (c['maxScore'] as num?)?.toInt() ?? 0,
              ),
        ],
        strengths: strings(a['strengths']),
        concerns: strings(a['concerns']),
        unassessedItems: strings(a['unassessedItems']),
        version: (a['version'] as num?)?.toInt() ?? (raw['rubricVersion'] as num?)?.toInt() ?? 0,
        calculatedAt: DateTime.tryParse(a['calculatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        insufficientData: a['insufficientData'] == true,
      );
    }
    final staffFit = raw['staffFit'] is Map ? raw['staffFit'] as Map : const {};
    return FitAtDecision(
      decision: decision,
      decidedAt: decidedAt,
      decidedBy: raw['decidedBy'] as String?,
      assessment: assessment,
      staffFitValue: staffFit['value'] as String?,
      staffFitBy: staffFit['assessedBy'] as String?,
      staffNotes: [
        if (raw['staffNotes'] is List)
          for (final n in (raw['staffNotes'] as List).whereType<Map>())
            if (n['text'] is String)
              (
                text: n['text'] as String,
                by: n['by'] as String?,
                at: DateTime.tryParse(n['at'] as String? ?? ''),
              ),
      ],
    );
  }
}
