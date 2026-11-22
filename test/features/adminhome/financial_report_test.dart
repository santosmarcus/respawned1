import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/financial_report_export.dart';

DonationHistoryRecord _donation(
  String id,
  double amount,
  DateTime at, {
  String type = 'donation',
  String status = 'completed',
  String method = 'GCash',
  String campaignId = 'c1',
  String campaignName = 'Medical fund',
  bool generalFund = false,
  DateTime? reversedAt,
  String item = '',
  int? quantity,
}) =>
    DonationHistoryRecord(
      id: id,
      amountValue: amount,
      amountString: '$amount',
      campaignId: campaignId,
      campaignName: campaignName,
      createdAt: at,
      date: '',
      donorName: 'Donor $id',
      isAnonymous: false,
      itemDescription: item,
      method: method,
      organizer: '',
      refNumber: '',
      type: type,
      status: status,
      generalFund: generalFund,
      reversedAt: reversedAt,
      quantityReceived: quantity,
    );

Expense _expense(String id, double amount, DateTime at, {String caseId = 'case1', String? approval}) => Expense(
      id: id,
      caseId: caseId,
      title: 'Bill $id',
      category: ExpenseCategory.medication,
      amount: amount,
      incurredAt: at,
      approvalStatus: approval,
    );

void main() {
  final from = DateTime(2026, 10);
  final to = DateTime(2026, 11);
  final inOct = DateTime(2026, 10, 15);
  final inSep = DateTime(2026, 9, 20);

  MonthlyFinanceReport build({
    List<DonationHistoryRecord> donations = const [],
    List<DonationHistoryRecord> reversed = const [],
    List<Expense> expenses = const [],
    List<({String campaign, AllocationEntry entry})> allocations = const [],
  }) =>
      buildMonthlyFinanceReport(
        from: from,
        to: to,
        donations: donations,
        reversed: reversed,
        expenses: expenses,
        allocations: allocations,
      );

  test('money in counts credited cash in the month only', () {
    final r = build(donations: [
      _donation('a', 1000, inOct),
      _donation('b', 500, inOct, type: 'sponsorship', method: 'Cash'),
      _donation('c', 300, inSep),
      _donation('d', 200, inOct, status: 'reversed'),
      _donation('e', 0, inOct, type: 'inkind', status: 'completed', item: 'Dog food', quantity: 5),
    ]);
    expect(r.totalIn, 1500);
    expect(r.inByType.map((l) => l.label), containsAll(['Donations', 'Sponsorships']));
    expect(r.inByMethod.firstWhere((l) => l.label == 'GCash').amount, 1000);
    expect(r.inKindLines.single.item, 'Dog food');
    expect(r.inKindLines.single.quantity, 5);
  });

  test('general fund donations are grouped apart from campaigns', () {
    final r = build(donations: [
      _donation('a', 100, inOct),
      _donation('b', 50, inOct, generalFund: true, campaignId: '', campaignName: ''),
    ]);
    expect({for (final l in r.inByFund) l.label: l.amount}, {'Medical fund': 100, 'General fund': 50});
  });

  test('refunds are counted in the month they were reversed', () {
    final r = build(reversed: [
      _donation('old', 400, inSep, status: 'reversed', reversedAt: inOct),
      _donation('later', 100, inOct, status: 'reversed', reversedAt: DateTime(2026, 11, 2)),
    ]);
    expect(r.refunds.map((d) => d.id), ['old']);
    expect(r.totalRefunded, 400);
  });

  test('bills waiting for approval or rejected are not spent; net subtracts the rest', () {
    final r = build(
      donations: [_donation('a', 2000, inOct)],
      reversed: [_donation('r', 100, inSep, status: 'reversed', reversedAt: inOct)],
      expenses: [
        _expense('x', 700, inOct),
        _expense('g', 300, inOct, caseId: ''),
        _expense('p', 900, inOct, approval: 'pending'),
        _expense('n', 50, inOct, approval: 'rejected'),
        _expense('s', 999, inSep),
      ],
    );
    expect(r.totalBills, 1000);
    expect(r.awaitingApproval.map((e) => e.id), ['p']);
    expect(r.net, 2000 - 100 - 1000);
    expect({for (final l in r.billsByKind) l.label: l.amount},
        {'Rescue case bills': 700, 'General running costs': 300});
  });

  test('campaign fund use is listed but not subtracted again', () {
    final alloc = AllocationEntry(
        id: 'al', kind: 'expense', label: 'Vet bill', category: 'Medical', amount: 700, date: '', createdAt: inOct);
    final r = build(
      donations: [_donation('a', 1000, inOct)],
      expenses: [_expense('x', 700, inOct)],
      allocations: [(campaign: 'Medical fund', entry: alloc)],
    );
    expect(r.campaignUseByCategory.single.amount, 700);
    expect(r.net, 300);
  });

  test('peso formatting', () {
    expect(peso(1234567.5), 'PHP 1,234,567.50');
    expect(peso(-20), '-PHP 20.00');
  });
}
