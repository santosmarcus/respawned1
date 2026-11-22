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

/// What this case needs from a transporting vehicle: room for its
/// passengers, i.e. how many animals ride (the case's `animals[]`). Size and
/// bite/escape risk no longer change the ranking or add an "enclosed
/// vehicle" requirement; the high-risk banner still warns about them.
class AnimalTransportProfile {
  final int animalCount;

  const AnimalTransportProfile({required this.animalCount});

  /// More than one passenger needs more room than a motorcycle.
  bool get needsBiggerVehicle => animalCount > 1;

  String get passengersLabel => animalCount == 1 ? '1 passenger' : '$animalCount passengers';
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
      // Not assumed to carry several animals — demoted, never hidden.
      VehicleCategory.motorcycle => -2,
    };
  }
  // A single passenger — a motorcycle is a perfectly fine (often
  // faster/more available) match.
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

/// Short line shown on each transporter card, e.g. "Van — fits 2
/// passengers"; just the vehicle for a single passenger.
String compatibilityReason(VehicleCategory category, AnimalTransportProfile profile) {
  final label = vehicleCategoryLabel(category);
  if (!profile.needsBiggerVehicle) return label;
  return '$label — for ${profile.passengersLabel}';
}
