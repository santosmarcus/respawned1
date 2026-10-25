import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_formatting.dart';
import 'package:respawnd1/features/adoption/adoption_step.dart';

void main() {
  test('AdoptionStep keeps the workflow order', () {
    expect(AdoptionStep.values, [
      AdoptionStep.intro,
      AdoptionStep.bookAppointment,
      AdoptionStep.appReview,
      AdoptionStep.timeToMeet,
      AdoptionStep.adoptionDay,
      AdoptionStep.appReject,
      AdoptionStep.withdrawn,
    ]);
    expect(kAdoptionStepLabels.length, 5);
  });

  test('formatAdoptionDate / formatAdoptionTime', () {
    expect(formatAdoptionDate(DateTime(2026, 1, 5)), 'January 5, 2026');
    expect(formatAdoptionTime(DateTime(2026, 1, 5, 0, 5)), '12:05 AM');
    expect(formatAdoptionTime(DateTime(2026, 1, 5, 12, 0)), '12:00 PM');
    expect(formatAdoptionTime(DateTime(2026, 1, 5, 15, 30)), '3:30 PM');
  });

  test('AdoptionFormController has no slots until a date is picked', () {
    final form = AdoptionFormController();
    addTearDown(form.dispose);
    expect(form.slotsForDate, isEmpty);
    expect(form.appointmentType, 'On-site Visit');
  });

  group('adoptionStepForStatus', () {
    AdoptionStep step(String? status, {bool hasAppointment = false}) =>
        adoptionStepForStatus(status, hasAppointment: hasAppointment);

    test('pending resumes on booking until an appointment exists', () {
      expect(step('pending'), AdoptionStep.bookAppointment);
      expect(step('pending', hasAppointment: true), AdoptionStep.appReview);
      expect(step('pending_appointment'), AdoptionStep.bookAppointment);
    });

    test('canonical and legacy statuses map to the same steps', () {
      expect(step('interview'), AdoptionStep.appReview);
      expect(step('under_review'), AdoptionStep.appReview);
      expect(step('approved'), AdoptionStep.timeToMeet);
      expect(step('appointment_confirmed'), AdoptionStep.timeToMeet);
      for (final s in [
        'adopted',
        'completed',
        'return_requested',
        'return_approved',
      ]) {
        expect(step(s), AdoptionStep.adoptionDay, reason: s);
        expect(kAdoptionReleasedStatuses, contains(s));
      }
      expect(step('rejected'), AdoptionStep.appReject);
      expect(step('withdrawn'), AdoptionStep.withdrawn);
    });

    test('unknown or missing status starts from the intro', () {
      expect(step(null), AdoptionStep.intro);
      expect(step('something_else'), AdoptionStep.intro);
    });
  });

  group('resolveAdoptionStep', () {
    final now = DateTime(2026, 10, 25, 12);

    test('holds on Time to Meet until the scheduled release arrives', () {
      expect(
        resolveAdoptionStep(
          'adopted',
          hasAppointment: true,
          scheduledReleaseDate: now.add(const Duration(hours: 1)),
          now: now,
        ),
        AdoptionStep.timeToMeet,
      );
      expect(
        resolveAdoptionStep(
          'adopted',
          hasAppointment: true,
          scheduledReleaseDate: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        AdoptionStep.adoptionDay,
      );
      expect(
        resolveAdoptionStep('adopted', hasAppointment: true, now: now),
        AdoptionStep.adoptionDay,
      );
    });

    test('a future release date never changes other steps', () {
      expect(
        resolveAdoptionStep(
          'approved',
          hasAppointment: true,
          scheduledReleaseDate: now.add(const Duration(days: 1)),
          now: now,
        ),
        AdoptionStep.timeToMeet,
      );
    });
  });

  test('tracker index keeps rejected and withdrawn on review', () {
    expect(kAdoptionTrackerSteps, hasLength(kAdoptionStepLabels.length));
    for (var i = 0; i < kAdoptionTrackerSteps.length; i++) {
      expect(adoptionTrackerIndex(kAdoptionTrackerSteps[i]), i);
    }
    expect(adoptionTrackerIndex(AdoptionStep.appReject), 2);
    expect(adoptionTrackerIndex(AdoptionStep.withdrawn), 2);
  });

  group('AdoptionFormController', () {
    test('lists unanswered radio questions and agreements', () {
      final form = AdoptionFormController();
      addTearDown(form.dispose);
      expect(form.missingRequiredAnswers(), hasLength(7));
      expect(form.allAgreementsAccepted, isFalse);

      form
        ..residenceType = 'House'
        ..ownershipStatus = 'Owned'
        ..petsVaccinated = 'Yes'
        ..petsSpayedNeutered = 'Yes'
        ..hoursAlone = '0-4'
        ..primaryCaregiver = 'Me'
        ..petStayLocation = 'Indoors'
        ..agreeCare = true
        ..agreeNoAbandon = true
        ..agreeFollowup = true
        ..agreeAccurate = true
        ..agreeNotGuaranteed = true;
      expect(form.missingRequiredAnswers(), isEmpty);
      expect(form.allAgreementsAccepted, isTrue);
    });

    test('applySavedApplication restores answers from the doc', () {
      final form = AdoptionFormController();
      addTearDown(form.dispose);
      form.applySavedApplication({
        'personal': {'adopterName': 'Ana', 'adopterCity': 'Manila'},
        'household': {'residenceType': 'Condo', 'householdMembers': 3},
        'petExperience': {
          'hadPetsBefore': true,
          'currentPets': {'dogs': 2},
        },
        'lifestyle': {
          'primaryCaregiver': 'Some freeform text',
          'canAfford': {'food': true},
        },
        'uploads': {'homePhotos': 'https://example.com/a.jpg'},
        'agreement': {'care': true, 'reason': 'Love dogs'},
        'appointmentDate': Timestamp.fromDate(DateTime(2026, 11, 2)),
        'appointmentTime': '10:00 AM',
      });
      expect(form.nameCtrl.text, 'Ana');
      expect(form.homeAddressCtrl.text, 'Manila');
      expect(form.residenceType, 'Condo');
      expect(form.householdMembers, 3);
      expect(form.hadPetsBefore, isTrue);
      expect(form.currentDogs, 2);
      expect(form.currentCats, 0);
      // Legacy freeform caregiver answers aren't preselected.
      expect(form.primaryCaregiver, isNull);
      expect(form.canAffordFood, isTrue);
      expect(form.existingHomePhotoUrls, ['https://example.com/a.jpg']);
      expect(form.agreeCare, isTrue);
      expect(form.reasonCtrl.text, 'Love dogs');
      expect(form.appointmentDate, DateTime(2026, 11, 2));
      expect(form.appointmentType, 'On-site Visit');
      expect(form.appointmentTime, '10:00 AM');
    });

    test('reset clears answers but keeps contact details', () {
      final form = AdoptionFormController();
      addTearDown(form.dispose);
      form
        ..nameCtrl.text = 'Ana'
        ..residenceType = 'House'
        ..currentDogs = 2
        ..agreeCare = true
        ..existingHomePhotoUrls = ['x']
        ..appointmentType = 'Video Call';
      form.reasonCtrl.text = 'Because';
      form.reset();
      expect(form.nameCtrl.text, 'Ana');
      expect(form.residenceType, isNull);
      expect(form.currentDogs, 0);
      expect(form.agreeCare, isFalse);
      expect(form.existingHomePhotoUrls, isEmpty);
      expect(form.reasonCtrl.text, isEmpty);
      expect(form.appointmentType, 'On-site Visit');
    });
  });
}
