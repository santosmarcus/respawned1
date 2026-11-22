import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/urgency_assessment.dart';

/// A complete, healthy-looking assessment; tests override what they need.
AnimalUrgencyInput animal({
  String? injury = kInjuryNone,
  String? injuryVisibleInPhotos,
  String? bodyCondition = 'Normal',
  String? mobility = 'Walks and runs normally',
  String? alertness = 'Alert/responsive',
  String? eyes = 'Clear and no discharge',
  String? skin = 'Clean; no visible skin disease (fleas/ticks, mange)',
  String? appetite = 'Eating/drinking normally',
  Set<String> behavior = const {'Calm'},
  Set<String> environment = const {'Safe Location'},
  String? biteRisk = 'Low',
  String? sex,
  String? hasLitter,
  String? suspectedPregnancy,
  Set<String> signs = const {},
  String? needsMedical,
}) =>
    AnimalUrgencyInput(
      injury: injury,
      injuryVisibleInPhotos: injuryVisibleInPhotos,
      bodyCondition: bodyCondition,
      mobility: mobility,
      alertness: alertness,
      eyesNoseMouth: eyes,
      skinAndCoat: skin,
      appetiteHydration: appetite,
      behavior: behavior,
      environmentSafety: environment,
      biteRisk: biteRisk,
      sex: sex,
      hasLitter: hasLitter,
      suspectedPregnancy: suspectedPregnancy,
      visibleSigns: signs,
      needsMedical: needsMedical,
    );

void main() {
  group('Low', () {
    test('healthy animal with normal behavior is Low', () {
      final r = assessAnimalUrgency(animal());
      expect(r.level, kUrgencyLow);
      expect(r.needsStaffVerification, isFalse);
    });

    test('small wound with normal, responsive behavior is not Critical (Low)', () {
      final r = assessAnimalUrgency(animal(injury: kInjuryMinor, injuryVisibleInPhotos: kInjuryPhotoOptions[0]));
      expect(r.level, kUrgencyLow);
      expect(r.reasons.first, contains('Minor injury'));
    });
  });

  group('Medium', () {
    test('moderate wound alone is Medium', () {
      expect(assessAnimalUrgency(animal(injury: kInjuryModerate)).level, kUrgencyMedium);
    });

    test('serious injury on a responsive animal is not disregarded (Medium, not Low)', () {
      final r = assessAnimalUrgency(animal(injury: kInjurySevere));
      expect(r.level, kUrgencyMedium);
      expect(r.reasons.first, contains('Severe injury'));
    });

    test('a single severe sign without corroboration is never Critical', () {
      for (final a in [
        animal(bodyCondition: kBodyConditionOptions[3]),
        animal(injury: kInjuryModerate, skin: kSkinAndCoatOptions[2]),
        animal(mobility: kMobilityOptions[2]),
      ]) {
        expect(assessAnimalUrgency(a).level, kUrgencyMedium);
      }
    });

    test('a bite on record raises a healthy animal to Medium', () {
      expect(assessAnimalUrgency(animal(biteRisk: 'Has bitten someone')).level, kUrgencyMedium);
    });
  });

  group('Critical', () {
    test('uncontrolled bleeding is Critical', () {
      expect(assessAnimalUrgency(animal(injury: kInjuryLifeThreatening)).level, kUrgencyCritical);
    });

    test('unresponsive/collapsed is Critical', () {
      expect(
        assessAnimalUrgency(animal(alertness: kAlertnessOptions[2], mobility: kMobilityOptions[2], behavior: const {})).level,
        kUrgencyCritical,
      );
    });

    test('severe injury corroborated by a functional sign is Critical', () {
      final r = assessAnimalUrgency(animal(injury: kInjurySevere, mobility: kMobilityOptions[1]));
      expect(r.level, kUrgencyCritical);
      expect(r.reasons.first, contains('together with'));
    });

    test('two severe signs are Critical', () {
      expect(
        assessAnimalUrgency(animal(injury: kInjuryModerate, bodyCondition: kBodyConditionOptions[3], skin: kSkinAndCoatOptions[2])).level,
        kUrgencyCritical,
      );
    });

    test('starvation: extremely underweight and refusing food is Critical', () {
      expect(
        assessAnimalUrgency(animal(bodyCondition: kBodyConditionOptions[3], appetite: kAppetiteHydrationOptions[2])).level,
        kUrgencyCritical,
      );
    });
  });

  group('contradictory or insufficient information', () {
    test('collapsed but walking normally is flagged and not Critical on that alone', () {
      final r = assessAnimalUrgency(animal(alertness: kAlertnessOptions[2]));
      expect(r.level, kUrgencyMedium);
      expect(r.conflicts, isNotEmpty);
      expect(r.needsStaffVerification, isTrue);
    });

    test('no injury but large open wounds is flagged and stays at least Medium', () {
      final r = assessAnimalUrgency(animal(skin: kSkinAndCoatOptions[2]));
      expect(r.conflicts.single, contains('no visible injury'));
      expect(r.level, kUrgencyMedium);
    });

    test('missing core answers never rate Low', () {
      final r = assessAnimalUrgency(const AnimalUrgencyInput());
      expect(r.level, kUrgencyMedium);
      expect(r.insufficientInformation, isTrue);
      expect(r.needsStaffVerification, isTrue);
    });

    test('missing answers still allow Critical on a clear red flag', () {
      expect(assessAnimalUrgency(const AnimalUrgencyInput(injury: kInjuryLifeThreatening)).level, kUrgencyCritical);
    });

    test('injury not visible in photos asks staff to verify, without changing the level', () {
      final r = assessAnimalUrgency(animal(injury: kInjuryModerate, injuryVisibleInPhotos: kInjuryPhotoOptions[1]));
      expect(r.level, kUrgencyMedium);
      expect(r.needsStaffVerification, isTrue);
    });

    test('empty report is Medium and flagged', () {
      final r = assessCaseUrgency(const []);
      expect(r.level, kUrgencyMedium);
      expect(r.insufficientInformation, isTrue);
    });
  });

  group('female questions', () {
    test('litter and suspected pregnancy are notes, never a diagnosis or a level change', () {
      final r = assessAnimalUrgency(animal(sex: 'Female', hasLitter: 'Yes', suspectedPregnancy: kSuspectedPregnancyOptions[0]));
      expect(r.level, kUrgencyLow);
      expect(r.notes, contains('Has a litter (reported)'));
      expect(r.notes.any((n) => n.contains('not vet-confirmed')), isTrue);
    });

    test('stale female answers on a male animal are ignored', () {
      final r = assessAnimalUrgency(animal(sex: 'Male', hasLitter: 'Yes', suspectedPregnancy: kSuspectedPregnancyOptions[0]));
      expect(r.notes, isEmpty);
    });
  });

  group('multi-animal and storage', () {
    test('the highest animal level wins and its reasons come first', () {
      final r = assessCaseUrgency([animal(), animal(injury: kInjuryLifeThreatening)]);
      expect(r.level, kUrgencyCritical);
      expect(r.reasons.first, startsWith('Animal 2 (Critical)'));
    });

    test('round-trips through a stored map', () {
      final r = assessAnimalUrgency(animal(injury: kInjurySevere));
      final back = UrgencyAssessment.fromMap(r.toMap())!;
      expect(back.level, r.level);
      expect(back.reasons, r.reasons);
      expect(r.toMap()['photosAnalyzed'], isFalse);
      expect(r.toMap()['method'], kUrgencyAssessmentMethod);
    });

    test('older reports without an assessment read as null', () {
      expect(UrgencyAssessment.fromMap(null), isNull);
      expect(UrgencyAssessment.fromMap({'level': 'Bogus'}), isNull);
    });

    test('reads a saved animals[] entry', () {
      final input = AnimalUrgencyInput.fromMap({
        'injury': kInjurySevere,
        'mobility': kMobilityOptions[2],
        'alertness': 'Alert/responsive',
        'bodyCondition': 'Normal',
        'behavior': ['Calm'],
      });
      expect(assessAnimalUrgency(input).level, kUrgencyCritical);
    });
  });

  group('visible signs and the medical-attention answer', () {
    test('the same injury reported twice is not counted as two severe signs', () {
      final r = assessAnimalUrgency(animal(injury: kInjurySevere, signs: {'Suspected broken bone'}));
      expect(r.level, kUrgencyMedium);
    });

    test('heavy bleeding as a visible sign is Critical', () {
      expect(assessAnimalUrgency(animal(injury: kInjuryModerate, signs: {'Active or heavy bleeding'})).level, kUrgencyCritical);
    });

    test('difficulty breathing is Critical', () {
      expect(assessAnimalUrgency(animal(signs: {'Difficulty breathing'})).level, kUrgencyCritical);
    });

    test('mild illness signs with normal condition stay Low', () {
      expect(assessAnimalUrgency(animal(signs: {'Coughing or sneezing', 'Heavy ticks or fleas'})).level, kUrgencyLow);
    });

    test('a broken bone plus a limp (another body system) is Critical', () {
      expect(
        assessAnimalUrgency(animal(injury: kInjurySevere, mobility: kMobilityOptions[1], signs: {'Suspected broken bone'})).level,
        kUrgencyCritical,
      );
    });

    test('"needs medical attention: Yes" alone is Medium, never Critical', () {
      expect(assessAnimalUrgency(animal(needsMedical: 'Yes')).level, kUrgencyMedium);
    });

    test('"no medical attention needed" contradicts a red flag and is flagged', () {
      final r = assessAnimalUrgency(animal(injury: kInjuryLifeThreatening, needsMedical: 'No'));
      expect(r.conflicts, isNotEmpty);
      expect(r.level, kUrgencyMedium);
      expect(r.needsStaffVerification, isTrue);
    });

    test('"no injury" with an injury sign is flagged', () {
      final r = assessAnimalUrgency(animal(signs: {'Open wound or deep cut'}));
      expect(r.conflicts.single, contains('injury sign'));
    });

    test('"Not sure / Not assessed" counts as missing information', () {
      final r = assessAnimalUrgency(animal(injury: kNotAssessedOption, mobility: kNotAssessedOption));
      expect(r.level, kUrgencyMedium);
      expect(r.insufficientInformation, isTrue);
    });
  });
}
