/// How a case assigned to a transporter (`cases.assignedVolunteerId`)
/// counts toward their trip stats. Shared by the transporter's own profile
/// (transporter_profile.dart) and the admin transporter detail page so the
/// two never disagree.
library;

/// Case statuses while the transporter's trip is still in progress.
const kTransporterOngoingStatuses = {
  'assigned',
  'accepted',
  'ongoing',
  'arrived',
  'treatment',
  'dropoff',
  'searching_clinic',
  'in_transit_shelter',
  'awaiting_adopter_pickup',
};

// Statuses a case moves on to AFTER the transporter's trip is done —
// admin closes it, admits the animal (intake) or starts clinical care.
// Previously only the literal 'completed' counted, so every finished trip
// whose case the admin had already moved on vanished from Completed.
const _afterTransitStatuses = {
  'completed',
  'closed',
  'intake',
  'in_treatment',
};

bool isCompletedTransit(Map<String, dynamic> data) {
  final status = data['status'] as String? ?? '';
  if (_afterTransitStatuses.contains(status)) return true;
  // Proof the trip itself was finished, whatever the case status is now.
  return data['transitCompletedAt'] != null ||
      data['adopterPickupConfirmedAt'] != null ||
      (data['shelterVerificationUrls'] as List?)?.isNotEmpty == true;
}

bool isOngoingTransit(Map<String, dynamic> data) =>
    !isCompletedTransit(data) && kTransporterOngoingStatuses.contains(data['status'] as String? ?? '');
