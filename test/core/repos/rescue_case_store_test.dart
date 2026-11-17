import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

void main() {
  group('RescueCaseStore.stageSummaryUpdate', () {
    test('legacy case with no animals writes nothing', () {
      expect(RescueCaseStore.stageSummaryUpdate(const []), isEmpty);
    });

    test(
      'counts in_treatment / intake stages, skipping deceased and resolved',
          () {
        final summary = RescueCaseStore.stageSummaryUpdate([
          {'postTreatmentAction': null},
          {'postTreatmentAction': null},
          {'postTreatmentAction': 'intake', 'intakeCompletedAt': null},
          {'postTreatmentAction': 'intake', 'intakeCompletedAt': 'done'},
          {'postTreatmentAction': 'release', 'releaseCompletedAt': 'done'},
          {'outcome': 'deceased'},
        ]);
        expect(summary['activeAnimalStages'], ['in_treatment', 'intake']);
        expect(summary['animalStageCounts'], {'in_treatment': 2, 'intake': 1});
      },
    );

    test('an animal waiting for its adopter stays in treatment until collected', () {
      final waiting = RescueCaseStore.stageSummaryUpdate([
        {'postTreatmentAction': 'release', 'releaseCompletedAt': null},
      ]);
      expect(waiting['animalStageCounts'], {'in_treatment': 1});
      final collected = RescueCaseStore.stageSummaryUpdate([
        {'postTreatmentAction': 'release', 'releaseCompletedAt': 'done'},
      ]);
      expect(collected['animalStageCounts'], isEmpty);
    });
  });

  group('RescueCaseStore.deriveCaseStatusOverride', () {
    test('null for a legacy case with no animals', () {
      expect(RescueCaseStore.deriveCaseStatusOverride(const []), isNull);
    });

    test('treatment while any living animal is un-actioned', () {
      expect(
        RescueCaseStore.deriveCaseStatusOverride([
          {'postTreatmentAction': null},
          {'postTreatmentAction': 'release', 'releaseCompletedAt': 'done'},
        ]),
        RescueStatus.treatment.firestoreValue,
      );
    });

    test('treatment while the confirmed adopter has not collected the animal', () {
      expect(
        RescueCaseStore.deriveCaseStatusOverride([
          {'postTreatmentAction': 'release', 'releaseCompletedAt': null},
          {'postTreatmentAction': 'transfer'},
        ]),
        RescueStatus.treatment.firestoreValue,
      );
      expect(
        RescueCaseStore.deriveCaseStatusOverride([
          {'postTreatmentAction': 'release', 'releaseCompletedAt': 'done'},
        ]),
        RescueStatus.completed.firestoreValue,
      );
    });

    test('intake while an intake action is still pending', () {
      expect(
        RescueCaseStore.deriveCaseStatusOverride([
          {'outcome': 'deceased'},
          {'postTreatmentAction': 'intake', 'intakeCompletedAt': null},
        ]),
        RescueStatus.intake.firestoreValue,
      );
    });

    test('completed once every animal has resolved', () {
      expect(
        RescueCaseStore.deriveCaseStatusOverride([
          {'outcome': 'deceased'},
          {'postTreatmentAction': 'transfer'},
          {'postTreatmentAction': 'intake', 'intakeCompletedAt': 'done'},
        ]),
        RescueStatus.completed.firestoreValue,
      );
    });
  });
}
