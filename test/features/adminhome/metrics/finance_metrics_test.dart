import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/finance_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';

final _p = Period(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
DateTime _at(int day) => DateTime(2026, 11, day);

DonationRow _money(double amount, {String source = 'paymongo', String method = 'GCash', String status = 'paid', DateTime? at}) =>
    DonationRow(amount: amount, type: 'donation', status: status, source: source, method: method, at: at ?? _at(2));

Expense _expense(double amount, {bool running = false, ExpenseCategory category = ExpenseCategory.medication, String caseId = 'c1', List<int>? animals, DateTime? at}) =>
    Expense(id: 'x', caseId: caseId, title: 't', category: category, amount: amount, incurredAt: at ?? _at(3), isRunningBill: running, animalIndexes: animals);

void main() {
  final donations = [
    _money(500),
    _money(1000, source: 'manual', method: 'Bank transfer'),
    _money(300, status: 'pending'),
    _money(200, status: 'reversed'),
    _money(700, at: DateTime(2026, 10, 30)),
    const DonationRow(amount: 0, type: 'inkind', status: 'completed', source: 'manual', method: '', at: null, category: 'Food', quantity: 5),
    DonationRow(amount: 0, type: 'inkind', status: 'completed', source: 'manual', method: '', at: _at(4), category: 'Food', quantity: 10),
    DonationRow(amount: 0, type: 'inkind', status: 'pending', source: 'manual', method: '', at: _at(4), category: 'Food', quantity: 99),
  ];

  test('funds collected: only received money, by channel; automatic share', () {
    final f = fundsCollectedIn(_p, donations);
    expect(f.total, 1500);
    expect(f.count, 2);
    expect(f.byChannel.keys, containsAll(['PayMongo · GCash', 'Logged by staff · Bank transfer']));
    expect(f.automatic, const Fraction(1, 2));
  });

  test('a running bill is owed, not spent', () {
    final s = expensesIn(_p, [
      _expense(400),
      _expense(600, running: true),
      _expense(100, category: ExpenseCategory.transport),
      _expense(900, at: DateTime(2026, 10, 1)),
    ]);
    expect(s.paid, 500);
    expect(s.running, 600);
    expect(s.byCategory['Medication'], (paid: 400.0, running: 600.0));
  });

  test('funds flow keeps four separate figures', () {
    final flow = fundsFlowIn(
      _p,
      donations: donations,
      cashOuts: [(amount: 800.0, at: _at(5)), (amount: 50.0, at: DateTime(2026, 9, 1))],
      allocations: [(amount: 300.0, at: _at(6))],
      expenses: [_expense(400), _expense(600, running: true)],
    );
    expect((flow.received, flow.cashedOut, flow.allocated, flow.spent), (1500.0, 800.0, 300.0, 400.0));
  });

  test('in-kind: received quantities, and used out of received from stock movements', () {
    expect(inKindReceivedIn(_p, donations), {'Food': (donations: 1, quantity: 10)});
    final usage = inKindUsageIn(_p, [
      {'itemId': 'inkind_food', 'itemName': 'Food', 'kind': 'received', 'change': 10, 'at': _at(4)},
      {'itemId': 'inkind_food', 'itemName': 'Food', 'kind': 'used', 'change': -4, 'at': _at(6)},
      {'itemId': 'dogfood', 'itemName': 'Bought food', 'kind': 'used', 'change': -2, 'at': _at(6)},
    ]);
    expect(usage.single, (item: 'Food', received: 10.0, used: 4.0));
  });

  test('campaigns lowest share first; cost per animal only when tied to one animal', () {
    final list = campaignsByProgress([
      (title: 'A', target: 1000.0, collected: 900.0, active: true, createdAt: null),
      (title: 'B', target: 1000.0, collected: 100.0, active: true, createdAt: null),
      (title: 'C', target: 0.0, collected: 100.0, active: true, createdAt: null),
      (title: 'D', target: 1000.0, collected: 0.0, active: false, createdAt: null),
    ]);
    expect(list.map((c) => c.title), ['B', 'A']);

    final cost = costPerAnimal([
      _expense(100, caseId: 'one'),
      _expense(50, caseId: 'one', running: true),
      _expense(200, caseId: 'two', animals: [1]),
      _expense(999, caseId: 'two'),
    ], {'one': 1, 'two': 3});
    expect(cost, {'one#0': (paid: 100.0, running: 50.0), 'two#1': (paid: 200.0, running: 0.0)});
  });
}
