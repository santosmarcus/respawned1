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

/// Where money for an expense came from. [unfunded] is never stored as an
/// [ExpenseFunding] line — an expense with no lines is unfunded — it only
/// survives as the legacy single-source value and as a display label.
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

  /// Sources an [ExpenseFunding] line can use.
  static List<FundingSource> get fundable => values.where((s) => s != FundingSource.unfunded).toList();
}

/// One slice of an expense's cost covered by one source — e.g. the clinic
/// bill paid ₱3,000 from the organization budget up front and ₱2,000 from a
/// fundraiser later. An expense can have several; whatever they don't cover
/// is its outstanding balance.
class ExpenseFunding {
  final FundingSource source;
  final double amount;
  const ExpenseFunding({required this.source, required this.amount});

  static ExpenseFunding? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final source = FundingSource.fromLabel(raw['source'] as String?);
    final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
    if (source == FundingSource.unfunded || amount <= 0) return null;
    return ExpenseFunding(source: source, amount: amount);
  }

  Map<String, dynamic> toMap() => {'source': source.label, 'amount': amount};
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

  /// How the cost is covered; empty = unfunded. Lines may add up to less
  /// than [amount] (partly funded), never more (enforced on save).
  final List<ExpenseFunding> fundings;
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
    this.fundings = const [],
    this.receiptUrl,
    this.notes,
    this.incurredAt,
    this.createdAt,
    this.createdBy,
    this.animalIndexes,
  });

  /// Covered so far — capped at [amount] so a bad legacy record can never
  /// make the case totals show a negative balance.
  double get fundedAmount {
    final total = fundings.fold<double>(0, (acc, f) => acc + f.amount);
    return total > amount ? amount : total;
  }

  double get outstandingAmount => amount - fundedAmount;

  bool get isFullyFunded => amount > 0 && outstandingAmount <= 0;

  bool get isPartlyFunded => fundedAmount > 0 && !isFullyFunded;

  bool get isUnfunded => fundedAmount <= 0;

  /// e.g. "Unfunded", "Donation Fund", "Organization Budget + Fundraiser".
  String get fundingLabel => fundings.isEmpty
      ? FundingSource.unfunded.label
      : fundings.map((f) => f.source.label).toSet().join(' + ');

  bool get isSharedCaseExpense => animalIndexes == null || animalIndexes!.isEmpty;

  bool appliesToAnimal(int animalIndex) => isSharedCaseExpense || animalIndexes!.contains(animalIndex);

  factory Expense.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String caseId) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    return Expense(
      id: doc.id,
      caseId: caseId,
      title: data['title'] as String? ?? '-',
      category: ExpenseCategory.fromLabel(data['category'] as String?),
      amount: amount,
      fundings: fundingsFromFirestore(data, amount),
      receiptUrl: data['receiptUrl'] as String?,
      notes: data['notes'] as String?,
      incurredAt: ts('incurredAt'),
      createdAt: ts('createdAt'),
      createdBy: data['createdBy'] as String?,
      animalIndexes: (data['animalIndexes'] as List?)?.map((e) => (e as num).toInt()).toList(),
    );
  }

  /// `fundings` when present; otherwise a legacy single `fundingSource`,
  /// which covered the whole amount unless it was Unfunded.
  static List<ExpenseFunding> fundingsFromFirestore(Map<String, dynamic> data, double amount) {
    final raw = data['fundings'];
    if (raw is List) return raw.map(ExpenseFunding.fromMap).whereType<ExpenseFunding>().toList();
    final legacy = FundingSource.fromLabel(data['fundingSource'] as String?);
    if (legacy == FundingSource.unfunded || amount <= 0) return const [];
    return [ExpenseFunding(source: legacy, amount: amount)];
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'category': category.label,
        'amount': amount,
        'fundings': fundings.map((f) => f.toMap()).toList(),
        // Kept for anything still reading the old single-source field.
        'fundingSource': fundings.length == 1 && isFullyFunded
            ? fundings.single.source.label
            : (isUnfunded ? FundingSource.unfunded.label : 'Mixed'),
        if (receiptUrl != null && receiptUrl!.isNotEmpty) 'receiptUrl': receiptUrl,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'incurredAt': incurredAt != null ? Timestamp.fromDate(incurredAt!) : Timestamp.now(),
        'createdBy': createdBy,
        if (animalIndexes != null && animalIndexes!.isNotEmpty) 'animalIndexes': animalIndexes,
      };
}
