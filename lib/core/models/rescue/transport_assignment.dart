import 'package:cloud_firestore/cloud_firestore.dart';

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
  completed;

  static TransportAssignmentStatus fromName(String? name) => values.firstWhere(
        (v) => v.name == name,
        orElse: () => TransportAssignmentStatus.pending,
      );
}

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
  final DateTime? respondedAt;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final bool isDemo;

  const TransportAssignment({
    required this.id,
    required this.caseId,
    required this.riderId,
    required this.riderName,
    required this.riderType,
    required this.status,
    this.offeredAt,
    this.respondedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.isDemo = false,
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
      respondedAt: ts('respondedAt'),
      acceptedAt: ts('acceptedAt'),
      rejectedAt: ts('rejectedAt'),
      rejectionReason: data['rejectionReason'] as String?,
      completedAt: ts('completedAt'),
      cancelledAt: ts('cancelledAt'),
      cancellationReason: data['cancellationReason'] as String?,
      isDemo: data['isDemo'] as bool? ?? false,
    );
  }

  bool get isActive =>
      status == TransportAssignmentStatus.pending || status == TransportAssignmentStatus.accepted;
}
