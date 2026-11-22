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
/// * A motorcycle carries one animal, and never one that needs enclosed,
///   stable transport ([enclosedTransportReasons]).
///
/// Capacity is what the transporter declared (`transporterVerification.
/// maxAnimals`), never assumed from the vehicle's name. A transporter who
/// registered before capacity was asked is treated as carrying one animal
/// until they declare it.
library;

import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';
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

/// Why the case's animals need an enclosed, stable vehicle (so not a
/// motorcycle). Empty when nothing says so.
List<String> enclosedTransportReasons(Map<String, dynamic> caseData) {
  final reasons = <String>{};
  if (caseData['urgency'] == 'Critical') reasons.add('critical urgency');
  final animals = caseData['animals'];
  final list = animals is List && animals.isNotEmpty ? animals.whereType<Map>().toList() : [caseData];
  for (final a in list) {
    if (a['size'] == 'Large') reasons.add('a large animal');
    if (a['mobility'] == kMobilityOptions[2]) reasons.add('an animal that cannot walk');
    if (a['alertness'] == kAlertnessOptions[2]) reasons.add('an unresponsive or collapsed animal');
    if (a['injury'] == kInjurySevere || a['injury'] == kInjuryLifeThreatening) reasons.add('a serious injury');
    if (isHighBiteRisk(a['biteRisk'] as String?) || isHighEscapeRisk(a['escapeRisk'] as String?)) {
      reasons.add('a high bite or escape risk');
    }
    if (a['litter'] is Map) reasons.add('a mother with a litter');
  }
  return reasons.toList();
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
  List<String> enclosedReasons = const [],
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
    if (enclosedReasons.isNotEmpty) {
      return VehicleSuitability(
        suitable: false,
        reason: 'Needs an enclosed vehicle (${enclosedReasons.join(', ')})',
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
