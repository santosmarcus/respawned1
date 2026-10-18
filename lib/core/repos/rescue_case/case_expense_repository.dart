// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/expense.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// Cost-tracking expenses recorded against a case.
class CaseExpenseRepository {
  CaseExpenseRepository(this._store);

  final RescueCaseStore _store;

  Stream<List<Expense>> streamExpenses(String caseId) {
    return _store
        .expensesOf(caseId)
        .orderBy('incurredAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromFirestore(d, caseId)).toList(),
        );
  }

  Future<void> addExpense({
    required String caseId,
    required Expense expense,
  }) async {
    if (expense.title.trim().isEmpty) {
      throw ArgumentError('Expense title is required.');
    }
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    // Every NEW expense requires a receipt (spec) — enforced here too, not
    // just in the UI, so a malformed direct call can't skip it. Existing
    // (legacy) expenses are never retroactively blocked — see updateExpense,
    // which deliberately does not repeat this check.
    if (expense.receiptUrl == null || expense.receiptUrl!.trim().isEmpty) {
      throw ArgumentError('A receipt is required for this expense.');
    }
    await _store.expensesOf(caseId).add({
      ...expense.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateExpense({
    required String caseId,
    required Expense expense,
  }) async {
    if (expense.title.trim().isEmpty) {
      throw ArgumentError('Expense title is required.');
    }
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    await _store
        .expensesOf(caseId)
        .doc(expense.id)
        .update(expense.toFirestore());
  }

  Future<void> deleteExpense({
    required String caseId,
    required String expenseId,
  }) async {
    await _store.expensesOf(caseId).doc(expenseId).delete();
  }
}
