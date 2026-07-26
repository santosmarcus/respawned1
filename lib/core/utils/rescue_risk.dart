/// Per-animal safety-risk vocabulary shared by the Rescue Report form and
/// every screen that needs to warn about a specific animal (Rescue Details,
/// Assign Transporter, the transporter's own job-offer screen, Tracking).
/// Kept as plain string constants — matching how every other selector in
/// this module (urgency, sex, size, temperament) is already stored — rather
/// than a new enum, so existing raw-map readers (rescue_request.dart,
/// assign_rider_page.dart) can keep working directly off `case['biteRisk']`
/// without a parsing layer.
library;

const List<String> kBiteRiskLevels = [
  'Unknown',
  'Low',
  'Moderate',
  'High',
  'Has attempted to bite',
  'Has bitten someone',
];

const List<String> kEscapeRiskLevels = [
  'Unknown',
  'Low',
  'Moderate',
  'High',
  'Actively fleeing',
  'Unable to contain',
];

const List<String> kSafetyIndicatorOptions = [
  'Aggressive',
  'Fearful',
  'Injured',
  'Trapped',
  'Protecting young',
  'In traffic',
  'Hard to approach',
];

/// 'Unknown', null, and unrecognized values are all deliberately NOT
/// high-risk — an animal must never read as aggressive just because its
/// risk was never assessed.
bool isHighBiteRisk(String? biteRisk) =>
    biteRisk == 'High' || biteRisk == 'Has attempted to bite' || biteRisk == 'Has bitten someone';

bool isHighEscapeRisk(String? escapeRisk) =>
    escapeRisk == 'High' || escapeRisk == 'Actively fleeing' || escapeRisk == 'Unable to contain';

bool hasHighRescueRisk({String? biteRisk, String? escapeRisk}) =>
    isHighBiteRisk(biteRisk) || isHighEscapeRisk(escapeRisk);

/// Short human-readable summary of why an animal is flagged, e.g.
/// "Bite risk: Has bitten someone · Escape risk: Actively fleeing". Empty
/// string when neither risk is elevated.
String rescueRiskSummary({String? biteRisk, String? escapeRisk}) {
  final parts = <String>[];
  if (isHighBiteRisk(biteRisk)) parts.add('Bite risk: $biteRisk');
  if (isHighEscapeRisk(escapeRisk)) parts.add('Escape risk: $escapeRisk');
  return parts.join(' · ');
}
