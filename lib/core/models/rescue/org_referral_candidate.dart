import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// A row in the "Refer to Another Organization" search modal. Reads the
/// same top-level `organizations` collection as
/// lib/features/organization/organization_model.dart, plus a few optional
/// referral-specific fields (accepted species, service area, intake
/// availability) that public org profiles don't need. Kept as a separate
/// model instead of extending Organization so this module doesn't couple
/// to — or need to change — the existing public org-profile screens.
class OrgReferralCandidate {
  final String id;
  final String name;
  final String? avatarUrl;
  final String location;
  final double? lat;
  final double? lng;
  final List<String> acceptedSpecies;
  final String? serviceArea;
  final bool intakeAvailable;

  const OrgReferralCandidate({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.location = '',
    this.lat,
    this.lng,
    this.acceptedSpecies = const [],
    this.serviceArea,
    this.intakeAvailable = true,
  });

  factory OrgReferralCandidate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return OrgReferralCandidate(
      id: doc.id,
      name: data['name'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      location: data['location'] as String? ?? '',
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      acceptedSpecies: List<String>.from(data['acceptedSpecies'] ?? const []),
      serviceArea: data['serviceArea'] as String?,
      intakeAvailable: data['intakeAvailable'] as bool? ?? true,
    );
  }

  double? distanceKmFrom(double fromLat, double fromLng) {
    if (lat == null || lng == null) return null;
    const earthRadiusKm = 6371.0;
    double deg2rad(double deg) => deg * (math.pi / 180.0);
    final dLat = deg2rad(lat! - fromLat);
    final dLng = deg2rad(lng! - fromLng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(deg2rad(fromLat)) *
            math.cos(deg2rad(lat!)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}
