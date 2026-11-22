import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/admin/donation/case_costs_tab.dart';
import 'package:respawnd1/features/donation/models.dart';

Expense _expense(String id, String caseId, double amount, DateTime at) => Expense(
      id: id,
      caseId: caseId,
      title: 'Vet $id',
      category: ExpenseCategory.other,
      amount: amount,
      incurredAt: at,
    );

DonationListing _listing(String id, String? caseId, DateTime created) => DonationListing(
      id: id,
      title: 'Help $id',
      target: 1000,
      collected: 200,
      organizer: 'Org',
      time: '',
      description: '',
      numdonated: 0,
      address: '',
      type: 'donation',
      linkedCaseId: caseId,
      createdAt: created,
    );

void main() {
  test('groups expenses by case, newest spending first, with totals', () {
    final groups = groupCaseCosts([
      _expense('a1', 'caseA', 300, DateTime(2026, 11, 1)),
      _expense('b1', 'caseB', 100, DateTime(2026, 11, 10)),
      _expense('a2', 'caseA', 200, DateTime(2026, 11, 5)),
    ], const []);

    expect(groups.map((g) => g.caseId), ['caseB', 'caseA']);
    final a = groups.last;
    expect(a.expenses.map((e) => e.id), ['a2', 'a1']);
    expect(a.total, 500);
    expect(a.funded, 0);
    expect(a.outstanding, 500);
    expect(a.fundraiser, isNull);
  });

  test('attaches the newest fundraiser linked to the case only', () {
    final groups = groupCaseCosts(
      [_expense('a1', 'caseA', 300, DateTime(2026, 11, 1)), _expense('b1', 'caseB', 50, DateTime(2026, 11, 2))],
      [
        _listing('old', 'caseA', DateTime(2026, 10, 1)),
        _listing('new', 'caseA', DateTime(2026, 11, 3)),
        _listing('general', null, DateTime(2026, 11, 4)),
      ],
    );
    expect(groups.firstWhere((g) => g.caseId == 'caseA').fundraiser?.id, 'new');
    expect(groups.firstWhere((g) => g.caseId == 'caseB').fundraiser, isNull);
  });
}
