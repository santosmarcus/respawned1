import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/finance_report_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

final _p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
DateTime _at(int d) => DateTime(2026, 11, d);

DonationRow _gift(double amount, {String type = 'donation', String status = 'paid', String method = 'GCash',
        String campaignId = 'c1', String campaignName = 'Vet fund', DateTime? at, DateTime? reversedAt}) =>
    DonationRow(amount: amount, type: type, status: status, method: method, at: at ?? _at(2),
        campaignId: campaignId, campaignName: campaignName, reversedAt: reversedAt);

FundRow _fund(String title, {String type = 'donation', double target = 0, double collected = 0, double spent = 0,
        double? monthly, bool fullyFunded = false, bool draft = false, String? animal}) =>
    (title: title, type: type, animalName: animal, target: target, collected: collected, transferredIn: 0.0,
     transferredOut: 0.0, spent: spent, monthlyAmount: monthly, fullyFunded: fullyFunded, draft: draft, goalMet: false);

void main() {
  test('money received excludes pending, reversed and in-kind; reversals shown apart', () {
    final m = moneyReceivedIn(_p, [
      _gift(500),
      _gift(1000, method: 'Bank transfer', campaignId: '', campaignName: ''),
      _gift(300, type: 'sponsorship', campaignName: 'Bantay'),
      _gift(200, status: 'pending'),
      _gift(400, status: 'reversed', reversedAt: _at(9)),
      _gift(700, at: DateTime(2026, 10, 30)),
      const DonationRow(amount: 0, type: 'inkind', status: 'completed', method: '', at: null, quantity: 5),
    ]);
    expect((m.total, m.count), (1800.0, 3));
    expect(m.byChannel, {'GCash': 800.0, 'Bank transfer': 1000.0});
    expect(m.byFund, {'Vet fund': 500.0, kGeneralFundLabel: 1000.0, 'Bantay': 300.0});
    expect((m.sponsorship, m.unallocated), (300.0, 1000.0));
    expect((m.reversed, m.reversedCount), (400.0, 1));
  });

  test('expenses by group, from the ledger only', () {
    Expense e(double a, ExpenseCategory c, {String? approval, DateTime? at}) =>
        Expense(id: 'x', caseId: '', title: 't', category: c, amount: a, incurredAt: at ?? _at(3), approvalStatus: approval);
    final t = expensesIn(_p, [
      e(1000, ExpenseCategory.consultation),
      e(500, ExpenseCategory.medication, approval: 'pending'),
      e(300, ExpenseCategory.transport),
      e(800, ExpenseCategory.foodAndSupplies),
      e(200, ExpenseCategory.staffCompensation),
      e(999, ExpenseCategory.rent, at: DateTime(2026, 10, 1)),
    ]);
    expect(t.total, 2800);
    expect(t.byGroup[ExpenseGroup.veterinary], 1500);
    expect(t.byGroup[ExpenseGroup.rescue], 300);
    expect(t.byGroup[ExpenseGroup.shelter], 800);
    expect(t.byGroup[ExpenseGroup.operational], 200);
    expect(t.awaitingApproval, 500);
  });

  test('funds: available, utilization, target completion; drafts left out', () {
    final s = fundStatsOf([
      _fund('Vet fund', target: 10000, collected: 6000, spent: 2000),
      _fund('Food', target: 5000, collected: 5000, spent: 5000),
      _fund('Draft', target: 999, collected: 999, draft: true),
      _fund('Bantay', type: 'sponsorship', collected: 1000, spent: 200, monthly: 1500),
    ]);
    expect(s.available, 4800);
    expect(s.utilization, (spent: 7200.0, raised: 12000.0));
    expect(s.targetCompletion, (raised: 11000.0, target: 15000.0));
    expect(s.goalsReached, const Ratio(1, 2));
  });

  test('sponsorship: fully funded vs underfunded and what is still needed', () {
    final s = sponsorshipStatsOf([
      _fund('Bantay', type: 'sponsorship', collected: 1000, spent: 200, monthly: 1500, animal: 'Bantay'),
      _fund('Mingming', type: 'sponsorship', collected: 2000, monthly: 1500, fullyFunded: true, animal: 'Mingming'),
      _fund('No amount', type: 'sponsorship', collected: 100),
    ]);
    expect((s.animals, s.fullyFunded, s.underfunded, s.noMonthlyAmount), (3, 1, 1, 1));
    expect(s.outstanding, 700);
    expect(s.progress.first.name, 'Bantay');
  });

  test('in-kind kept in quantities: received, used and on hand', () {
    final k = inKindStatsIn(
      _p,
      donations: [
        DonationRow(amount: 0, type: 'inkind', status: 'completed', method: '', at: _at(4), category: 'Food', quantity: 10),
        DonationRow(amount: 0, type: 'inkind', status: 'pending', method: '', at: _at(4), category: 'Food', quantity: 99),
      ],
      movements: [
        {'itemName': 'Dog food', 'kind': 'used', 'change': -4, 'at': _at(6)},
        {'itemName': 'Dog food', 'kind': 'received', 'change': 10, 'at': _at(4)},
      ],
      stock: [(name: 'Dog food', category: 'Food', unit: 'kg', quantity: 6.0)],
    );
    expect(k.receivedByCategory, {'Food': 10});
    expect(k.usedByItem, {'Dog food': (quantity: 4.0, unit: 'kg')});
    expect(k.onHandByCategory, {'Food (kg)': 6.0});
  });
}
