// Split out of rescue_case_repository.dart (behavior-preserving refactor).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/rescue/expense.dart';

import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';

/// Cost-tracking expenses recorded against a case.
class CaseExpenseRepository {
  CaseExpenseRepository(this._store, {AuditLogRepository? audit})
      : _audit = audit ?? AuditLogRepository(firestore: _store.db);

  final RescueCaseStore _store;
  final AuditLogRepository _audit;

  static Map<String, dynamic> _auditValues(Expense e) => {
        'title': e.title,
        'category': e.category.label,
        'amount': e.amount,
        'funding': e.fundingLabel,
        'funded': e.fundedAmount,
      };

  /// Best-effort, after the real write (AuditLogRepository.log never throws).
  Future<void> _log(String caseId, String action, String? expenseId,
      {Map<String, dynamic>? oldValues, Map<String, dynamic>? newValues}) async {
    String? orgId;
    try {
      orgId = (await _store.caseDoc(caseId).get()).data()?['organizationId'] as String?;
    } catch (_) {}
    final user = FirebaseAuth.instance.currentUser;
    await _audit.log(
      category: AuditCategory.expenses,
      action: action,
      actorId: user?.uid,
      actorEmail: user?.email,
      actorName: user?.displayName,
      organizationId: orgId,
      targetType: 'Case expense',
      targetId: expenseId == null ? caseId : '$caseId/$expenseId',
      oldValues: oldValues,
      newValues: newValues,
    );
  }

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

  /// Funding lines must each be positive and together not exceed the cost.
  static void _checkFundings(Expense expense) {
    if (expense.fundings.any((f) => f.amount <= 0)) {
      throw ArgumentError('Each funding amount must be greater than zero.');
    }
    final total = expense.fundings.fold<double>(0, (acc, f) => acc + f.amount);
    if (total > expense.amount + 0.005) {
      throw ArgumentError('Funding adds up to more than the expense amount.');
    }
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
    _checkFundings(expense);
    // Every NEW expense requires a receipt (spec) — enforced here too, not
    // just in the UI, so a malformed direct call can't skip it. Existing
    // (legacy) expenses are never retroactively blocked — see updateExpense,
    // which deliberately does not repeat this check.
    if (expense.receiptUrl == null || expense.receiptUrl!.trim().isEmpty) {
      throw ArgumentError('A receipt is required for this expense.');
    }
    final ref = await _store.expensesOf(caseId).add({
      ...expense.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _log(caseId, 'Expense added', ref.id, newValues: _auditValues(expense));
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
    _checkFundings(expense);
    final before = await _store.expensesOf(caseId).doc(expense.id).get();
    await _store
        .expensesOf(caseId)
        .doc(expense.id)
        .update(expense.toFirestore());
    await _log(
      caseId,
      'Expense edited',
      expense.id,
      oldValues: before.exists ? _auditValues(Expense.fromFirestore(before, caseId)) : null,
      newValues: _auditValues(expense),
    );
  }

  Future<void> deleteExpense({
    required String caseId,
    required String expenseId,
  }) async {
    final before = await _store.expensesOf(caseId).doc(expenseId).get();
    await _store.expensesOf(caseId).doc(expenseId).delete();
    await _log(
      caseId,
      'Expense deleted',
      expenseId,
      oldValues: before.exists ? _auditValues(Expense.fromFirestore(before, caseId)) : null,
    );
  }
}
