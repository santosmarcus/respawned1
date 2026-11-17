import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/adoption/adoption_no_show_rules.dart';

void main() {
  test('the first missed interview allows one rebooking', () {
    expect(noShowOutcome(previousNoShows: 0), NoShowOutcome.rebook);
  });

  test('the second missed interview closes the application', () {
    expect(noShowOutcome(previousNoShows: 1), NoShowOutcome.close);
    expect(noShowOutcome(previousNoShows: 2), NoShowOutcome.close);
  });

  test('counts no-shows, treating an older single noShowAt as one', () {
    expect(noShowCountOf(const {}), 0);
    expect(noShowCountOf(const {'noShowAt': 'x'}), 1);
    expect(noShowCountOf(const {'noShowCount': 2, 'noShowAt': 'x'}), 2);
  });
}
