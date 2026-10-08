/// A resolved, display-ready snapshot of "whoever is currently transporting
/// this case" — used by both Intake Details' default-transporter display
/// and the shared TransporterDetailsCard on Track Case. Combines whatever
/// the accepted transportAssignment already carried (name/type) with
/// profile data fetched from `users/{uid}` (vehicle/plate/photo/phone) for
/// real transporters, or fixed demo values for the two test transporters.
class TransporterProfile {
  final String uid;
  final String name;
  final String type;
  final String? photoUrl;
  final String? phone;
  final String vehicle;
  final String plate;
  final bool isDemo;

  const TransporterProfile({
    required this.uid,
    required this.name,
    required this.type,
    this.photoUrl,
    this.phone,
    required this.vehicle,
    required this.plate,
    required this.isDemo,
  });
}
