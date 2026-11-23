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
  // Return Autofill spec §7 — the adopter's own contact number/pickup
  // address, submitted at request time. Distinct from retrievalAddress
  // below (set later by the org during scheduling).
  final String? contactNumber;
  final String? returnAddress;
  /// The pickup pin, prefilled from the application's home pin. Where the
  /// animal is retrieved from, and the returned animal's intake case
  /// location (AdoptionApplicationRepository.proceedToIntake).
  final double? returnLat;
  final double? returnLng;
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
    this.contactNumber,
    this.returnAddress,
    this.returnLat,
    this.returnLng,
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
      contactNumber: map['contactNumber'] as String?,
      returnAddress: map['returnAddress'] as String?,
      returnLat: (map['returnLat'] as num?)?.toDouble(),
      returnLng: (map['returnLng'] as num?)?.toDouble(),
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

/// A pinned place: where a returned animal is picked up from.
class ReturnPickupLocation {
  final double lat;
  final double lng;
  final String? address;
  const ReturnPickupLocation({required this.lat, required this.lng, this.address});
}

/// Where a returned animal is picked up from, best first: the retrieval
/// the organization scheduled, the adopter's return pin, then the home pin
/// on the adoption application ([applicationData] is the `adoptions/{id}`
/// doc). Null when none of them was pinned.
ReturnPickupLocation? returnPickupLocation(Map<String, dynamic> applicationData, ReturnRequest? r) {
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  final personal = applicationData['personal'] is Map ? applicationData['personal'] as Map : const {};
  final homeAddress = text(personal['homeAddress']);
  if (r?.retrievalLat != null && r?.retrievalLng != null) {
    return ReturnPickupLocation(
      lat: r!.retrievalLat!,
      lng: r.retrievalLng!,
      address: text(r.retrievalAddress) ?? text(r.returnAddress) ?? homeAddress,
    );
  }
  if (r?.returnLat != null && r?.returnLng != null) {
    return ReturnPickupLocation(lat: r!.returnLat!, lng: r.returnLng!, address: text(r.returnAddress) ?? homeAddress);
  }
  final lat = personal['homeLat'];
  final lng = personal['homeLng'];
  if (lat is num && lng is num) {
    return ReturnPickupLocation(lat: lat.toDouble(), lng: lng.toDouble(), address: homeAddress);
  }
  return null;
}
