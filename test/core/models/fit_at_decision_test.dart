import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/adoption/adoption_fit_assessment.dart';

void main() {
  final assessment = AdoptionFitAssessment(
    score: 72,
    band: FitAssessmentBand.moderate,
    completeness: 90,
    categoryScores: const [
      FitAssessmentCategoryScore(label: 'Housing and permission', score: 18, maxScore: 20),
      FitAssessmentCategoryScore(label: 'Care plan', score: 14, maxScore: 20),
    ],
    strengths: const ['Landlord allows pets'],
    concerns: const ['Alone 9 hours a day'],
    unassessedItems: const ['Previous vet reference'],
    version: 1,
    calculatedAt: DateTime.utc(2026, 11, 17, 9),
  );

  test('the saved score reads back as it was at the decision', () {
    final map = FitAtDecision.toMap(
      decision: 'approved',
      decidedBy: 'Ana Staff',
      assessment: assessment,
      staffFitValue: 'goodCandidate',
      staffFitBy: 'Ben Staff',
      staffNotes: [(text: 'Met the family on site.', by: 'Ana Staff', at: DateTime.utc(2026, 11, 16))],
    );
    expect(map['rubricVersion'], 1);

    final saved = FitAtDecision.fromMap(map, decidedAt: DateTime.utc(2026, 11, 17, 10))!;
    expect(saved.decision, 'approved');
    expect(saved.decidedBy, 'Ana Staff');
    expect(saved.rubricVersion, 1);
    expect(saved.assessment!.score, 72);
    expect(saved.assessment!.band, FitAssessmentBand.moderate);
    expect(saved.assessment!.completeness, 90);
    expect(saved.assessment!.categoryScores.map((c) => c.score), [18, 14]);
    expect(saved.assessment!.concerns, ['Alone 9 hours a day']);
    expect(saved.staffFitValue, 'goodCandidate');
    expect(saved.staffFitBy, 'Ben Staff');
    expect(saved.staffNotes.single.text, 'Met the family on site.');
    expect(saved.staffNotes.single.at, DateTime.utc(2026, 11, 16));
  });

  test('a decision without a calculated score still records the staff view', () {
    final map = FitAtDecision.toMap(decision: 'rejected', decidedBy: 'Ana Staff', assessment: null);
    final saved = FitAtDecision.fromMap(map)!;
    expect(saved.assessment, isNull);
    expect(saved.rubricVersion, isNull);
    expect(saved.staffFitValue, isNull);
    expect(saved.staffNotes, isEmpty);
  });

  test('nothing saved reads as null', () {
    expect(FitAtDecision.fromMap(null), isNull);
    expect(FitAtDecision.fromMap({'score': 50}), isNull);
  });
}
