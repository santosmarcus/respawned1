import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/collartag/animal_tag_scan.dart';

void main() {
  test('reads the tag from an animal QR payload', () {
    expect(animalTagFromScan('RESPAWND-ANIMAL:AB23CD45'), 'AB23CD45');
    expect(animalTagFromScan('  RESPAWND-ANIMAL:ab23cd45 '), 'AB23CD45');
  });

  test('ignores collar tag links and malformed payloads', () {
    expect(animalTagFromScan('https://respawnd1-45021.web.app/tag/xyz'), isNull);
    expect(animalTagFromScan('RESPAWND-ANIMAL:'), isNull);
    expect(animalTagFromScan('RESPAWND-ANIMAL:../../etc'), isNull);
  });
}
