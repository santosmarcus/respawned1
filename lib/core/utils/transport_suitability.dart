/// Which transporters' vehicles can carry a case's animals: used by Assign
/// Transporter to recommend (and only allow) suitable ones, and re-checked
/// by TransportAssignmentRepository.createAssignmentOffer and firestore.rules
/// before an offer is created.
///
/// Rules (initial, per the organization):
/// * 1 animal: a motorcycle or any other registered vehicle.
/// * 2 animals: a vehicle whose declared capacity is at least 2.
/// * More than 2: a sedan or larger (never a motorcycle) whose declared
///   capacity covers every animal.
/// * A motorcycle carries one animal.
///
/// Only the number of passengers (animals riding) decides suitability; an
/// "enclosed vehicle" requirement (from size, injury, risk or urgency) was
/// removed at the organization's request.
///
/// Capacity is what the transporter declared (`transporterVerification.
/// maxAnimals`), never assumed from the vehicle's name. A transporter who
/// registered before capacity was asked is treated as carrying one animal
/// until they declare it.
library;

import 'package:respawnd1/core/utils/transporter_ranking.dart';

/// The vehicle types offered at registration
/// (transporter_verification_screen.dart).
const String kVehicleMotorcycle = 'Motorcycle';
const List<String> kVehicleTypes = [kVehicleMotorcycle, 'Sedan', 'SUV', 'Cargo Van/L300'];

/// The most animals a transporter can declare (a sanity limit).
const int kMaxDeclaredAnimals = 20;

/// A declared capacity, or null when missing or not a usable number.
int? declaredAnimalCapacity(Object? value) {
  final n = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
  return (n == null || n < 1 || n > kMaxDeclaredAnimals) ? null : n;
}

/// How many animals the trip carries: every animal on the case (a legacy
/// single-animal case counts as one).
int animalsToTransport(Map<String, dynamic> caseData) {
  final animals = caseData['animals'];
  return animals is List && animals.isNotEmpty ? animals.length : 1;
}

/// Whether one transporter's vehicle suits the trip, and why.
class VehicleSuitability {
  const VehicleSuitability({
    required this.suitable,
    required this.reason,
    required this.effectiveCapacity,
    this.declaredCapacity,
  });

  final bool suitable;

  /// Short explanation shown on the transporter card.
  final String reason;

  /// The most animals this vehicle may carry here (1 for a motorcycle or
  /// an undeclared capacity).
  final int effectiveCapacity;
  final int? declaredCapacity;
}

VehicleSuitability vehicleSuitability({
  required String? vehicleType,
  required Object? declaredCapacity,
  required int animals,
}) {
  final type = (vehicleType ?? '').trim();
  final declared = declaredAnimalCapacity(declaredCapacity);
  if (type.isEmpty) {
    return VehicleSuitability(
      suitable: false,
      reason: 'No vehicle registered',
      effectiveCapacity: 0,
      declaredCapacity: declared,
    );
  }
  // Same vehicle parser as the ranking (transporter_ranking.dart), so
  // older free-text types ("motor", "scooter") count as motorcycles too.
  if (classifyVehicle(type) == VehicleCategory.motorcycle) {
    if (animals > 1) {
      return VehicleSuitability(
        suitable: false,
        reason: 'A motorcycle carries one animal; this trip has $animals',
        effectiveCapacity: 1,
        declaredCapacity: declared,
      );
    }
    return VehicleSuitability(
      suitable: true,
      reason: 'Suitable for one animal',
      effectiveCapacity: 1,
      declaredCapacity: declared,
    );
  }
  final capacity = declared ?? 1;
  if (animals > capacity) {
    return VehicleSuitability(
      suitable: false,
      reason: declared == null
          ? 'Capacity not declared, so only single-animal trips; this trip has $animals'
          : 'Carries up to $capacity; this trip has $animals',
      effectiveCapacity: capacity,
      declaredCapacity: declared,
    );
  }
  return VehicleSuitability(
    suitable: true,
    reason: declared == null
        ? 'Capacity not declared (counted as 1)'
        : 'Carries up to $capacity; this trip has $animals',
    effectiveCapacity: capacity,
    declaredCapacity: declared,
  );
}

/// Thrown when an offer would go to a transporter whose vehicle doesn't
/// suit the trip (re-checked when the offer is created).
class UnsuitableVehicleException implements Exception {
  const UnsuitableVehicleException(this.reason);
  final String reason;

  @override
  String toString() => "This transporter's vehicle isn't suitable for this trip: $reason. Please select another.";
}
