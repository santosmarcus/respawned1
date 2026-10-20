import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-side models for the donation module. Listings themselves use the
/// general view's [DonationListing] (lib/features/donation/models.dart) so
/// both views parse the same `campaigns` documents one way.

/// Option lists — must match the constants in functions/campaigns.js.
const List<String> kPurposeTags = ['Rescue', 'Medicine & Treatment', 'Food and Supplies', 'Shelter', 'General Operations'];
const List<String> kAllocationCategories = [
  'Food',
  'Medicine and Treatment',
  'Administrative',
  'Bills and Utilities',
  'Shelter',
  'Transport',
  'Other',
];
const List<String> kInKindCategories = [
  'Food & Water',
  'Medicine & Treatment',
  'Supplies & Equipment',
  'Hygiene & Cleaning',
  'Transport Crates',
  'Others',
];
const Map<String, String> kFundKinds = {
  'campaign': 'A specific campaign',
  'animal': 'A specific animal',
  'medical': 'A medical expense',
  'shelter_resource': 'Shelter resources',
  'general': 'General operational funds',
};
const Map<String, String> kOfflineMethods = {
  'bank_transfer': 'Bank Transfer',
  'cash': 'Cash',
  'check': 'Check',
  'other': 'Other',
};

String campaignStatusLabel(String status) => switch (status) {
  'draft' => 'Draft',
  'active' => 'Active',
  'paused' => 'Deactivated',
  'goal_met' => 'Goal Met',
  'goal_not_met' => 'Goal Not Met',
  'closed' => 'Closed',
  'archived' => 'Archived',
  _ => status,
};

/// One record in `donations/` as the admin lists show it — monetary
/// (PayMongo or manual), sponsorship, or in-kind pledge. Austin's
/// DonationHistoryRecord, plus the fields the backend now writes.
class DonationHistoryRecord {
  final String id;
  final double amountValue;
  final String amountString;
  final String campaignId;
  final String campaignName;
  final DateTime? createdAt;
  final DateTime? timestamp;
  final String date;
  final String donorName;
  final bool isAnonymous;
  final String itemDescription;
  final String method;
  final String organizer;
  final String refNumber;
  final DateTime? nextChargeDate;
  final String type; // 'donation' | 'sponsorship' | 'inkind'
  final String? userId;
  final String status;
  final String sponsorshipStatus;
  final String category;
  final String clarification;
  final String address;
  final String source; // 'paymongo' (default) | 'manual'
  final String? recordedByName;
  final String? paymentId;
  final int? quantityReceived;

  const DonationHistoryRecord({
    required this.id,
    required this.amountValue,
    required this.amountString,
    required this.campaignId,
    required this.campaignName,
    this.createdAt,
    this.timestamp,
    required this.date,
    required this.donorName,
    required this.isAnonymous,
    required this.itemDescription,
    required this.method,
    required this.organizer,
    required this.refNumber,
    this.nextChargeDate,
    required this.type,
    this.userId,
    this.status = '',
    this.sponsorshipStatus = '',
    this.category = '',
    this.clarification = '',
    this.address = '',
    this.source = 'paymongo',
    this.recordedByName,
    this.paymentId,
    this.quantityReceived,
  });

  String get displayName => isAnonymous ? 'Anonymous' : (donorName.isEmpty ? 'Donor' : donorName);
  bool get isInKind => type == 'inkind';
  bool get isManual => source == 'manual';
  bool get isPendingInKind {
    final s = status.toLowerCase();
    return isInKind && (s == 'inprogress' || s == 'pending' || s.isEmpty);
  }

  bool get isCompletedInKind {
    final s = status.toLowerCase();
    return isInKind && (s == 'complete' || s == 'completed');
  }

  DateTime? get when => timestamp ?? createdAt;

  factory DonationHistoryRecord.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    DateTime? ts(String key) => data[key] is Timestamp ? (data[key] as Timestamp).toDate() : null;
    return DonationHistoryRecord(
      id: doc.id,
      amountValue: (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0,
      amountString: data['amountString'] as String? ?? '',
      campaignId: data['campaignId'] as String? ?? '',
      campaignName: data['campaignName'] as String? ?? '',
      createdAt: ts('createdAt'),
      timestamp: ts('timestamp'),
      date: data['date'] as String? ?? '',
      donorName: data['donorName'] as String? ?? '',
      isAnonymous: data['isAnonymous'] == true,
      itemDescription: data['itemDescription'] as String? ?? '',
      method: data['method'] as String? ?? data['donationMethod'] as String? ?? '',
      organizer: data['organizer'] as String? ?? '',
      refNumber: data['refNumber'] as String? ?? '',
      nextChargeDate: ts('nextChargeDate'),
      type: data['type'] as String? ?? 'donation',
      userId: data['userId'] as String?,
      status: data['status'] as String? ?? '',
      sponsorshipStatus: data['sponsorshipStatus'] as String? ?? '',
      category: data['category'] as String? ?? '',
      clarification: data['clarification'] as String? ?? '',
      address: data['address'] as String? ?? '',
      source: data['source'] as String? ?? 'paymongo',
      recordedByName: data['recordedByName'] as String?,
      paymentId: data['paymentId'] as String?,
      quantityReceived: (data['quantityReceived'] is num) ? (data['quantityReceived'] as num).toInt() : null,
    );
  }
}

/// `campaigns/{id}/allocations/{id}` — the same docs donation_detail.dart's
/// Fund Tracking reads (label, category, amount, date). Legacy docs may
/// store amount as a string; it is parsed leniently.
class AllocationEntry {
  final String id;
  final String kind; // 'expense' | 'transfer_out'
  final String label;
  final String category;
  final double amount;
  final String date;
  final String? notes;
  final String? receiptUrl;
  final String? recordedByName;
  final String? inKindDescription;
  final DateTime? createdAt;

  const AllocationEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
    this.receiptUrl,
    this.recordedByName,
    this.inKindDescription,
    this.createdAt,
  });

  bool get isTransfer => kind == 'transfer_out';

  factory AllocationEntry.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final rawAmount = data['amount'];
    double amount = 0;
    if (rawAmount is num) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      amount = double.tryParse(rawAmount.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    }
    return AllocationEntry(
      id: doc.id,
      kind: data['kind'] as String? ?? 'expense',
      label: data['label'] as String? ?? data['title'] as String? ?? 'Expense',
      category: data['category'] as String? ?? 'General',
      amount: amount,
      date: data['date'] as String? ?? '',
      notes: data['notes'] as String?,
      receiptUrl: data['receiptUrl'] as String? ?? data['imageUrl'] as String?,
      recordedByName: data['recordedByName'] as String?,
      inKindDescription: data['inKindDescription'] as String?,
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

/// `campaigns/{id}/history/{id}` — admin-only audit trail written by the backend.
class CampaignHistoryEntry {
  final String id;
  final String type;
  final String byName;
  final DateTime? at;
  final String? reason;
  final DateTime? previousDeadline;
  final DateTime? newDeadline;
  final double? amount;

  const CampaignHistoryEntry({
    required this.id,
    required this.type,
    required this.byName,
    this.at,
    this.reason,
    this.previousDeadline,
    this.newDeadline,
    this.amount,
  });

  String get label => switch (type) {
    'created' => 'Listing created',
    'edited' => 'Details edited',
    'publish' => 'Published',
    'deactivate' => 'Deactivated',
    'reactivate' => 'Reactivated',
    'close' => 'Closed',
    'archive' => 'Archived (all funds allocated)',
    'goal_completed' => 'Goal reached — donations closed',
    'deadline_reached' => 'Deadline reached',
    'extended' => 'Deadline extended',
    'relaunched' => 'Relaunched',
    'extension_declined' => 'Extension declined — closed',
    'converted_to_general' => 'Converted to general fund',
    'offline_donation_recorded' => 'Offline donation recorded',
    'allocation_recorded' => 'Funds allocated',
    'excess_transferred_out' => 'Excess transferred out',
    'excess_transferred_in' => 'Excess received (transfer)',
    'inkind_received' => 'In-kind donation received',
    'inkind_cancelled' => 'In-kind pledge cancelled',
    _ => type,
  };

  factory CampaignHistoryEntry.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    DateTime? ts(String key) => data[key] is Timestamp ? (data[key] as Timestamp).toDate() : null;
    return CampaignHistoryEntry(
      id: doc.id,
      type: data['type'] as String? ?? '',
      byName: data['byName'] as String? ?? '',
      at: ts('at'),
      reason: data['reason'] as String?,
      previousDeadline: ts('previousDeadline'),
      newDeadline: ts('newDeadline'),
      amount: (data['amount'] is num) ? (data['amount'] as num).toDouble() : null,
    );
  }
}

/// `donationPayments/{id}` — PayMongo checkout attempts (finance admins only).
class PaymentAttempt {
  final String id;
  final String status; // creating | pending | paid | needs_review | expired | cancelled | error
  final String campaignName;
  final double amount;
  final String methodLabel;
  final String? refNumber;
  final DateTime? createdAt;

  const PaymentAttempt({
    required this.id,
    required this.status,
    required this.campaignName,
    required this.amount,
    required this.methodLabel,
    this.refNumber,
    this.createdAt,
  });

  factory PaymentAttempt.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return PaymentAttempt(
      id: doc.id,
      status: data['status'] as String? ?? '',
      campaignName: data['campaignName'] as String? ?? '',
      amount: (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0,
      methodLabel: data['paymentMethodLabel'] as String? ?? '',
      refNumber: data['refNumber'] as String?,
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

// ---- Formatting (no intl dependency is declared; see core/utils/currency.dart) ----

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String formatLongDate(DateTime? d) => d == null ? 'N/A' : '${_months[d.month - 1]} ${d.day}, ${d.year}';

String formatShortDate(DateTime? d) =>
    d == null ? 'mm/dd/yyyy' : '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

/// ₱ with thousands separators and centavos only when present: ₱2,000 / ₱2,000.50.
String formatPesoExact(num amount) {
  final cents = (amount * 100).round();
  final whole = (cents.abs() ~/ 100).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  final frac = cents.abs() % 100;
  return '${cents < 0 ? '-' : ''}₱$whole${frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}'}';
}
