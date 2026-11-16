/// A readable label for a case's raw `status` code.
///
/// People who aren't working a case only get its public copy
/// (`publicCases/{id}`, see functions/public_cases.js), which has the status
/// code but not the status history. Explore Reports used to fall back to
/// "Pending" for every one of those; this turns the code into the current
/// status instead.
String publicCaseStatusLabel(String? status) {
  switch ((status ?? '').trim()) {
    case '':
    case 'pending':
    case 'pending_review':
      return 'Pending review';
    case 'accepted_pending_clinic':
      return 'Accepted by the rescue team';
    case 'accepted':
      return 'Accepted, waiting for a transporter';
    case 'assigned':
      return 'Transporter assigned';
    case 'ongoing':
      return 'Transporter on the way to the animal';
    case 'arrived':
      return 'Transporter arrived at the location';
    case 'treatment':
      return 'Animal picked up, on the way to the clinic';
    case 'dropoff':
      return 'Animal at the clinic';
    case 'searching_clinic':
      return 'Finding another clinic';
    case 'in_transit_shelter':
      return 'On the way to the shelter';
    case 'awaiting_adopter_pickup':
      return 'Waiting for the adopter at the clinic';
    case 'in_treatment':
      return 'Under treatment';
    case 'intake':
      return 'At the shelter';
    case 'referred':
      return 'Referred to another organization';
    case 'possibleDuplicate':
      return 'Under review';
    case 'merged':
      return 'Merged with another report';
    case 'unable_to_locate':
      return 'Animal could not be located';
    case 'awaiting_reporter_response':
      return 'Waiting for the reporter';
    case 'pickup_attempt_unsuccessful':
      return 'Pickup attempt unsuccessful';
    case 'needs_specialized_assistance':
      return 'Needs specialized assistance';
    case 'transit_ended':
    case 'ended':
      return 'Transport stopped — the team is deciding the next step';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'completed':
    case 'closed':
      return 'Completed';
    case 'adopted':
      return 'Adopted';
    default:
    // Unknown code: "some_new_status" -> "Some new status".
      final words = status!.trim().replaceAll('_', ' ');
      return words[0].toUpperCase() + words.substring(1);
  }
}

/// The status line to show for a case: the latest status-history entry
/// when the viewer can read it (the full case), otherwise the label for
/// the current status code (the public copy).
String caseStatusLine(Map<String, dynamic> data) {
  final history = data['statusHistory'];
  if (history is List && history.isNotEmpty) {
    final last = history.last;
    final text = last is Map ? (last['status'] as String?)?.trim() : null;
    if (text != null && text.isNotEmpty) return text;
  }
  return publicCaseStatusLabel(data['status'] as String?);
}
