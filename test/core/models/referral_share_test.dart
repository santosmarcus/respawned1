import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';

void main() {
  test('share link is open until revoked or expired', () {
    final now = DateTime(2026, 11, 18);
    final link = ReferralShareLink.fromMap({
      'url': 'https://respawnd1-45021.web.app/referral/abc',
      'includeReporter': true,
      'expiresAt': Timestamp.fromDate(DateTime(2026, 12, 18)),
    })!;
    expect(link.includeReporter, isTrue);
    expect(link.isOpen(now), isTrue);
    expect(link.isOpen(DateTime(2026, 12, 19)), isFalse);
    expect(ReferralShareLink.fromMap({'url': 'x', 'revoked': true})!.isOpen(now), isFalse);
    expect(ReferralShareLink.fromMap({'revoked': false}), isNull);
    expect(ReferralShareLink.fromMap(null), isNull);
  });

  test('answers from the page read back with their label', () {
    final r = ReferralShareResponse.fromMap({
      'response': 'cannot_handle',
      'name': 'Brgy San Isidro',
      'note': 'No vehicle',
      'at': Timestamp.fromDate(DateTime(2026, 11, 18, 9)),
    })!;
    expect(r.label, "Can't take it");
    expect(r.name, 'Brgy San Isidro');
    expect(r.note, 'No vehicle');
    expect(r.at, DateTime(2026, 11, 18, 9));
    expect(ReferralShareResponse.fromMap({'name': 'x'}), isNull);
  });
}
