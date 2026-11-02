import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';

/// Central audit trail for categories with no existing per-entity log
/// (Adoptions, Logins, Organization/Staff — Donations has no real write
/// path anywhere in this codebase yet, see AuditCategory's doc comment).
/// Animal Record Changes and Rescue/Case Changes are deliberately NOT
/// written here — they're served straight from the existing
/// `animals/{id}/managementLogs` and `cases/{id}/activityLogs` collections
/// via `collectionGroup`, reusing that logging instead of duplicating it.
///
/// Every write is best-effort and non-blocking (spec: "audit writes do not
/// prevent the main user action from completing if the audit write
/// fails") — [log] never throws; a failure is caught and debugPrint'd,
/// never surfaced to the caller. Callers always perform the real
/// business write FIRST, then call [log] — never inside the same
/// transaction, so a transient audit-write failure can never roll back or
/// block a legitimate action.
class AuditLogRepository {
  AuditLogRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _logs => _db.collection('auditLogs');

  Future<void> log({
    required AuditCategory category,
    required String action,
    String? actorId,
    String? actorEmail,
    String? actorName,
    String? actorRole,
    String? organizationId,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _logs.add({
        'category': category.name,
        'action': action,
        if (actorId != null && actorId.isNotEmpty) 'actorId': actorId,
        if (actorEmail != null && actorEmail.isNotEmpty) 'actorEmail': actorEmail,
        if (actorName != null && actorName.isNotEmpty) 'actorName': actorName,
        if (actorRole != null && actorRole.isNotEmpty) 'actorRole': actorRole,
        if (organizationId != null && organizationId.isNotEmpty) 'organizationId': organizationId,
        if (targetType != null) 'targetType': targetType,
        if (targetId != null) 'targetId': targetId,
        if (oldValues != null && oldValues.isNotEmpty) 'oldValues': oldValues,
        if (newValues != null && newValues.isNotEmpty) 'newValues': newValues,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AuditLogRepository] Failed to write audit log ($category/$action): $e');
    }
  }

  /// Adoptions/Logins/Donations/OrganizationStaff — the centralized
  /// `auditLogs` collection. [organizationId] restricts to the current
  /// organization when provided; every current writer supplies it on a
  /// best-effort basis, so a null filter (no org resolved yet) shows
  /// nothing rather than every organization's entries.
  Stream<List<AuditLogEntry>> streamCategory(
    AuditCategory category, {
    String? organizationId,
    int limit = 30,
  }) {
    Query<Map<String, dynamic>> q = _logs.where('category', isEqualTo: category.name);
    if (organizationId != null) {
      q = q.where('organizationId', isEqualTo: organizationId);
    }
    q = q.orderBy('createdAt', descending: true).limit(limit);
    return q.snapshots().map((snap) {
      final entries = <AuditLogEntry>[];
      for (final doc in snap.docs) {
        try {
          entries.add(AuditLogEntry.fromFirestore(doc));
        } catch (e) {
          debugPrint('[AuditLogRepository] Skipping unparseable audit entry ${doc.id}: $e');
        }
      }
      return entries;
    });
  }

  /// Animal Record Changes — reuses the existing per-animal
  /// `managementLogs` subcollections via a `collectionGroup` query across
  /// every animal at once, rather than a parallel write path.
  Stream<List<AuditDisplayRow>> streamAnimalRecordChanges({int limit = 30}) {
    return _db
        .collectionGroup('managementLogs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _tolerantRows(snap, targetType: 'Animal Record'));
  }

  /// Rescue and Case Changes — reuses the existing per-case
  /// `activityLogs` subcollections the same way.
  Stream<List<AuditDisplayRow>> streamRescueCaseChanges({int limit = 30}) {
    return _db
        .collectionGroup('activityLogs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _tolerantRows(snap, targetType: 'Rescue Case'));
  }

  List<AuditDisplayRow> _tolerantRows(QuerySnapshot<Map<String, dynamic>> snap, {required String targetType}) {
    final rows = <AuditDisplayRow>[];
    for (final doc in snap.docs) {
      try {
        // parentId (the animal/case doc id) is the subcollection's
        // immediate parent — always the second-to-last path segment.
        final parentId = doc.reference.parent.parent?.id;
        rows.add(AuditDisplayRow.fromEntityLog(
          doc,
          targetLabel: parentId != null ? '$targetType #$parentId' : targetType,
        ));
      } catch (e) {
        debugPrint('[AuditLogRepository] Skipping unparseable $targetType log ${doc.id}: $e');
      }
    }
    return rows;
  }
}
