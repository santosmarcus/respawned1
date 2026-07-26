import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses the `returnRequest` map on `adoptions/{id}` — the SAME map the
/// existing adopter-side `AdoptionReturnForm` (post_adoption_page.dart)
/// already writes (reason/reasonOther/urgency/explanation/images/
/// requestedBy/requestedAt), plus the admin-review fields this module adds
/// on top. Never a second return-request collection.
enum ReturnRequestStatus {
  pendingReview,
  // [approved] IS "retrieval unscheduled" — the repository never writes a
  // separate 'retrievalUnscheduled' string; [retrievalUnscheduled] is kept
  // as a display-only alias so screens can match either name against
  // "approved, no schedule yet" without caring which one is on file.
  approved,
  retrievalUnscheduled,
  retrievalScheduled,
  retrieved,
  intake,
  declined,
  cancelled;

  bool get isApprovedAwaitingSchedule => this == approved || this == retrievalUnscheduled;

  String get label => switch (this) {
        ReturnRequestStatus.pendingReview => 'Pending Review',
        ReturnRequestStatus.approved => 'Approved',
        ReturnRequestStatus.retrievalUnscheduled => 'Retrieval Unscheduled',
        ReturnRequestStatus.retrievalScheduled => 'Retrieval Scheduled',
        ReturnRequestStatus.retrieved => 'Retrieved',
        ReturnRequestStatus.intake => 'Intake',
        ReturnRequestStatus.declined => 'Declined',
        ReturnRequestStatus.cancelled => 'Cancelled',
      };

  static ReturnRequestStatus fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ReturnRequestStatus.pendingReview);
}

class ReturnRequest {
  final String reason;
  final String? reasonOther;
  final String urgency;
  final String explanation;
  final List<String> images;
  final String? requestedBy;
  final DateTime? requestedAt;

  final ReturnRequestStatus status;

  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? declinedAt;
  final String? declinedBy;
  final String? declineReason;

  final DateTime? retrievalScheduledAt;
  final DateTime? retrievalDateTime;
  final String? retrievalAddress;
  final double? retrievalLat;
  final double? retrievalLng;
  final String? retrievalNotes;
  final String? scheduledBy;
  // Adopter's own acknowledgement of the admin-set schedule — adopter-side
  // self-service field (ReturnApprovedPage), mirrors the pre-existing
  // returnPickup.confirmedByAdopter behavior this replaces.
  final bool confirmedByAdopter;
  final DateTime? confirmedByAdopterAt;

  final DateTime? retrievedAt;
  final String? retrievedBy;

  final String? intakeCaseId;
  final DateTime? proceededToIntakeAt;

  /// 'adopter' (default — every return request before this field existed
  /// was adopter-initiated) or 'organization' (admin's own Initiate Return
  /// action, spec §4). Purely descriptive — every status/workflow read
  /// site keys off [status] alone, never this, so an org-initiated request
  /// flows through the exact same approve/schedule/retrieve/intake
  /// pipeline an adopter-initiated one does.
  final String source;

  final DateTime? proposedRetrievalDateTime;
  final String? internalNotes;

  const ReturnRequest({
    required this.reason,
    this.reasonOther,
    required this.urgency,
    required this.explanation,
    required this.images,
    this.requestedBy,
    this.requestedAt,
    required this.status,
    this.approvedAt,
    this.approvedBy,
    this.declinedAt,
    this.declinedBy,
    this.declineReason,
    this.retrievalScheduledAt,
    this.retrievalDateTime,
    this.retrievalAddress,
    this.retrievalLat,
    this.retrievalLng,
    this.retrievalNotes,
    this.scheduledBy,
    this.confirmedByAdopter = false,
    this.confirmedByAdopterAt,
    this.retrievedAt,
    this.retrievedBy,
    this.intakeCaseId,
    this.proceededToIntakeAt,
    this.source = 'adopter',
    this.proposedRetrievalDateTime,
    this.internalNotes,
  });

  bool get hasRetrievalSchedule => retrievalDateTime != null;
  bool get isOrgInitiated => source == 'organization';

  static ReturnRequest? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return ReturnRequest(
      reason: map['reason'] as String? ?? '',
      reasonOther: map['reasonOther'] as String?,
      urgency: map['urgency'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      images: List<String>.from(map['images'] ?? const []),
      requestedBy: map['requestedBy'] as String?,
      requestedAt: ts(map['requestedAt']),
      status: ReturnRequestStatus.fromName(map['status'] as String?),
      approvedAt: ts(map['approvedAt']),
      approvedBy: map['approvedBy'] as String?,
      declinedAt: ts(map['declinedAt']),
      declinedBy: map['declinedBy'] as String?,
      declineReason: map['declineReason'] as String?,
      retrievalScheduledAt: ts(map['retrievalScheduledAt']),
      retrievalDateTime: ts(map['retrievalDateTime']),
      retrievalAddress: map['retrievalAddress'] as String?,
      retrievalLat: (map['retrievalLat'] as num?)?.toDouble(),
      retrievalLng: (map['retrievalLng'] as num?)?.toDouble(),
      retrievalNotes: map['retrievalNotes'] as String?,
      scheduledBy: map['scheduledBy'] as String?,
      confirmedByAdopter: map['confirmedByAdopter'] as bool? ?? false,
      confirmedByAdopterAt: ts(map['confirmedByAdopterAt']),
      retrievedAt: ts(map['retrievedAt']),
      retrievedBy: map['retrievedBy'] as String?,
      intakeCaseId: map['intakeCaseId'] as String?,
      proceededToIntakeAt: ts(map['proceededToIntakeAt']),
      source: map['source'] as String? ?? 'adopter',
      proposedRetrievalDateTime: ts(map['proposedRetrievalDateTime']),
      internalNotes: map['internalNotes'] as String?,
    );
  }
}
