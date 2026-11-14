import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:respawnd1/core/models/rescue/expense.dart';

/// Keeps an expense's campaign-linked funding lines and the campaigns'
/// spending records in step. When a line is paid from a campaign, the
/// campaign gets a spending record (recordAllocation) for the same amount;
/// when the line or the expense goes away, that record is voided
/// (voidAllocation) and the money returns to the campaign's balance. Both
/// callables are in functions/campaigns.js and need a financial admin.
class ExpenseFundingService {
  ExpenseFundingService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _functions = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  /// Records spending on the campaign of every linked line that doesn't
  /// have it yet, and returns the lines with their allocation ids. If one
  /// fails, the ones already recorded in this call are voided again before
  /// the error is passed on.
  Future<List<ExpenseFunding>> recordNewLinks({
    required List<ExpenseFunding> lines,
    required String title,
    required ExpenseCategory category,
    String? caseId,
    String? receiptUrl,
  }) async {
    final out = <ExpenseFunding>[];
    final created = <ExpenseFunding>[];
    try {
      for (final line in lines) {
        if (!line.isLinked || line.allocationId != null) {
          out.add(line);
          continue;
        }
        final requestId = _db.collection('fundTransfers').doc().id;
        final result = await _functions.httpsCallable('recordAllocation').call<Object?>({
          'campaignId': line.campaignId,
          'requestId': requestId,
          'label': title,
          'category': category.allocationCategory,
          'amount': line.amount,
          'notes': caseId == null ? 'General expense' : 'Rescue case expense',
          'receiptUrl': ?receiptUrl,
          'linkedCaseId': ?caseId,
        });
        final data = result.data;
        final id = data is Map ? (data['allocationId'] as String? ?? requestId) : requestId;
        final linked = line.withAllocation(id);
        created.add(linked);
        out.add(linked);
      }
      return out;
    } catch (_) {
      for (final line in created) {
        await _void(line, 'Expense was not saved');
      }
      rethrow;
    }
  }

  /// Voids the spending record of every linked line in [before] that is no
  /// longer in [after] (removed from the expense, or the expense deleted).
  Future<void> voidRemovedLinks({
    required List<ExpenseFunding> before,
    List<ExpenseFunding> after = const [],
    required String reason,
  }) async {
    final kept = {for (final f in after) ?f.allocationId};
    for (final line in before) {
      if (line.allocationId != null && !kept.contains(line.allocationId)) {
        await _void(line, reason);
      }
    }
  }

  Future<void> _void(ExpenseFunding line, String reason) async {
    await _functions.httpsCallable('voidAllocation').call<Object?>({
      'campaignId': line.campaignId,
      'allocationId': line.allocationId,
      'reason': reason,
    });
  }
}
