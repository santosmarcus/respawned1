import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';

/// The organization's running costs that aren't tied to a rescue case
/// (utilities, rent, food, staff compensation), at `orgExpenses/{id}`.
/// Same shape as a case expense (an [Expense] with an empty caseId) plus
/// `organizationId`. firestore.rules limits them to the organization's
/// financial admins.
class GeneralExpenseRepository {
  GeneralExpenseRepository({FirebaseFirestore? firestore, AuditLogRepository? audit})
      : _db = firestore ?? FirebaseFirestore.instance,
        _audit = audit ?? AuditLogRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final AuditLogRepository _audit;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('orgExpenses');

  /// Newest first.
  Stream<List<Expense>> watch(String organizationId) {
    return _col.where('organizationId', isEqualTo: organizationId).snapshots().map((snap) {
      final list = [for (final d in snap.docs) Expense.fromFirestore(d, '')];
      final epoch = DateTime(0);
      list.sort((a, b) => (b.incurredAt ?? epoch).compareTo(a.incurredAt ?? epoch));
      return list;
    });
  }

  static void _check(Expense e) {
    if (e.title.trim().isEmpty) throw ArgumentError('Expense title is required.');
    if (e.amount <= 0) throw ArgumentError('Expense amount must be greater than zero.');
    if (e.fundings.any((f) => f.amount <= 0)) throw ArgumentError('Each funding amount must be greater than zero.');
    final total = e.fundings.fold<double>(0, (acc, f) => acc + f.amount);
    if (total > e.amount + 0.005) throw ArgumentError('Funding adds up to more than the expense amount.');
  }

  static Map<String, dynamic> _auditValues(Expense e) => {
        'title': e.title,
        'category': e.category.label,
        'amount': e.amount,
        'funding': e.fundingLabel,
      };

  Future<void> _log(String organizationId, String action, String id,
      {Map<String, dynamic>? oldValues, Map<String, dynamic>? newValues}) {
    final user = FirebaseAuth.instance.currentUser;
    return _audit.log(
      category: AuditCategory.expenses,
      action: action,
      actorId: user?.uid,
      actorEmail: user?.email,
      actorName: user?.displayName,
      organizationId: organizationId,
      targetType: 'General expense',
      targetId: id,
      oldValues: oldValues,
      newValues: newValues,
    );
  }

  Future<void> add({required String organizationId, required Expense expense}) async {
    _check(expense);
    final ref = await _col.add({
      ...expense.toFirestore(),
      'organizationId': organizationId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _log(organizationId, 'General expense added', ref.id, newValues: _auditValues(expense));
  }

  Future<void> update({required String organizationId, required Expense expense, Expense? before}) async {
    _check(expense);
    await _col.doc(expense.id).update(expense.toFirestore());
    await _log(organizationId, 'General expense edited', expense.id,
        oldValues: before == null ? null : _auditValues(before), newValues: _auditValues(expense));
  }

  Future<void> delete({required String organizationId, required Expense expense}) async {
    await _col.doc(expense.id).delete();
    await _log(organizationId, 'General expense deleted', expense.id, oldValues: _auditValues(expense));
  }
}
