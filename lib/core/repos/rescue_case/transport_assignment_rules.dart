// Pure decisions behind the transport-assignment lifecycle, pulled out of
// TransportAssignmentRepository's transactions so they can be unit-tested
// without Firestore. The repository still does every read and write; these
// functions only decide what the reads mean.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/pet_transporter.dart';

/// What [TransportAssignmentRepository.createAssignmentOffer] does about
/// the assignment the case's `currentAssignmentId` pointer resolves to.
enum OfferConflictResolution {
  /// Rejected / cancelled / completed / expired / missing (dangling): the
  /// pointer is simply overwritten by the new offer.
  none,

  /// A pending offer, or an accepted one without reassign: throw
  /// ActiveAssignmentConflictException.
  block,

  /// An accepted offer on the explicit Reassign Transporter path: mark it
  /// cancelled (superseded) in the same transaction.
  supersede,
}

OfferConflictResolution resolveOfferConflict(
  String? currentStatus, {
  required bool allowReassign,
}) {
  if (currentStatus == 'pending') return OfferConflictResolution.block;
  if (currentStatus == 'accepted') {
    return allowReassign
        ? OfferConflictResolution.supersede
        : OfferConflictResolution.block;
  }
  return OfferConflictResolution.none;
}

/// A real transporter can only be offered a case while their presence is
/// fresh: `online == true` and `lastSeenAt` within
/// [kTransporterPresenceThreshold] of [now].
bool isTransporterStillOnline({
  required bool online,
  required DateTime? lastSeenAt,
  required DateTime now,
}) {
  return online &&
      lastSeenAt != null &&
      now.difference(lastSeenAt) <= kTransporterPresenceThreshold;
}

/// True when [expiresAt] is a Timestamp that [now] is past. A missing or
/// malformed `expiresAt` never expires.
bool isOfferExpired(Object? expiresAt, Timestamp now) {
  return expiresAt is Timestamp && now.compareTo(expiresAt) > 0;
}

/// Why a transporter's accept/reject no longer applies, or null when it
/// still does (expiry is checked separately, since it also triggers a
/// cleanup write). [currentAssignmentId] is only checked when
/// [requireCurrent] is true — accepting requires this offer to still be
/// the case's current one; rejecting doesn't.
String? offerResponseBlockReason({
  required bool exists,
  required String? status,
  required String assignmentId,
  String? currentAssignmentId,
  bool requireCurrent = false,
}) {
  if (!exists) return 'assignment no longer exists';
  if (status != 'pending') return 'status is $status, not pending';
  if (requireCurrent && currentAssignmentId != assignmentId) {
    // The case has moved on to a newer offer (or none) since this one
    // was created — a stale/superseded offer trying to resurrect itself.
    return 'a newer offer has superseded this one';
  }
  return null;
}

// ---- When no transporter can be found -----------------------------------

/// After this many declined or expired offers on one case, Assign
/// Transporter stops suggesting "try another transporter" as the only path
/// and offers the fallbacks (refer, organization transports, keep waiting).
/// For a Critical case, notifyStaffOfOfferOutcome (functions/index.js) also
/// escalates to every organization admin at this point; keep its
/// NO_TRANSPORTER_ATTEMPT_LIMIT the same. Proposed value, pending the
/// organization's confirmation.
const int kNoTransporterAttemptLimit = 3;

/// Offer statuses that count as a failed attempt to find a transporter.
const List<String> kFailedOfferStatuses = ['rejected', 'expired'];

/// True when Assign Transporter should show the "No transporter available"
/// prompt: the search radius reached its maximum with nobody available, or
/// the case has had [kNoTransporterAttemptLimit] offers declined or expired.
bool shouldOfferNoTransporterFallback({
  required bool searchExhausted,
  required int failedOfferCount,
}) {
  return searchExhausted || failedOfferCount >= kNoTransporterAttemptLimit;
}
