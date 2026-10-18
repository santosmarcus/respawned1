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
}
