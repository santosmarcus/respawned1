import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/core/models/donation/refund_policy.dart';

void main() {
  final paid = DateTime(2026, 11, 1);
  Map<String, dynamic> donation([Map<String, dynamic> extra = const {}]) => {
    'userId': 'u',
    'type': 'donation',
    'amount': 500,
    'status': 'paid',
    'timestamp': Timestamp.fromDate(paid),
    ...extra,
  };

  test('the donor may ask while within the longest window', () {
    expect(refundRequestBlocker(donation(), uid: 'u', now: paid.add(const Duration(days: 3))), isNull);
    expect(refundRequestBlocker(donation(), uid: 'u', now: paid.add(const Duration(days: 61))), contains('60 days'));
    expect(refundRequestBlocker(donation(), uid: 'x', now: paid), contains('Only the donor'));
    expect(refundRequestBlocker(donation({'type': 'inkind'}), uid: 'u', now: paid), contains('In-kind'));
    expect(refundRequestBlocker(donation({'status': 'reversed'}), uid: 'u', now: paid), contains('already refunded'));
    expect(refundRequestBlocker(donation({'refundRequest': {}}), uid: 'u', now: paid), contains('already requested'));
    expect(refundRequestBlocker(null, uid: 'u'), isNotNull);
  });

  test('each reason has its own window', () {
    final day8 = paid.add(const Duration(days: 8));
    expect(refundReasonInTime(RefundReason.duplicate, paid, now: day8), isFalse);
    expect(refundReasonInTime(RefundReason.unauthorized, paid, now: day8), isTrue);
    expect(refundReasonInTime(RefundReason.duplicate, null), isTrue);
  });

  test('sponsorships offer the animal outcome reason, donations the closed campaign', () {
    expect(RefundReason.forType('sponsorship'), contains(RefundReason.animalOutcome));
    expect(RefundReason.forType('donation'), contains(RefundReason.campaignClosed));
    expect(RefundReason.fromKey('wrong_amount'), RefundReason.wrongAmount);
  });

  test('request status reads from the stored map', () {
    final info = RefundRequestInfo.fromMap({'status': 'failed', 'reason': 'duplicate', 'failCodes': ['x']})!;
    expect(info.isOpen, isTrue);
    expect(info.reason, RefundReason.duplicate);
    expect(info.label, 'Refund under review');
    expect(RefundRequestInfo.fromMap(null), isNull);
    expect(refundTimingFor('GCash'), contains('within a day'));
  });
}
