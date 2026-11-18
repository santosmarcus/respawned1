import 'package:cloud_firestore/cloud_firestore.dart';

/// The categories the Audit page tabs on. `animalRecords` and `rescueCases`
/// are deliberately NOT written into this model's own `auditLogs`
/// collection — they're served by querying the existing, already-rich
/// per-entity logs this codebase already writes (animals/{id}/
/// managementLogs and cases/{id}/activityLogs, both via
/// `collectionGroup`), reusing that logging rather than duplicating it.
/// Adoptions/Logins/Donations/OrganizationStaff have no existing
/// equivalent log, so those write directly into `auditLogs`.
// Audit Cleanup spec §5 — declaration order is also `AuditCategory.values`'
// iteration order, which is what actually drives both the Audit page's tab
// order and `TabController.length`; reordering here is what reorders the
// tabs (`.name`, used as the stored Firestore `category` value, is based on
// the identifier itself, not position, so this is safe against existing
// data). Ordered to match the admin drawer's own module order
// (admin_drawer.dart's `AdminModule` enum: Dashboard, Rescue, Adoptions,
// Donations, Records, Events, Volunteers, Transporters, Collar Tags,
// Audit) for every category that has a real drawer-module counterpart;
// `logins`/`organizationStaff` have no corresponding drawer module, so they
// come last as a distinct, un-alphabetized trailing group.
enum AuditCategory {
  rescueCases,
  adoptions,
  donations,
  expenses,
  animalRecords,
  logins,
  organizationStaff;

  // Audit Cleanup spec §6 — dropped the redundant visible "Changes"/"and
  // Case" suffixes (the row content directly below each tab already shows
  // the actual action, e.g. "Profile edited" — repeating "Changes" in the
  // section label added no information). Structured previous/new-value
  // detail rows are untouched; see AuditDisplayRow.
  String get label => switch (this) {
        AuditCategory.adoptions => 'Adoptions',
        AuditCategory.logins => 'Logins',
        AuditCategory.donations => 'Donations',
        AuditCategory.expenses => 'Expenses',
        AuditCategory.animalRecords => 'Records',
        AuditCategory.rescueCases => 'Rescue',
        AuditCategory.organizationStaff => 'Organization and Staff',
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
/// What a case/animal log's action code means, as a sentence fragment:
/// `rejected` → "Rejected the case". Unknown codes are turned from
/// snake_case into words.
String auditActionLabel(String code) {
  const labels = {
    'accepted': 'Accepted the case',
    'rejected': 'Rejected the case',
    'assigned_clinic': 'Assigned a clinic',
    'changed_clinic': 'Changed the clinic',
    'case_closed': 'Closed the case',
    'closed_deceased': 'Closed the case (animal died)',
    'treatment_started': 'Started treatment',
    'treatment_update': 'Added a treatment update',
    'intake_assigned': 'Sent animals to intake',
    'intake_confirmed': 'Confirmed intake',
    'intake_completed': 'Completed intake',
    'animal_received': 'Confirmed the animal arrived',
    'received': 'Confirmed the animal arrived',
    'transporter_accepted': 'Transporter accepted the trip',
    'transporter_declined': 'Transporter declined the trip',
    'transporter_claimed': 'Transporter claimed the trip',
    'transferred_animal': 'Transferred an animal',
    'merged': 'Merged a duplicate report',
    'kept_separate': 'Kept reports separate',
    'flagged_possible_duplicate': 'Flagged a possible duplicate',
    'referred_to_lgu': 'Referred to the LGU',
    'referred_to_organization': 'Referred to another organization',
    'referred_to_volunteer': 'Referred to a volunteer',
    'referral_withdrawn': 'Withdrew a referral',
    'referral_expired': 'Referral expired',
    'verification_desk_result': 'Recorded a desk verification',
    'verification_rider_result': 'Recorded an on-site verification',
    'live_proof_requested': 'Asked the reporter for live proof',
    'live_proof_submitted': 'Reporter sent live proof',
    'location_updated': 'Updated the location',
    'community_location_approved': 'Approved a community location update',
    'community_location_rejected': 'Rejected a community location update',
    'community_report_submitted': 'Community report submitted',
    'updated_ownership_info': 'Updated owner information',
    'released_to_reporter': 'Released the animal to the reporter',
    'released_to_adopter': 'Released the animal to the adopter',
    'animal_death_reported': 'Reported an animal death',
    'quarantine_completed': 'Quarantine completed',
    'critical_report_escalated': 'Critical report escalated',
    'test_arrived_at_clinic': 'Marked arrived at clinic (test)',
  };
  final known = labels[code];
  if (known != null) return known;
  if (code.isEmpty) return 'Unknown action';
  final words = code.replaceAll('_', ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

String _humanizeValue(Object? v) {
  if (v == null) return '';
  if (v is List) return v.map(_humanizeValue).where((s) => s.isNotEmpty).join(', ');
  final s = v.toString().trim();
  if (s.isEmpty) return '';
  // A single enum-style token (notAnimal, not_an_animal) reads as words;
  // free text (a typed reason, a name) is shown as written.
  if (s.contains(' ') || !RegExp(r'^[A-Za-z_]+$').hasMatch(s)) return s;
  final spaced = s
      .replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}')
      .replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

String _humanizeKey(String k) {
  final spaced = k
      .replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}')
      .replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

class AuditDisplayRow {
  final String id;
  final String action;
  final String? description;
  final String? actorName;

  /// Who acted, for resolving a name when the log didn't store one.
  final String? actorUid;
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
    this.actorUid,
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
        actorUid: e.actorId,
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
        (rawDetails is Map
            ? rawDetails.entries
                .where((e) => _humanizeValue(e.value).isNotEmpty)
                .map((e) => '${_humanizeKey(e.key.toString())}: ${_humanizeValue(e.value)}')
                .join(' · ')
            : null);
    // 'Staff' is the placeholder some screens write before the name loads.
    final storedName = (data['actorName'] as String?)?.trim();
    return AuditDisplayRow(
      id: doc.id,
      action: auditActionLabel((data['action'] as String?) ?? ''),
      description: description,
      actorName: (storedName == null || storedName.isEmpty || storedName == 'Staff') ? null : storedName,
      actorUid: data['actorUid'] as String?,
      actorEmail: data['actorEmail'] as String?,
      targetLabel: targetLabel,
      oldValues: asMap(data['previousValues']),
      newValues: asMap(data['newValues']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
