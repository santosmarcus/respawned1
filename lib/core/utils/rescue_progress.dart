/// Where a rescue case is in its normal path, for the reporter's "Rescue
/// progress" timeline on Track Case. Raw `cases.status` values only — the
/// pet-transporter app writes several transit sub-states (see
/// RescueStatus._legacyAliases), each placed on the step it belongs to.
library;

/// The steps, in order. A case's progress is how many of these are done.
const List<(String, String)> kRescueProgressSteps = [
  ('Case reported', 'Your report was submitted.'),
  ('Reviewed', 'Staff check the report and accept the case.'),
  ('Transporter on the way', 'A transporter heads to the animal.'),
  ('At the clinic', 'The animal is checked and treated.'),
  ('Shelter intake', 'The animal moves to the shelter.'),
  ('Completed', 'The rescue is finished.'),
];

/// How many steps of [kRescueProgressSteps] are finished for [status], or
/// null when the case left the normal path (rejected, referred, cancelled,
/// waiting on the reporter, ...) — the status history explains those.
int? rescueProgressFinished(String? status) {
  switch ((status ?? '').trim()) {
    case 'pending':
    case 'verifying':
    case 'possibleDuplicate':
      return 1;
    case 'accepted_pending_clinic':
    case 'accepted':
      return 2;
    case 'assigned':
    case 'ongoing':
    case 'searching_clinic':
    case 'arrived':
    case 'treatment': // transporter's "picked up, heading to the clinic"
      return 2;
    case 'dropoff':
    case 'awaiting_adopter_pickup':
    case 'in_treatment':
      return 3;
    case 'in_transit_shelter':
    case 'intake':
      return 4;
    case 'completed':
    case 'closed':
      return kRescueProgressSteps.length;
    default:
      return null;
  }
}

/// A short line for the current step when the transporter's own sub-state
/// says more than the step title (e.g. picked up vs still heading there).
String? rescueProgressDetail(String? status) => switch ((status ?? '').trim()) {
      'assigned' || 'ongoing' => 'Transporter assigned and heading to the animal.',
      'searching_clinic' => 'Transporter is finding the nearest clinic.',
      'arrived' => 'Transporter has arrived at the location.',
      'treatment' => 'Animal picked up — on the way to the clinic.',
      'dropoff' => 'Animal arrived at the clinic.',
      'awaiting_adopter_pickup' => 'At the clinic, waiting for the adopter.',
      'in_treatment' => 'The animal is receiving treatment.',
      'in_transit_shelter' => 'On the way from the clinic to the shelter.',
      _ => null,
    };
