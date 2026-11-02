// Pure transit decisions, split out of transit_progress_page.dart
// (behavior-preserving refactor). Nothing in here touches Firebase, the
// network or the widget tree, so all of it is unit-tested directly.

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/core/models/rescue/rescue_status.dart';

// Transit status strings written to `cases/{id}.status` by the transporter:
// accepted           - rider accepted, not yet started
// ongoing            - otw to pickup
// arrived            - arrived at pickup, verify
// treatment          - picked up, otw to clinic
// dropoff            - arrived at a clinic, awaiting Treatment Accepted/Rejected
// searching_clinic   - clinic rejected treatment, auto-searching next nearby clinic
// in_transit_shelter - treatment accepted, on the way to drop the pet at the shelter
// awaiting_adopter_pickup - treatment accepted, interested adopter collects at the clinic
// completed          - rescue done (delivered to shelter / adopter)
// ended              - aborted

/// How close (by road, or straight line when Directions fails) the
/// transporter must be before an "arrived" action is accepted.
const double kArrivalThresholdMeters = 150;

// Temporary default shelter — used whenever
// OrganizationDirectoryRepository.resolveShelterLocation comes back null,
// which per that method's own doc comment is still the common case today
// (org-membership backfill hasn't happened for most test accounts). Without
// this, a case with no org-registered shelter would show "Shelter address
// not available" and have no coordinates to route/verify arrival against.
// Remove once every organization has a real shelter location configured.
const String kFallbackShelterName = 'LGARI Shelter - Tanza';
const String kFallbackShelterAddress =
    'LGARI Shelter, Tanza, Cavite, Philippines';
const double kFallbackShelterLat = 14.3860;
const double kFallbackShelterLng = 120.8283;

/// Nearby-clinic search radii (meters), widened progressively when nearby
/// clinics have already rejected the case.
const List<int> kClinicSearchRadiiMeters = [5000, 10000, 20000, 40000];

/// A clinic with this many non-capacity declines on its profile is skipped
/// by the automatic clinic search.
const int kClinicCapabilityDeclineLimit = 2;

/// Decline reasons that say something about the clinic itself (and are
/// tallied on its `clinic_profiles` doc), as opposed to case-specific ones.
const Set<String> kClinicRelevantReasons = {
  'Clinic at full capacity',
  'Insufficient Medication/Treatment Supplies',
  'No Veterinarian/Specialist Available',
};

/// Reads a lat/lng pair off the case document, if present.
LatLng? latLngFrom(Map<String, dynamic> data, String latKey, String lngKey) {
  final lat = data[latKey];
  final lng = data[lngKey];
  if (lat is num && lng is num) {
    return LatLng(lat.toDouble(), lng.toDouble());
  }
  return null;
}

LatLng? clinicLatLngFrom(Map<String, dynamic> data) {
  return latLngFrom(data, 'dropoffLat', 'dropoffLng') ??
      latLngFrom(data, 'vetClinicLat', 'vetClinicLng');
}

String clinicAddressFrom(Map<String, dynamic> data) {
  final dropoff = (data['dropoffAddress'] as String?)?.trim();
  if (dropoff != null && dropoff.isNotEmpty) return dropoff;
  final vet = (data['vetClinicAddress'] as String?)?.trim();
  if (vet != null && vet.isNotEmpty) return vet;
  return '';
}

/// `clinic_profiles` doc id: the Places id when known, else a slug of the
/// address.
String clinicProfileId({String? placeId, required String address}) {
  if (placeId != null && placeId.isNotEmpty) return placeId;
  final slug = address
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'unknown_clinic' : slug;
}

/// The comma-separated reject [reason] reduced to the clinic-relevant
/// entries that get tallied on the clinic's profile. Empty when accepted.
List<String> clinicDeclineReasons({
  required bool accepted,
  String reason = '',
}) {
  if (accepted) return const <String>[];
  return reason
      .split(',')
      .map((r) => r.trim())
      .where((r) => kClinicRelevantReasons.contains(r))
      .toList();
}

/// Declines on a clinic profile's tally that are about capability, i.e.
/// everything except "full capacity" (which is temporary).
int capabilityDeclineCount(Map<String, dynamic> tally) {
  return tally.entries
      .where((e) => e.key != 'Clinic at full capacity')
      .fold<int>(0, (sum, e) => sum + ((e.value as num?)?.toInt() ?? 0));
}

/// Where the case goes once a clinic accepts treatment. When the reporter
/// answered "yes" to "interested to adopt" on the report form, that
/// reporter is the intended adopter, so the transporter waits at the clinic
/// for them (see AwaitingAdopterPanel) instead of continuing to the shelter.
({String status, String label}) statusAfterTreatmentAccepted(
  Map<String, dynamic> caseData,
) {
  final hasInterestedAdopter = caseData['interestedToAdopt'] == 'yes';
  return hasInterestedAdopter
      ? (
          status: 'awaiting_adopter_pickup',
          label:
              'Treatment accepted. Awaiting the interested adopter to arrive at the treatment location.',
        )
      : (
          status: 'in_transit_shelter',
          label: 'Treatment accepted. On the way to shelter.',
        );
}

// End Reason (close transit) options.
const String kEndReasonNotFound = 'Animal/Reporter not Found';
const String kEndReasonReporterUnreachable = 'Reporter Unreachable';
const String kEndReasonAggressive = 'Animal is too aggressive to handle safely';
const String kEndReasonDeceased = 'Animal Deceased';
const String kEndReasonSpecializedTransport =
    'Animal requires specialized transport that I cannot provide';
const String kEndReasonBreakdown = 'Vehicle breakdown';
const String kEndReasonOther = 'Other';

const List<String> kEndReasons = [
  kEndReasonNotFound,
  kEndReasonReporterUnreachable,
  kEndReasonAggressive,
  kEndReasonDeceased,
  kEndReasonSpecializedTransport,
  kEndReasonBreakdown,
  kEndReasonOther,
];

// Options offered when kEndReasonSpecializedTransport is picked — shown to
// the admin (and factored into vehicle-compatibility ranking) so
// whoever's re-assigned next knows exactly what to bring, instead of
// finding out on-site the same way this transporter just did.
const List<String> kSpecializedServiceTypes = [
  'Larger enclosed vehicle (van/truck)',
  'Secure crate/cage required',
  'Two-person handling required',
  'Climate-controlled transport',
  'Other',
];

/// What the transporter picked in the End Reason dialog.
class EndReasonSelection {
  const EndReasonSelection({
    required this.reason,
    this.otherText,
    this.notes = '',
    this.serviceType,
  });

  final String reason;
  final String? otherText;
  final String notes;
  final String? serviceType;
}

/// The case update an End Reason leads to.
class EndReasonOutcome {
  const EndReasonOutcome({
    required this.status,
    required this.statusLabel,
    required this.reasonText,
    required this.notes,
    this.serviceType,
    this.awaitingReporter = false,
    this.excludeFromTransporterFault = false,
  });

  final String status;
  final String statusLabel;

  /// Written as `endReason` (the "Other" free text when given).
  final String reasonText;

  /// Written as `endReasonNotes` when not empty.
  final String notes;

  /// Written as `endReasonServiceType` (specialized transport only).
  final String? serviceType;

  /// Sets `awaitingReporterSince` (Not Found / Reporter Unreachable).
  final bool awaitingReporter;

  /// Sets `transporterFaultVerified: false` (Aggressive / Specialized).
  final bool excludeFromTransporterFault;

  /// A genuine terminal cancellation (shows the cancelled result screen);
  /// every other outcome keeps the case active.
  bool get isTerminal => status == 'ended';
}

// Decides the resulting case status from the selected End Reason.
//
// - Not Found / Reporter Unreachable: the case is NOT closed as failed —
//   it moves to a reporter-facing "awaiting response" status so the
//   reporter can supply a new location or confirm they're reachable.
//   expireStaleReporterResponses (functions/index.js) auto-closes it if
//   they never respond.
// - Aggressive / Specialized Transport: both escalate to
//   needsSpecializedAssistance instead of ending the case as a failure —
//   "the original rescue report remains active" and the transporter is
//   explicitly not penalized for either outcome. Specialized Transport
//   additionally carries the reported service type forward so it's
//   visible wherever the case shows up as a service request afterward
//   (assign_rider_page.dart, rescue_detail_page.dart) instead of a new
//   transporter having to rediscover the same requirement on-site.
// - Deceased / Vehicle breakdown / Other: remain a straightforward
//   transit-ended outcome.
EndReasonOutcome resolveEndReason(EndReasonSelection selection) {
  final selectedReason = selection.reason;
  final otherText = selection.otherText;
  final serviceType = selection.serviceType;

  final reasonStr = selectedReason == kEndReasonOther
      ? (otherText != null && otherText.isNotEmpty
            ? otherText
            : kEndReasonOther)
      : selectedReason;

  String status;
  String statusLabel;
  switch (selectedReason) {
    case kEndReasonAggressive:
      // Escalate — not a failure, not counted against the transporter.
      status = RescueStatus.needsSpecializedAssistance.firestoreValue;
      statusLabel =
          'Pickup postponed — animal could not be safely handled. '
          'Escalated for specialized assistance.';
      break;
    case kEndReasonSpecializedTransport:
      // Escalate — same as Aggressive, this is a capability mismatch
      // with THIS transporter/vehicle, not a failed rescue.
      status = RescueStatus.needsSpecializedAssistance.firestoreValue;
      statusLabel = serviceType != null && serviceType.isNotEmpty
          ? 'Pickup postponed — requires specialized transport ($serviceType). '
                'Escalated for reassignment.'
          : 'Pickup postponed — requires specialized transport. '
                'Escalated for reassignment.';
      break;
    case kEndReasonNotFound:
      status = RescueStatus.unableToLocate.firestoreValue;
      statusLabel =
          'Animal not found at reported location. Awaiting reporter response.';
      break;
    case kEndReasonReporterUnreachable:
      status = RescueStatus.pickupUnsuccessful.firestoreValue;
      statusLabel = 'Pickup attempt unsuccessful — reporter unreachable.';
      break;
    default:
      status = 'ended';
      statusLabel = 'Transit closed: $reasonStr';
  }

  final specializedTransport = selectedReason == kEndReasonSpecializedTransport;

  return EndReasonOutcome(
    status: status,
    statusLabel: statusLabel,
    reasonText: reasonStr,
    notes: selection.notes,
    serviceType:
        specializedTransport && serviceType != null && serviceType.isNotEmpty
        ? serviceType
        : null,
    awaitingReporter:
        selectedReason == kEndReasonNotFound ||
        selectedReason == kEndReasonReporterUnreachable,
    excludeFromTransporterFault:
        selectedReason == kEndReasonAggressive || specializedTransport,
  );
}
