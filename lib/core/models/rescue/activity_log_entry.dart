import 'package:cloud_firestore/cloud_firestore.dart';

/// An audit entry under `cases/{caseId}/activityLogs/{logId}`, written for
/// every major administrative action (accept, reject, merge, refer, assign
/// clinic, ...). Distinct from the reporter-facing `statusHistory` array on
/// the case doc — this is the org-facing audit trail and always records
/// which staff/admin user performed the action.
class ActivityLogEntry {
  final String id;
  final String caseId;
  final String action;
  final String? actorUid;
  final String? actorName;
  final String? actorRole; // OrgRole.name, or null if not yet known
  final Map<String, dynamic>? details;
  final DateTime? timestamp;

  const ActivityLogEntry({
    required this.id,
    required this.caseId,
    required this.action,
    this.actorUid,
    this.actorName,
    this.actorRole,
    this.details,
    this.timestamp,
  });

  factory ActivityLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String caseId,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['timestamp'];
    return ActivityLogEntry(
      id: doc.id,
      caseId: caseId,
      action: data['action'] as String? ?? '',
      actorUid: data['actorUid'] as String?,
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] as String?,
      details: data['details'] as Map<String, dynamic>?,
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'action': action,
        'actorUid': actorUid,
        'actorName': actorName,
        'actorRole': actorRole,
        if (details != null) 'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      };
}
