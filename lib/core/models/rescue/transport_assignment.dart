import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

/// Lifecycle of a single rider offer for a rescue case. Distinct from both
/// [RescueStatus] (the case's own admin-facing pipeline status) and the raw
/// pet-transporter transit strings ('ongoing'/'treatment'/'dropoff'/etc.)
/// written by transit_progress_page.dart — this only tracks whether *this
/// particular rider* has accepted, rejected, or is still deciding.
enum TransportAssignmentStatus {
  pending,
  accepted,
  rejected,
  cancelled,
  completed,
  expired;

  static TransportAssignmentStatus fromName(String? name) => values.firstWhere(
        (v) => v.name == name,
        orElse: () => TransportAssignmentStatus.pending,
      );
}

// ---- How long a transporter has to answer an offer ----------------------
//
// The wait depends on the case's urgency, so a Critical case moves on to the
// next transporter quickly. These are the proposed values; the organization
// still has to confirm them, so change them here only.

/// Wait for a Critical case.
const Duration kTransportOfferTtlCritical = Duration(minutes: 5);

/// Wait for every other case (Medium, Low, or not rated).
const Duration kTransportOfferTtlStandard = Duration(minutes: 20);

/// How long a new offer stays open for a case with this [urgency] (the raw
/// `cases/{id}.urgency` string). Only used when the offer is created: the
/// offer's own `expiresAt` is what every later check reads, so changing
/// these values never shortens or extends offers already sent.
///
/// Expiry is enforced inside the accept/reject transactions, by the
/// expireTransportOffers scheduled function (functions/index.js), and by
/// TransportAssignmentRepository.reconcileStaleOffer whenever a staff
/// screen reads the offer.
Duration transportOfferTtlFor(String? urgency) =>
    UrgencyLevel.fromFirestoreValue(urgency) == UrgencyLevel.critical
        ? kTransportOfferTtlCritical
        : kTransportOfferTtlStandard;

/// A single doc under `cases/{caseId}/transportAssignments/{assignmentId}`.
/// One rider offer per doc — rejecting never deletes the doc, it just moves
/// to [TransportAssignmentStatus.rejected] so the offer history is kept.
class TransportAssignment {
  final String id;
  final String caseId;
  final String riderId;
  final String riderName;
  final String riderType;
  final TransportAssignmentStatus status;
  final DateTime? offeredAt;
  final DateTime? expiresAt;
  final DateTime? respondedAt;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final bool isDemo;
  final String? vehicle;
  final String? plate;

  const TransportAssignment({
    required this.id,
    required this.caseId,
    required this.riderId,
    required this.riderName,
    required this.riderType,
    required this.status,
    this.offeredAt,
    this.expiresAt,
    this.respondedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.isDemo = false,
    this.vehicle,
    this.plate,
  });

  factory TransportAssignment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String caseId,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    return TransportAssignment(
      id: doc.id,
      caseId: caseId,
      riderId: data['riderId'] as String? ?? '',
      riderName: data['riderName'] as String? ?? 'Unknown Rider',
      riderType: data['riderType'] as String? ?? 'Pet Transporter',
      status: TransportAssignmentStatus.fromName(data['status'] as String?),
      offeredAt: ts('offeredAt'),
      expiresAt: ts('expiresAt'),
      respondedAt: ts('respondedAt'),
      acceptedAt: ts('acceptedAt'),
      rejectedAt: ts('rejectedAt'),
      rejectionReason: data['rejectionReason'] as String?,
      completedAt: ts('completedAt'),
      cancelledAt: ts('cancelledAt'),
      cancellationReason: data['cancellationReason'] as String?,
      isDemo: data['isDemo'] as bool? ?? false,
      vehicle: data['vehicle'] as String?,
      plate: data['plate'] as String?,
    );
  }

  bool get isActive =>
      status == TransportAssignmentStatus.pending || status == TransportAssignmentStatus.accepted;

  /// True only for a still-pending offer whose [expiresAt] has passed. An
  /// accepted/rejected/cancelled/completed/already-expired offer is never
  /// "expired" in this sense — that word only describes a pending offer that
  /// timed out unanswered.
  bool get isStalePending =>
      status == TransportAssignmentStatus.pending && expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// "Expires in 4m" style label for a pending offer, read from its own
  /// [expiresAt]; empty when the offer has none (very old offers).
  String expiryLabel([DateTime? now]) => offerExpiryLabel(expiresAt, now ?? DateTime.now());
}

/// Staff-facing countdown text for an offer that expires at [expiresAt].
String offerExpiryLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return '';
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return 'Offer expired';
  if (left.inMinutes < 1) return 'Expires in ${left.inSeconds}s';
  return 'Expires in ${left.inMinutes}m ${left.inSeconds % 60}s';
}

/// Thrown by [RescueCaseRepository.acceptAssignment] / [rejectAssignment]
/// when the response no longer applies: the offer was already resolved by
/// someone else, the case's `currentAssignmentId` has moved on to a newer
/// offer (this one was superseded), or the offer's TTL has elapsed. Callers
/// must not treat a caught instance of this as success — in particular
/// real-transporter flows must not navigate into a trip they were not
/// actually granted. A background/demo responder may safely swallow this
/// silently, since "ignore the response" is exactly the desired behavior.
class OfferNoLongerAvailableException implements Exception {
  final String reason;
  const OfferNoLongerAvailableException(this.reason);

  @override
  String toString() => 'This offer is no longer available ($reason).';
}

/// Thrown by [RescueCaseRepository.createAssignmentOffer] when the target
/// (real, non-demo) transporter is no longer online/available — revalidated
/// inside the transaction itself since the admin's rider list may be
/// stale by the time they tap Confirm.
class TransporterNoLongerOnlineException implements Exception {
  const TransporterNoLongerOnlineException();

  @override
  String toString() => 'This transporter is no longer online. Please select another.';
}

/// Thrown by [RescueCaseRepository.createAssignmentOffer] (inside its
/// transaction) when the case's `currentAssignmentId` pointer resolves to a
/// genuinely active (pending/accepted) assignment — carries enough of that
/// assignment's identity for the UI to show "who is already assigned"
/// instead of a generic error, and to offer the right next action (View
/// Pending / Track Case / Reassign Transporter) rather than sending the
/// admin back to a screen that will only fail the same way again. Never
/// thrown for rejected/cancelled/completed/missing (dangling) pointers —
/// those are reconciled transactionally instead of blocking.
class ActiveAssignmentConflictException implements Exception {
  final String assignmentId;
  final TransportAssignmentStatus status;
  final String riderName;
  final String riderType;
  final String? vehicle;
  final String? plate;
  final DateTime? offeredAt;
  final DateTime? acceptedAt;
  final bool isDemo;

  const ActiveAssignmentConflictException({
    required this.assignmentId,
    required this.status,
    required this.riderName,
    required this.riderType,
    this.vehicle,
    this.plate,
    this.offeredAt,
    this.acceptedAt,
    this.isDemo = false,
  });

  factory ActiveAssignmentConflictException.fromMap(String assignmentId, Map<String, dynamic> data) {
    DateTime? ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : null;
    }

    return ActiveAssignmentConflictException(
      assignmentId: assignmentId,
      status: TransportAssignmentStatus.fromName(data['status'] as String?),
      riderName: data['riderName'] as String? ?? 'Unknown Transporter',
      riderType: data['riderType'] as String? ?? 'Pet Transporter',
      vehicle: data['vehicle'] as String?,
      plate: data['plate'] as String?,
      offeredAt: ts('offeredAt'),
      acceptedAt: ts('acceptedAt'),
      isDemo: data['isDemo'] as bool? ?? false,
    );
  }

  /// True identity was resolvable (a real rider name on file) — when false,
  /// the UI should fall back to the generic "An active transporter
  /// assignment already exists." message while still logging
  /// [assignmentId]/[status] for development debugging.
  bool get hasKnownIdentity => riderName.isNotEmpty && riderName != 'Unknown Transporter';

  String get userMessage {
    if (!hasKnownIdentity) return 'An active transporter assignment already exists.';
    return status == TransportAssignmentStatus.pending
        ? 'This case already has a pending assignment for $riderName.'
        : 'This case is currently assigned to $riderName.';
  }

  @override
  String toString() => userMessage;
}
