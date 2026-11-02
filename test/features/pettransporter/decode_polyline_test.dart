import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';

void main() {
  test('decodePolyline decodes Google\'s reference example', () {
    // Example from Google's Encoded Polyline Algorithm documentation.
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    expect(points[0].latitude, closeTo(38.5, 1e-9));
    expect(points[0].longitude, closeTo(-120.2, 1e-9));
    expect(points[1].latitude, closeTo(40.7, 1e-9));
    expect(points[1].longitude, closeTo(-120.95, 1e-9));
    expect(points[2].latitude, closeTo(43.252, 1e-9));
    expect(points[2].longitude, closeTo(-126.453, 1e-9));
  });

  test('decodePolyline returns no points for an empty string', () {
    expect(decodePolyline(''), isEmpty);
  });
}
