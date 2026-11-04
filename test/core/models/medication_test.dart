import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/medication.dart';

void main() {
  final plan = MedicationPlan(
    id: 'p1',
    animalId: 'a1',
    drug: 'Amoxicillin',
    dose: '250 mg',
    timesPerDay: 2,
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 3),
  );

  test('scheduled only inside the start and end dates (inclusive)', () {
    expect(plan.isScheduledOn(DateTime(2026, 10, 31)), isFalse);
    expect(plan.isScheduledOn(DateTime(2026, 11, 1, 23, 59)), isTrue);
    expect(plan.isScheduledOn(DateTime(2026, 11, 3, 8)), isTrue);
    expect(plan.isScheduledOn(DateTime(2026, 11, 4)), isFalse);
  });

  test('an inactive plan is never scheduled', () {
    final ended = MedicationPlan(
      id: 'p2',
      animalId: 'a1',
      drug: 'X',
      dose: '1',
      timesPerDay: 1,
      startDate: DateTime(2026, 11, 1),
      active: false,
    );
    expect(ended.isScheduledOn(DateTime(2026, 11, 2)), isFalse);
  });

  test('dose ids are deterministic per plan, day and slot', () {
    expect(doseIdFor('p1', DateTime(2026, 11, 2, 9), 1), 'p1_2026-11-02_1');
    expect(doseIdFor('p1', DateTime(2026, 11, 2, 21), 1), 'p1_2026-11-02_1');
    expect(doseIdFor('p1', DateTime(2026, 11, 2), 2), 'p1_2026-11-02_2');
  });

  test('a recorded slot is given; past gaps are missed; today is due', () {
    final now = DateTime(2026, 11, 2, 10);
    final doses = {
      doseIdFor('p1', DateTime(2026, 11, 1), 1): MedicationDose(
        id: doseIdFor('p1', DateTime(2026, 11, 1), 1),
        planId: 'p1',
        animalId: 'a1',
        day: DateTime(2026, 11, 1),
        slot: 1,
        givenBy: 'carer',
      ),
    };
    DoseStatus at(DateTime day, int slot) => doseStatusFor(
          planId: 'p1',
          day: day,
          slot: slot,
          doses: doses,
          now: now,
        );

    expect(at(DateTime(2026, 11, 1), 1), DoseStatus.given);
    expect(at(DateTime(2026, 11, 1), 2), DoseStatus.missed);
    expect(at(DateTime(2026, 11, 2), 1), DoseStatus.due);
    expect(at(DateTime(2026, 11, 3), 1), DoseStatus.upcoming);
  });

  test('counts missed slots across a window, skipping unscheduled days', () {
    final now = DateTime(2026, 11, 4, 12);
    final missed = countMissedDoses(
      plans: [plan],
      doses: const {},
      from: DateTime(2026, 10, 30),
      to: DateTime(2026, 11, 4),
      now: now,
    );
    // 1–3 Nov are scheduled, 2 slots each, all past or today-without-record.
    // 3 Nov is a past day by 4 Nov, so every scheduled slot is missed.
    expect(missed, 6);
  });
}
