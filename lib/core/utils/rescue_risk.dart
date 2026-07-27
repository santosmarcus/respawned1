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

/// One flagged animal within a case, ready for display. [label] is that
/// animal's species (or "Animal N" if species is missing) — never a
/// fabricated name.
class HighRiskAnimal {
  final String label;
  final String? biteRisk;
  final String? escapeRisk;
  const HighRiskAnimal({required this.label, this.biteRisk, this.escapeRisk});
  String get summary => rescueRiskSummary(biteRisk: biteRisk, escapeRisk: escapeRisk);
}

/// Every high-risk animal in a case. A case now covers one or more animals
/// via its `animals` array (one entry per animal, each optionally carrying
/// its own `biteRisk`/`escapeRisk`) — this checks every entry so a report
/// with, say, a low-risk dog and a high-risk cat still surfaces the cat's
/// warning. Falls back to the legacy case-level biteRisk/escapeRisk fields
/// for single-animal reports saved before the `animals` array existed,
/// mirroring species_summary.dart's own animals-array-first/legacy-fallback
/// pattern so old data keeps reading correctly.
List<HighRiskAnimal> highRiskAnimalsIn({
  List<dynamic>? animals,
  String? legacyBiteRisk,
  String? legacyEscapeRisk,
}) {
  if (animals != null && animals.isNotEmpty) {
    final result = <HighRiskAnimal>[];
    for (var i = 0; i < animals.length; i++) {
      final a = animals[i];
      if (a is! Map) continue;
      final biteRisk = a['biteRisk'] as String?;
      final escapeRisk = a['escapeRisk'] as String?;
      if (!hasHighRescueRisk(biteRisk: biteRisk, escapeRisk: escapeRisk)) continue;
      final species = (a['species'] as Object?)?.toString().trim();
      result.add(HighRiskAnimal(
        label: (species == null || species.isEmpty) ? 'Animal ${i + 1}' : species,
        biteRisk: biteRisk,
        escapeRisk: escapeRisk,
      ));
    }
    return result;
  }
  if (hasHighRescueRisk(biteRisk: legacyBiteRisk, escapeRisk: legacyEscapeRisk)) {
    return [HighRiskAnimal(label: 'This animal', biteRisk: legacyBiteRisk, escapeRisk: legacyEscapeRisk)];
  }
  return const [];
}
