import 'package:cloud_firestore/cloud_firestore.dart';

/// Rescue gaps 6 and 10: the reporter who said they want to adopt, or a
/// user who registered interest on Track Case, adopts the rescued animal
/// through an adoption request the organization confirms. The request is an
/// `adoptions/{id}` document with `source: 'rescue_case'` and `caseId`; the
/// backend mirrors its state onto the case as `adoptionRequest`
/// (functions/rescue_adoption.js).
///
/// Timeline:
///  1. The adopter fills in the request and accepts the three agreements
///     (vet fees, adopter obligations, pickup window). Status: pending.
///  2. The organization confirms or declines it. Confirmed = "confirmed
///     adopter".
///  3. When the clinic accepts treatment and the case has a confirmed
///     adopter, the transporter's trip is completed there (no shelter
///     leg); without one, the transporter continues to the shelter.
///  4. Once the animal is discharged, staff mark it ready for pickup. The
///     adopter then has [kAdopterPickupWindow] to collect it.
///  5. Staff confirm the pickup, which opens Release Details (agreement and
///     post-adoption follow-ups).
///  6. Not collected in time: the request is closed and the animal goes to
///     the shelter if it has space, or is flagged for referral to another
///     organization if the shelter is full (followUpAdopterPickups).

/// `adoptions/{id}.source` for these requests.
const String kRescueAdoptionSource = 'rescue_case';

/// How long the confirmed adopter has to collect the animal once it is
/// ready. Pending the organization's confirmation; keep equal to
/// PICKUP_WINDOW_HOURS in functions/rescue_adoption_rules.js.
const Duration kAdopterPickupWindow = Duration(hours: 72);

/// The adopter is reminded this long before the window closes. Keep equal
/// to PICKUP_REMINDER_HOURS in functions/rescue_adoption_rules.js.
const Duration kAdopterPickupReminder = Duration(hours: 24);

/// The agreements the adopter must accept, in the order shown, keyed as
/// stored under `agreement` on the request.
const List<(String key, String title, String body)> kRescueAdoptionAgreements = [
  (
  'vetFees',
  'I will pay the veterinary fees',
  'I will shoulder the cost of this animal\'s veterinary treatment from the time I am confirmed as its adopter, '
      'including any bills still open at the clinic when I collect it.',
  ),
  (
  'obligations',
  'I will fulfil my obligations as a pet adopter',
  'I will give the animal food, water, shelter, veterinary care and vaccinations, keep it safe and never abandon '
      'it, and follow the organization\'s post-adoption check-ins.',
  ),
  (
  'pickupWindow',
  'I will collect the animal on time',
  'Once the organization tells me the animal is ready, I will collect it within 72 hours. If I do not, my request '
      'is closed and the animal goes to the shelter, or to another organization if the shelter is full.',
  ),
];

/// Request state as mirrored on the case (`cases/{id}.adoptionRequest`).
enum RescueAdoptionStatus {
  pending,
  approved,
  rejected,
  withdrawn,
  adopted;

  static RescueAdoptionStatus? fromName(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }

  String get label => switch (this) {
    RescueAdoptionStatus.pending => 'Waiting for the organization to confirm',
    RescueAdoptionStatus.approved => 'Confirmed adopter',
    RescueAdoptionStatus.rejected => 'Not approved',
    RescueAdoptionStatus.withdrawn => 'Closed',
    RescueAdoptionStatus.adopted => 'Adopted',
  };
}

/// `cases/{id}.adoptionRequest`, written by the backend.
class CaseAdoptionRequest {
  final String applicationId;
  final String adopterId;
  final String adopterName;
  final RescueAdoptionStatus status;
  final String? closedReason;

  const CaseAdoptionRequest({
    required this.applicationId,
    required this.adopterId,
    required this.adopterName,
    required this.status,
    this.closedReason,
  });

  bool get isConfirmed => status == RescueAdoptionStatus.approved;
  bool get isOpen => status == RescueAdoptionStatus.pending || status == RescueAdoptionStatus.approved;

  static CaseAdoptionRequest? fromCase(Map<String, dynamic> caseData) {
    final raw = caseData['adoptionRequest'];
    if (raw is! Map) return null;
    final status = RescueAdoptionStatus.fromName(raw['status'] as String?);
    final id = raw['applicationId'] as String?;
    if (status == null || id == null) return null;
    return CaseAdoptionRequest(
      applicationId: id,
      adopterId: raw['adopterId'] as String? ?? '',
      adopterName: raw['adopterName'] as String? ?? 'Adopter',
      status: status,
      closedReason: raw['closedReason'] as String?,
    );
  }
}

/// `cases/{id}.adopterPickup`: set when staff mark the animal ready for
/// pickup by the confirmed adopter.
class AdopterPickup {
  final String applicationId;
  final DateTime? readyAt;
  final DateTime? deadline;
  final String place;
  final List<int>? animalIndexes;
  final DateTime? collectedAt;
  final DateTime? missedAt;
  final String? missedOutcome; // 'shelter' | 'refer'

  const AdopterPickup({
    required this.applicationId,
    this.readyAt,
    this.deadline,
    required this.place,
    this.animalIndexes,
    this.collectedAt,
    this.missedAt,
    this.missedOutcome,
  });

  bool get isWaiting => collectedAt == null && missedAt == null;

  static AdopterPickup? fromCase(Map<String, dynamic> caseData) {
    final raw = caseData['adopterPickup'];
    if (raw is! Map) return null;
    DateTime? ts(String k) => raw[k] is Timestamp ? (raw[k] as Timestamp).toDate() : null;
    return AdopterPickup(
      applicationId: raw['applicationId'] as String? ?? '',
      readyAt: ts('readyAt'),
      deadline: ts('deadline'),
      place: raw['place'] as String? ?? 'the clinic',
      animalIndexes: (raw['animalIndexes'] as List?)?.map((e) => (e as num).toInt()).toList(),
      collectedAt: ts('collectedAt'),
      missedAt: ts('missedAt'),
      missedOutcome: raw['missedOutcome'] as String?,
    );
  }
}

/// Who may ask to adopt a case's animal: the reporter who answered "yes" to
/// "interested to adopt", or the user who registered interest on Track Case.
bool canRequestRescueAdoption(Map<String, dynamic> caseData, String uid) =>
    (caseData['reporterId'] == uid && caseData['interestedToAdopt'] == 'yes') ||
        caseData['willingAdopterId'] == uid;
