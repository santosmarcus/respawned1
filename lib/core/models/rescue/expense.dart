import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseCategory {
  consultation,
  medication,
  procedure,
  laboratory,
  vaccination,
  confinement,
  transport,
  foodAndSupplies,
  other;

  String get label => switch (this) {
        ExpenseCategory.consultation => 'Consultation',
        ExpenseCategory.medication => 'Medication',
        ExpenseCategory.procedure => 'Procedure',
        ExpenseCategory.laboratory => 'Laboratory',
        ExpenseCategory.vaccination => 'Vaccination',
        ExpenseCategory.confinement => 'Confinement',
        ExpenseCategory.transport => 'Transport',
        ExpenseCategory.foodAndSupplies => 'Food and Supplies',
        ExpenseCategory.other => 'Other',
      };

  static ExpenseCategory fromLabel(String? label) =>
      values.firstWhere((c) => c.label == label, orElse: () => ExpenseCategory.other);
}

/// [unfunded] intentionally is NOT "fully covered" — see
/// RescueCaseRepository.streamExpenses / the Cost Tracking totals: an
/// expense counts toward Funded Amount only when its source is anything
/// other than [unfunded]. This is the deliberately simplified MVP rule —
/// no partial-funding/multi-source allocation yet.
/// TODO(cost-tracking): support partial funding and multiple funding
/// sources allocated to a single expense; this MVP treats every non-
/// Unfunded expense as 100% covered by its one selected source.
enum FundingSource {
  unfunded,
  donationFund,
  organizationBudget,
  fundraiser,
  other;

  String get label => switch (this) {
        FundingSource.unfunded => 'Unfunded',
        FundingSource.donationFund => 'Donation Fund',
        FundingSource.organizationBudget => 'Organization Budget',
        FundingSource.fundraiser => 'Fundraiser',
        FundingSource.other => 'Other',
      };

  static FundingSource fromLabel(String? label) =>
      values.firstWhere((s) => s.label == label, orElse: () => FundingSource.unfunded);
}

/// A single doc under `cases/{caseId}/expenses/{expenseId}` — the ledger
/// entry cost tracking is built on. Totals (Total Expenses / Funded Amount
/// / Outstanding Balance) are always computed by summing these records,
/// never stored/edited as a standalone total.
class Expense {
  final String id;
  final String caseId;
  final String title;
  final ExpenseCategory category;
  final double amount;
  final FundingSource fundingSource;
  final String? receiptUrl;
  final String? notes;
  final DateTime? incurredAt;
  final DateTime? createdAt;
  final String? createdBy;

  /// Same representation and null-means-"applies to everything" convention
  /// as TreatmentLogEntry.animalIndexes (see its doc comment) — here null/
  /// empty means "Shared case expense" rather than "All Animals", but it's
  /// the identical `animals[]`-index list underneath. One expense document
  /// either way; a shared expense is never duplicated per animal, and
  /// totals are never auto-split across the listed animals.
  final List<int>? animalIndexes;

  const Expense({
    required this.id,
    required this.caseId,
    required this.title,
    required this.category,
    required this.amount,
    required this.fundingSource,
    this.receiptUrl,
    this.notes,
    this.incurredAt,
    this.createdAt,
    this.createdBy,
    this.animalIndexes,
  });

  bool get isFunded => fundingSource != FundingSource.unfunded;

  bool get isSharedCaseExpense => animalIndexes == null || animalIndexes!.isEmpty;

  bool appliesToAnimal(int animalIndex) => isSharedCaseExpense || animalIndexes!.contains(animalIndex);

  factory Expense.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String caseId) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    return Expense(
      id: doc.id,
      caseId: caseId,
      title: data['title'] as String? ?? '-',
      category: ExpenseCategory.fromLabel(data['category'] as String?),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      fundingSource: FundingSource.fromLabel(data['fundingSource'] as String?),
      receiptUrl: data['receiptUrl'] as String?,
      notes: data['notes'] as String?,
      incurredAt: ts('incurredAt'),
      createdAt: ts('createdAt'),
      createdBy: data['createdBy'] as String?,
      animalIndexes: (data['animalIndexes'] as List?)?.map((e) => (e as num).toInt()).toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'category': category.label,
        'amount': amount,
        'fundingSource': fundingSource.label,
        if (receiptUrl != null && receiptUrl!.isNotEmpty) 'receiptUrl': receiptUrl,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'incurredAt': incurredAt != null ? Timestamp.fromDate(incurredAt!) : Timestamp.now(),
        'createdBy': createdBy,
        if (animalIndexes != null && animalIndexes!.isNotEmpty) 'animalIndexes': animalIndexes,
      };
}
