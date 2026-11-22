/// Centralized transporter preference ranking (Assign Transporter spec) —
/// the single place that decides which available transporter is
/// "Preferred" and in what order the rest are shown. Never hides an
/// eligible transporter — only orders them and labels the best match.
library;

/// Best-effort vehicle category guessed from the free-text `vehicleType`
/// field on [PetTransporter] (there is no separate vehicle-category/
/// capacity field in the current data model — see pet_transporter.dart).
/// Keyword-based, so an unrecognized string (including a bare brand/model
/// name with no type word in it) safely falls back to [unknown] rather than
/// guessing wrong.
enum VehicleCategory { motorcycle, car, van, truck, unknown }

VehicleCategory classifyVehicle(String? vehicleType) {
  final v = (vehicleType ?? '').toLowerCase();
  if (v.contains('van')) return VehicleCategory.van;
  if (v.contains('truck') || v.contains('pickup')) return VehicleCategory.truck;
  if (v.contains('car') || v.contains('sedan') || v.contains('suv') || v.contains('hatchback')) {
    return VehicleCategory.car;
  }
  if (v.contains('motor') || v.contains('scooter') || v.contains('moped')) return VehicleCategory.motorcycle;
  return VehicleCategory.unknown;
}

/// What this specific case's animals need from a transporting vehicle —
/// derived from the case's own `animals[]` (size) and bite/escape risk
/// fields, never invented.
class AnimalTransportProfile {
  final bool hasLargeAnimal;
  final int animalCount;
  final bool needsSpecialHandling;

  const AnimalTransportProfile({
    required this.hasLargeAnimal,
    required this.animalCount,
    required this.needsSpecialHandling,
  });

  bool get needsBiggerVehicle => hasLargeAnimal || animalCount > 1 || needsSpecialHandling;
}

/// Higher is a better match. Used as the primary sort key within the
/// already-available/online bucket — distance only breaks ties within the
/// same score, so a compatible-but-farther transporter still ranks above an
/// incompatible-but-closer one (spec: "Do not rank an offline or busy
/// transporter above a compatible available transporter simply because
/// they are nearer" generalizes to vehicle compatibility too).
int vehicleCompatibilityScore(VehicleCategory category, AnimalTransportProfile profile) {
  if (profile.needsBiggerVehicle) {
    return switch (category) {
      VehicleCategory.van => 3,
      VehicleCategory.truck => 2,
      VehicleCategory.car => 1,
      VehicleCategory.unknown => 0,
      // Not assumed safe for a large animal, multiple animals, or an
      // animal needing special handling — demoted, never hidden.
      VehicleCategory.motorcycle => -2,
    };
  }
  // A single small/medium animal with no special handling need — a
  // motorcycle is a perfectly fine (often faster/more available) match.
  return switch (category) {
    VehicleCategory.motorcycle => 2,
    VehicleCategory.car => 1,
    VehicleCategory.van => 1,
    VehicleCategory.truck => 1,
    VehicleCategory.unknown => 0,
  };
}

String vehicleCategoryLabel(VehicleCategory category) => switch (category) {
      VehicleCategory.motorcycle => 'Motorcycle',
      VehicleCategory.car => 'Car',
      VehicleCategory.van => 'Van',
      VehicleCategory.truck => 'Truck',
      VehicleCategory.unknown => 'Vehicle',
    };

/// Short human-readable reason shown on the "Preferred" chip, e.g. "Van —
/// suitable for 2 large animals".
String compatibilityReason(VehicleCategory category, AnimalTransportProfile profile) {
  final label = vehicleCategoryLabel(category);
  if (!profile.needsBiggerVehicle) return label;
  final animalDesc = profile.animalCount > 1
      ? '${profile.animalCount} animals'
      : (profile.hasLargeAnimal ? 'a large animal' : 'special handling');
  return '$label — suitable for $animalDesc';
}
