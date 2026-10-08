/// Builds a concise species summary such as `Dog ×2, Cat` from a case's
/// animal list. Prefers the newer `animals` array (each entry a
/// `{species, breed, sex, size, colorMarkings}` map); falls back to the
/// legacy single `animalType` field for reports saved before that array
/// existed, so older single-animal cases keep rendering correctly.
///
/// Grouping is case-insensitive (so "dog"/"Dog"/"DOG" count together) but
/// displays using the first-seen casing for that group. A species that
/// appears once is shown without a count; one that repeats gets ` ×N` —
/// this is the one consistent format used everywhere a species summary is
/// shown (case cards, and available for filters/search).
String summarizeSpecies({
  List<dynamic>? animals,
  String? legacyAnimalType,
}) {
  final species = speciesList(animals: animals, legacyAnimalType: legacyAnimalType);
  if (species.isEmpty) return 'Unknown species';

  final order = <String>[];
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final s in species) {
    final key = s.toLowerCase();
    if (!counts.containsKey(key)) {
      order.add(key);
      display[key] = s;
    }
    counts[key] = (counts[key] ?? 0) + 1;
  }

  return order.map((key) {
    final count = counts[key]!;
    return count > 1 ? '${display[key]} ×$count' : display[key]!;
  }).join(', ');
}

/// The raw, un-grouped list of species strings for a case — one entry per
/// animal (never empty unless there's truly no data at all). Used both by
/// [summarizeSpecies] and by filter/search matching, where a multi-animal
/// case needs to match on any of its species, not just the first one.
List<String> speciesList({
  List<dynamic>? animals,
  String? legacyAnimalType,
}) {
  final result = <String>[];
  if (animals != null && animals.isNotEmpty) {
    for (final a in animals) {
      if (a is Map) {
        final raw = (a['species'] as Object?)?.toString().trim();
        result.add((raw == null || raw.isEmpty) ? 'Unknown species' : raw);
      }
    }
  }
  if (result.isEmpty) {
    final raw = legacyAnimalType?.trim();
    if (raw != null && raw.isNotEmpty) result.add(raw);
  }
  return result;
}

/// Number of animals covered by a case — the `animals` array length, or 1
/// for legacy single-animal reports that predate it.
int animalCountOf({List<dynamic>? animals}) => (animals != null && animals.isNotEmpty) ? animals.length : 1;
