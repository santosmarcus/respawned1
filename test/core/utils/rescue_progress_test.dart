import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/utils/rescue_progress.dart';

void main() {
  test('a new report has only "Case reported" done', () {
    expect(rescueProgressFinished('pending'), 1);
  });

  test('transporter sub-states stay on the transporter step until the clinic', () {
    for (final s in ['accepted', 'assigned', 'ongoing', 'arrived', 'treatment']) {
      expect(rescueProgressFinished(s), 2, reason: s);
    }
    // 'treatment' is the transporter's "picked up", not clinical care.
    expect(rescueProgressDetail('treatment'), contains('picked up'));
  });

  test('clinic, intake and completion move forward', () {
    expect(rescueProgressFinished('dropoff'), 3);
    expect(rescueProgressFinished('in_treatment'), 3);
    expect(rescueProgressFinished('intake'), 4);
    expect(rescueProgressFinished('completed'), kRescueProgressSteps.length);
  });

  test('off-path statuses have no step', () {
    for (final s in ['rejected', 'referred', 'cancelled', 'unable_to_locate', null]) {
      expect(rescueProgressFinished(s), isNull, reason: '$s');
    }
  });
}
