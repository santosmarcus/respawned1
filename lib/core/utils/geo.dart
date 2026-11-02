import 'dart:math' as math;

/// Straight-line (haversine) distance between two coordinates, in km.
/// Shared so this formula isn't reimplemented at every call site — see
/// RescueCaseRepository's own copy (kept separate to avoid an unrelated
/// change to already-working duplicate-detection code) and the transporter
/// distance calculations in assign_rider_page.dart / admin_track_case_page.dart.
double haversineDistanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  double deg2rad(double deg) => deg * (math.pi / 180.0);
  final dLat = deg2rad(lat2 - lat1);
  final dLng = deg2rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(deg2rad(lat1)) * math.cos(deg2rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/// Deterministic (NOT `Random()`) offset from (centerLat, centerLng), seeded
/// by [seed]. Used only to place the debug-build demo transporters in
/// assign_rider_page.dart; real transporters use the location they shared.
({double lat, double lng}) deterministicDemoOffset(
  double centerLat,
  double centerLng,
  String seed,
) {
  final hash = seed.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
  // Spread within roughly +-0.03 degrees (~3km) around the center so
  // distances stay plausible for a same-city rescue case.
  final dLat = ((hash % 601) - 300) / 10000.0;
  final dLng = (((hash ~/ 601) % 601) - 300) / 10000.0;
  return (lat: centerLat + dLat, lng: centerLng + dLng);
}
