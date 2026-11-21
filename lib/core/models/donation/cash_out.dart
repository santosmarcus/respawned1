import 'package:cloud_firestore/cloud_firestore.dart';

/// Where money was taken out from. Keep equal to SOURCES in
/// functions/cash_out_rules.js.
const Map<String, String> kCashOutSources = {
  'paymongo': 'PayMongo payout',
  'bank': 'Bank withdrawal',
  'gcash': 'GCash / e-wallet',
  'cash': 'Cash on hand',
  'other': 'Other',
};

/// One part of a cash-out assigned to a fund: a spending record
/// (campaigns/{campaignId}/allocations/{allocationId}).
class CashOutLine {
  final String campaignId;
  final String campaignTitle;
  final String category;
  final String label;
  final double amount;
  final String? byName;
  final DateTime? at;

  const CashOutLine({
    required this.campaignId,
    required this.campaignTitle,
    required this.category,
    required this.label,
    required this.amount,
    this.byName,
    this.at,
  });

  factory CashOutLine.fromMap(Map<String, dynamic> m) => CashOutLine(
        campaignId: m['campaignId'] as String? ?? '',
        campaignTitle: m['campaignTitle'] as String? ?? 'Fund',
        category: m['category'] as String? ?? '',
        label: m['label'] as String? ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        byName: m['byName'] as String?,
        at: m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : null,
      );
}

/// Money taken out of PayMongo, the bank, an e-wallet or the cash box:
/// organizations/{orgId}/cashOuts/{id}, written only by the backend
/// (functions/campaigns.js recordCashOut / assignCashOut / settleCashOut and
/// the PayMongo payout webhook). Until it is sorted out, the Donations
/// screen asks the people who manage money which fund it came from.
class CashOut {
  final String id;
  final String organizationId;

  /// A key of [kCashOutSources].
  final String source;
  final double amount;
  final double assignedAmount;

  /// needs_assignment | partly_assigned | assigned | already_recorded |
  /// returned (a PayMongo payout the bank sent back while it waited)
  final String status;

  /// PayMongo reported the bank sent this payout back (payout.returned).
  /// When some of it was already assigned, that spending needs checking.
  final bool payoutReturned;
  final String? note;
  final String? settleNote;
  final DateTime? occurredAt;
  final DateTime? createdAt;
  final String recordedByName;
  final List<CashOutLine> lines;

  const CashOut({
    required this.id,
    required this.organizationId,
    required this.source,
    required this.amount,
    required this.assignedAmount,
    required this.status,
    this.payoutReturned = false,
    this.note,
    this.settleNote,
    this.occurredAt,
    this.createdAt,
    this.recordedByName = '',
    this.lines = const [],
  });

  factory CashOut.fromMap(String id, Map<String, dynamic> d) {
    DateTime? asDate(Object? v) => v is Timestamp ? v.toDate() : null;
    return CashOut(
      id: id,
      organizationId: d['organizationId'] as String? ?? '',
      source: kCashOutSources.containsKey(d['source']) ? d['source'] as String : 'other',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      assignedAmount: (d['assignedAmount'] as num?)?.toDouble() ?? 0,
      status: d['status'] as String? ?? 'needs_assignment',
      payoutReturned: d['payoutReturned'] == true,
      note: d['note'] as String?,
      settleNote: d['settleNote'] as String?,
      occurredAt: asDate(d['occurredAt']),
      createdAt: asDate(d['createdAt']),
      recordedByName: d['recordedByName'] as String? ?? '',
      lines: [
        for (final l in (d['lines'] as List? ?? const []))
          if (l is Map) CashOutLine.fromMap(l.map((k, v) => MapEntry(k.toString(), v))),
      ],
    );
  }

  factory CashOut.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => CashOut.fromMap(doc.id, doc.data() ?? const {});

  bool get isOpen => status == 'needs_assignment' || status == 'partly_assigned';

  /// Pesos that still need a fund (rounded to centavos).
  double get remaining => ((amount - assignedAmount) * 100).round().clamp(0, 1 << 52) / 100;

  String get sourceLabel => kCashOutSources[source] ?? 'Other';

  String get statusLabel => switch (status) {
        'needs_assignment' => 'Needs a fund',
        'partly_assigned' => 'Partly assigned',
        'assigned' => 'Assigned',
        'already_recorded' => 'Already recorded',
        'returned' => 'Returned by the bank',
        _ => status,
      };
}
