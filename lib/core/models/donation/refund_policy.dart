import 'package:cloud_firestore/cloud_firestore.dart';

/// The refund policy for donations and sponsorships, shown to the donor
/// before every payment and again before a refund request. Keep the
/// version, days and reasons equal to functions/refund_rules.js and the
/// donorRefundRequest rule in firestore.rules.

/// Change whenever the terms below change.
const String kRefundTermsVersion = '2026-11-18';

/// Days after paying in which a donor may ask for a refund.
const int kRefundRequestDays = 7;

/// An unauthorized payment may be reported for longer.
const int kUnauthorizedRefundDays = 60;

enum RefundReason {
  duplicate('duplicate', 'I was charged twice',
      'The same amount was paid more than once for the same campaign.'),
  wrongAmount('wrong_amount', 'I entered the wrong amount',
      'The amount paid is not what I meant to give.'),
  unauthorized('unauthorized', 'I did not make this payment',
      'Someone paid with my account or card without my permission.'),
  campaignClosed('campaign_closed', 'The campaign closed before my money was used',
      'The campaign was closed or cancelled and my donation was not spent.'),
  animalOutcome('animal_outcome', 'The sponsored animal was adopted, transferred or passed away',
      'The animal I sponsor no longer needs this sponsorship.');

  const RefundReason(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;

  static RefundReason? fromKey(String? k) {
    for (final r in values) {
      if (r.key == k) return r;
    }
    return null;
  }

  int get requestDays => this == RefundReason.unauthorized ? kUnauthorizedRefundDays : kRefundRequestDays;

  /// Reasons a donor can pick for this kind of record.
  static List<RefundReason> forType(String type) => [
    RefundReason.duplicate,
    RefundReason.wrongAmount,
    RefundReason.unauthorized,
    type == 'sponsorship' ? RefundReason.animalOutcome : RefundReason.campaignClosed,
  ];
}

/// The policy in short, shown before paying.
const List<String> kRefundPolicyPoints = [
  'Donations and sponsorships are non-refundable once they are used for the animals\' care.',
  'A refund can be requested only for: a duplicate payment, a wrong amount, a payment you did not make, '
      'a campaign that closed before your money was used, or (for sponsorships) an animal that was adopted, '
      'transferred or passed away.',
  'Requests must be made within $kRefundRequestDays days of payment ($kUnauthorizedRefundDays days for a payment '
      'you did not make), from History.',
  'Money already spent on the animals cannot be refunded.',
  'Changing your mind is not a reason for a refund. To stop a sponsorship, use Cancel Sponsorship: it simply '
      'won\'t continue after its end date.',
  'Approved refunds are for the full amount you paid. The organization covers the payment fees.',
];

/// What happens after a request, step by step.
const List<String> kRefundProcedure = [
  'You send the request with its reason. It can be sent only once for each payment.',
  'The organization\'s financial administrator reviews it, usually within 5 working days.',
  'If approved, the refund goes back to the method you paid with through PayMongo. If PayMongo cannot refund it '
      '(for example, the payment is too old), the organization pays you back by GCash or bank transfer and tells '
      'you the reference number.',
  'If declined, you are told why.',
  'Once refunded, your Certificate of Donation is no longer valid and the campaign\'s total goes down.',
];

/// Terms the donor accepts with the request.
const List<String> kRefundTerms = [
  'The information I give is true. A false request may be declined and reported.',
  'If approved, the refund is the full amount I paid, returned to my original payment method when possible.',
  'Refunds can take time to reach me: GCash and GrabPay usually within a day, Maya a few days, cards up to 30 '
      'days, bank transfers 3 to 5 banking days.',
  'My Certificate of Donation for this payment will be voided.',
  'For a sponsorship, the sponsorship ends when the refund is approved.',
];

/// How long the money usually takes to arrive, by payment method label.
String refundTimingFor(String method) {
  final m = method.toLowerCase();
  if (m.contains('gcash') || m.contains('grab')) return 'GCash and GrabPay refunds usually arrive within a day.';
  if (m.contains('maya')) return 'Maya refunds usually arrive within a few days.';
  if (m.contains('card')) return 'Card refunds can take up to 30 days to appear on your statement.';
  if (m.contains('qr')) return 'QR Ph payments are refunded by the organization directly (GCash or bank transfer).';
  return 'The organization will tell you how and when the refund is sent.';
}

/// Why the donor can't ask for a refund for this record now, or null when
/// they can. [data] is `donations/{id}`.
String? refundRequestBlocker(Map<String, dynamic>? data, {required String? uid, DateTime? now}) {
  if (data == null) return 'This donation could not be found.';
  if (uid == null || data['userId'] != uid) return 'Only the donor can ask for a refund.';
  if (data['type'] == 'inkind') return 'In-kind pledges are cancelled, not refunded.';
  if (data['status'] == 'reversed') return 'This payment was already refunded.';
  if (data['refundRequest'] != null) return 'A refund was already requested for this payment.';
  final amount = data['amount'];
  if (amount is! num || amount <= 0) return 'This record has no amount to refund.';
  final paid = data['timestamp'] is Timestamp ? (data['timestamp'] as Timestamp).toDate() : null;
  if (paid == null) return null;
  final t = now ?? DateTime.now();
  // The longest window (unauthorized); the reason picker narrows it.
  if (t.isAfter(paid.add(const Duration(days: kUnauthorizedRefundDays)))) {
    return 'Refunds can only be requested within $kUnauthorizedRefundDays days of payment.';
  }
  return null;
}

/// Whether [reason] is still within its own window for a payment made at
/// [paidAt].
bool refundReasonInTime(RefundReason reason, DateTime? paidAt, {DateTime? now}) {
  if (paidAt == null) return true;
  return !(now ?? DateTime.now()).isAfter(paidAt.add(Duration(days: reason.requestDays)));
}

/// `donations/{id}.refundRequest` as the donor and staff see it.
class RefundRequestInfo {
  final String status; // requested | processing | failed | refunded | declined
  final RefundReason? reason;
  final String details;
  final DateTime? requestedAt;
  final String? declineReason;
  final String? method; // paymongo | manual
  final String? manualReference;
  final String? paymongoRefundId;
  final List<String> failCodes;

  const RefundRequestInfo({
    required this.status,
    this.reason,
    this.details = '',
    this.requestedAt,
    this.declineReason,
    this.method,
    this.manualReference,
    this.paymongoRefundId,
    this.failCodes = const [],
  });

  static RefundRequestInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return RefundRequestInfo(
      status: raw['status'] as String? ?? 'requested',
      reason: RefundReason.fromKey(raw['reason'] as String?),
      details: raw['details'] as String? ?? '',
      requestedAt: ts(raw['requestedAt']),
      declineReason: raw['declineReason'] as String?,
      method: raw['method'] as String?,
      manualReference: raw['manualReference'] as String?,
      paymongoRefundId: raw['paymongoRefundId'] as String?,
      failCodes: (raw['failCodes'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// Waiting for the organization (a failed PayMongo refund is still open).
  bool get isOpen => status == 'requested' || status == 'failed';

  String get label => switch (status) {
    'requested' => 'Refund requested',
    'processing' => 'Refund being processed',
    'failed' => 'Refund under review',
    'refunded' => 'Refunded',
    'declined' => 'Refund declined',
    _ => status,
  };
}
