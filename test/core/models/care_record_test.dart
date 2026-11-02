import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';

CareRecord _record(CareType type, DateTime given, {DateTime? nextDue}) =>
    CareRecord(id: '', animalId: 'a', type: type, dateGiven: given, nextDueDate: nextDue);

void main() {
  test('latestByType keeps the newest record of each type', () {
    final latest = CareRecord.latestByType([
      _record(CareType.deworming, DateTime(2025, 1, 1)),
      _record(CareType.deworming, DateTime(2025, 6, 1)),
      _record(CareType.fleaTick, DateTime(2025, 3, 1)),
    ]);
    expect(latest[CareType.deworming]!.dateGiven, DateTime(2025, 6, 1));
    expect(latest[CareType.fleaTick]!.dateGiven, DateTime(2025, 3, 1));
    expect(latest.containsKey(CareType.vetCheckup), isFalse);
  });

  test('status follows the next due date like vaccines', () {
    final now = DateTime.now();
    expect(_record(CareType.fleaTick, now, nextDue: now.subtract(const Duration(days: 1))).status, VaccineStatus.overdue);
    expect(_record(CareType.fleaTick, now, nextDue: now.add(const Duration(days: 5))).status, VaccineStatus.dueSoon);
    expect(_record(CareType.vetCheckup, now, nextDue: now.add(const Duration(days: 120))).status, VaccineStatus.upToDate);
    expect(_record(CareType.vetCheckup, now).status, VaccineStatus.noRecord);
  });

  test('unknown stored types fall back to a vet checkup', () {
    expect(CareType.fromName('somethingElse'), CareType.vetCheckup);
    expect(CareType.fromName('fleaTick'), CareType.fleaTick);
  });
}
