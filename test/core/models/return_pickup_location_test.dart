import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';

void main() {
  final application = {
    'personal': {'homeAddress': '12 Mabini St, Manila', 'homeLat': 14.6, 'homeLng': 120.98},
  };
  ReturnRequest req(Map<String, dynamic> extra) =>
      ReturnRequest.fromMap({'reason': 'Allergies', 'urgency': 'Within 1 Week', 'explanation': 'x', ...extra})!;

  test('the home pin on the application when nothing else is pinned', () {
    final p = returnPickupLocation(application, null)!;
    expect([p.lat, p.lng, p.address], [14.6, 120.98, '12 Mabini St, Manila']);
  });

  test("the adopter's return pin wins over the application", () {
    final p = returnPickupLocation(application, req({'returnAddress': 'Office', 'returnLat': 14.5, 'returnLng': 121.0}))!;
    expect([p.lat, p.lng, p.address], [14.5, 121.0, 'Office']);
  });

  test('the scheduled retrieval pin wins over both', () {
    final p = returnPickupLocation(
      application,
      req({'returnLat': 14.5, 'returnLng': 121.0, 'retrievalAddress': 'Gate 2', 'retrievalLat': 14.4, 'retrievalLng': 121.1}),
    )!;
    expect([p.lat, p.lng, p.address], [14.4, 121.1, 'Gate 2']);
  });

  test('nothing pinned anywhere: null, so the shelter is used', () {
    expect(returnPickupLocation({'personal': {'homeAddress': 'Somewhere'}}, req({'returnAddress': 'Somewhere'})), isNull);
    expect(returnPickupLocation(const {}, null), isNull);
  });
}
