import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_application.dart';

void main() {
  VolunteerApplication app({String name = 'Ria', String phone = '09171234567', Set<VolunteerCategory>? cats, String availability = 'Weekends'}) =>
      VolunteerApplication(
        uid: 'u1',
        name: name,
        phone: phone,
        categories: cats ?? {VolunteerCategory.event},
        availability: availability,
        serviceArea: '',
        experience: '',
      );

  test('a complete application has no problems', () {
    expect(app().validate(), isEmpty);
  });

  test('flags missing name, phone, category and availability', () {
    expect(app(name: ' ').validate(), contains('Enter your name.'));
    expect(app(phone: '12').validate(), contains('Enter a phone number.'));
    expect(app(cats: {}).validate(), contains('Pick at least one way to help.'));
    expect(app(availability: '').validate(), contains('Say when you are available.'));
  });

  test('a submission always goes back to pending', () {
    final m = app(cats: {VolunteerCategory.rescue, VolunteerCategory.carer}).toSubmission();
    expect(m['status'], 'pending');
    expect(m['categories'], containsAll(['rescue', 'carer']));
    expect(m.containsKey('reviewedBy'), isFalse);
  });
}
