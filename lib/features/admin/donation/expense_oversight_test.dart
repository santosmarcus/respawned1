import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/admin/donation/expense_oversight_page.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

Expense _e(String id,
    {double amount = 1000,
      String? approvalStatus,
      String? receiptUrl,
      DateTime? createdAt,
      DateTime? receiptDueAt}) =>
    Expense(
      id: id,
      caseId: '',
      title: 'Expense $id',
      category: ExpenseCategory.values.first,
      amount: amount,
      approvalStatus: approvalStatus,
      receiptUrl: receiptUrl,
      createdAt: createdAt,
      receiptDueAt: receiptDueAt,
    );

void main() {
  final now = DateTime(2026, 11, 17, 12);

  test('approval is needed only above the threshold', () {
    const off = ShelterSettings();
    const on = ShelterSettings(expenseApprovalThreshold: 5000);
    expect(off.requiresApproval(1e9), isFalse);
    expect(on.requiresApproval(5000), isFalse);
    expect(on.requiresApproval(5000.01), isTrue);
    expect(off.effectiveReceiptDueDays, ShelterSettings.defaultReceiptDueDays);
  });

  test('awaiting approval lists pending expenses, oldest first', () {
    final list = expensesAwaitingApproval([
      _e('b', approvalStatus: 'pending', createdAt: now),
      _e('a', approvalStatus: 'pending', createdAt: now.subtract(const Duration(days: 1))),
      _e('c', approvalStatus: 'approved'),
      _e('d'),
    ]);
    expect(list.map((e) => e.id), ['a', 'b']);
  });

  test('overdue receipts use the due date, or created + default days', () {
    final list = expensesWithOverdueReceipts([
      _e('due-passed', receiptDueAt: now.subtract(const Duration(hours: 1))),
      _e('due-later', receiptDueAt: now.add(const Duration(days: 1))),
      _e('has-receipt', receiptUrl: 'https://x', receiptDueAt: now.subtract(const Duration(days: 9))),
      _e('legacy-old', createdAt: now.subtract(const Duration(days: 8))),
      _e('legacy-new', createdAt: now.subtract(const Duration(days: 2))),
    ], 7, now: now);
    expect(list.map((e) => e.id), ['legacy-old', 'due-passed']);
  });
}
