import 'package:cloud_firestore/cloud_firestore.dart';

/// The categories the Audit page tabs on. `animalRecords` and `rescueCases`
/// are deliberately NOT written into this model's own `auditLogs`
/// collection — they're served by querying the existing, already-rich
/// per-entity logs this codebase already writes (animals/{id}/
/// managementLogs and cases/{id}/activityLogs, both via
/// `collectionGroup`), reusing that logging rather than duplicating it.
/// Adoptions/Logins/Donations/OrganizationStaff have no existing
/// equivalent log, so those write directly into `auditLogs`.
enum AuditCategory {
  adoptions,
  logins,
  donations,
  animalRecords,
  rescueCases,
  organizationStaff;

  String get label => switch (this) {
        AuditCategory.adoptions => 'Adoptions',
        AuditCategory.logins => 'Logins',
        AuditCategory.donations => 'Donations',
        AuditCategory.animalRecords => 'Animal Record Changes',
        AuditCategory.rescueCases => 'Rescue and Case Changes',
        AuditCategory.organizationStaff => 'Organization and Staff Changes',
      };
}

/// One entry under the top-level `auditLogs` collection — used by the
/// Adoptions/Logins/OrganizationStaff tabs (Donations has no real write
/// path yet, see AuditCategory's own doc comment; AnimalRecords/RescueCases
/// read from existing per-entity logs instead of this collection).
///
/// Every field beyond `category`/`action`/`createdAt` is optional and
/// tolerantly parsed — a partially-populated entry (e.g. a login event
/// with no target) must never crash the list, and a genuinely malformed
/// document is caught by the repository's own per-doc try/catch, never
/// this factory throwing uncaught.
class AuditLogEntry {
  final String id;
  final AuditCategory category;
  final String action;
  final String? actorId;
  final String? actorEmail;
  final String? actorName;
  final String? actorRole;
  final String? organizationId;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  const AuditLogEntry({
    required this.id,
    required this.category,
    required this.action,
    this.actorId,
    this.actorEmail,
    this.actorName,
    this.actorRole,
    this.organizationId,
    this.targetType,
    this.targetId,
    this.oldValues,
    this.newValues,
    this.metadata,
    this.createdAt,
  });

  factory AuditLogEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['createdAt'];
    Map<String, dynamic>? asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;
    return AuditLogEntry(
      id: doc.id,
      category: AuditCategory.values.firstWhere(
        (c) => c.name == data['category'],
        orElse: () => AuditCategory.organizationStaff,
      ),
      action: data['action'] as String? ?? 'Unknown action',
      actorId: data['actorId'] as String?,
      actorEmail: data['actorEmail'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
      organizationId: data['organizationId'] as String?,
      targetType: data['targetType'] as String?,
      targetId: data['targetId'] as String?,
      oldValues: asMap(data['oldValues']),
      newValues: asMap(data['newValues']),
      metadata: asMap(data['metadata']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// A read-only, display-normalized shape both the centralized [AuditLogEntry]
/// rows AND the reused managementLogs/activityLogs collectionGroup rows are
/// adapted into, so the Audit page's list UI is written once and shared by
/// every tab regardless of which underlying collection a category reads
/// from.
class AuditDisplayRow {
  final String id;
  final String action;
  final String? description;
  final String? actorName;
  final String? actorEmail;
  final String? targetLabel;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final DateTime? createdAt;

  const AuditDisplayRow({
    required this.id,
    required this.action,
    this.description,
    this.actorName,
    this.actorEmail,
    this.targetLabel,
    this.oldValues,
    this.newValues,
    this.createdAt,
  });

  factory AuditDisplayRow.fromAuditLog(AuditLogEntry e) => AuditDisplayRow(
        id: e.id,
        action: e.action,
        actorName: e.actorName,
        actorEmail: e.actorEmail,
        targetLabel: e.targetType != null ? '${e.targetType}${e.targetId != null ? ' #${e.targetId}' : ''}' : e.targetId,
        oldValues: e.oldValues,
        newValues: e.newValues,
        createdAt: e.createdAt,
      );

  /// Adapts a raw `managementLogs`/`activityLogs` doc into the shared
  /// display row. The two collections don't share an identical shape —
  /// `managementLogs.details` is always a string, while
  /// `activityLogs.details` (see ActivityLogEntry) is a Map — so `details`
  /// is read tolerantly as either.
  factory AuditDisplayRow.fromEntityLog(DocumentSnapshot<Map<String, dynamic>> doc, {String? targetLabel}) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['timestamp'];
    Map<String, dynamic>? asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;
    final rawDetails = data['details'];
    final description = (data['description'] as String?) ??
        (rawDetails is String ? rawDetails : null) ??
        (rawDetails is Map ? rawDetails.entries.map((e) => '${e.key}: ${e.value}').join(', ') : null);
    return AuditDisplayRow(
      id: doc.id,
      action: (data['action'] as String?) ?? 'Unknown action',
      description: description,
      actorName: (data['actorName'] as String?) ?? (data['actorUid'] as String?),
      actorEmail: data['actorEmail'] as String?,
      targetLabel: targetLabel,
      oldValues: asMap(data['previousValues']),
      newValues: asMap(data['newValues']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
