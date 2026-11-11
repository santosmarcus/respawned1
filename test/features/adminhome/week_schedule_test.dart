import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/week_schedule.dart';

final _now = DateTime(2026, 11, 12, 9);

VaccinationRecord _vax(String name, DateTime given, DateTime nextDue) => VaccinationRecord(
      id: '$name$given',
      animalId: 'a1',
      vaccineName: name,
      species: 'Dog',
      dateAdministered: given,
      validityDurationDays: 365,
      nextDueDate: nextDue,
    );

VolunteerEvent _event(String id, DateTime start, {String status = VolunteerEvent.statusPublished}) => VolunteerEvent(
      id: id,
      organizationId: 'org',
      title: 'Event $id',
      description: '',
      location: 'Shelter',
      addressFull: '',
      organizerName: 'Org',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      capacity: 10,
      goingCount: 4,
      status: status,
    );

void main() {
  final mochi = AnimalRecord.fromMap('a1', {'name': 'Mochi', 'species': 'Dog'});

  test('only items dated today through the next 6 days are included', () {
    final items = buildWeekSchedule(
      now: _now,
      events: [
        _event('today', DateTime(2026, 11, 12, 15)),
        _event('day7', DateTime(2026, 11, 19, 10)), // one day past the window
        _event('cancelled', DateTime(2026, 11, 13, 10), status: VolunteerEvent.statusCancelled),
      ],
      animals: [mochi],
      care: {
        'a1': [CareRecord(id: 'c', animalId: 'a1', type: CareType.fleaTick, dateGiven: DateTime(2026, 10, 18), nextDueDate: DateTime(2026, 11, 18))],
      },
    );
    expect(items.map((i) => i.title), ['Event today', 'Flea & Tick due · Mochi']);
  });

  test('only the latest dose of each vaccine counts', () {
    final items = buildWeekSchedule(
      now: _now,
      animals: [mochi],
      vaccinations: {
        'a1': [
          // Older dose was due this week, but a newer dose replaced it.
          _vax('Rabies', DateTime(2025, 11, 14), DateTime(2026, 11, 14)),
          _vax('Rabies', DateTime(2026, 11, 1), DateTime(2027, 11, 1)),
          _vax('DHPP', DateTime(2025, 11, 15), DateTime(2026, 11, 15)),
        ],
      },
    );
    expect(items, hasLength(1));
    expect(items.single.subtitle, 'DHPP');
    expect(items.single.day, DateTime(2026, 11, 15));
  });

  test('items sort by day, then events before animal care', () {
    final items = buildWeekSchedule(
      now: _now,
      animals: [mochi],
      vaccinations: {
        'a1': [_vax('DHPP', DateTime(2025, 11, 13), DateTime(2026, 11, 13))],
      },
      events: [
        _event('later', DateTime(2026, 11, 16, 9)),
        _event('sameDay', DateTime(2026, 11, 13, 18)),
      ],
    );
    expect(items.map((i) => i.kind), [ScheduleKind.event, ScheduleKind.vaccine, ScheduleKind.event]);
    expect(items.first.title, 'Event sameDay');
  });

  test('day headings name today and tomorrow', () {
    expect(dayHeading(DateTime(2026, 11, 12), _now), 'Today · Nov 12');
    expect(dayHeading(DateTime(2026, 11, 13), _now), 'Tomorrow · Nov 13');
    expect(dayHeading(DateTime(2026, 11, 16), _now), 'Mon · Nov 16');
  });

  test('urgent count leaves out critical cases that are already moving', () {
    RescueCase c(String id, String urgency) => RescueCase.fromMap(id, {'urgency': urgency});
    final snap = RescueSnapshot({
      RescueStage.review: [c('r1', 'Critical'), c('r2', 'Low')],
      RescueStage.transporter: [c('t1', 'Critical')],
      RescueStage.transit: [c('m1', 'Critical')],
      RescueStage.treatment: [c('v1', 'Critical')],
      RescueStage.fieldIssue: [c('f1', 'Critical')],
    });
    expect(snap.urgentWaiting.map((c) => c.id), unorderedEquals(['r1', 't1', 'f1']));
    expect(urgentTabFor(const []), RescuePipelineTab.review);
  });
}
