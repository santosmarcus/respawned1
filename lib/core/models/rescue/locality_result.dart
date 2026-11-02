import 'dart:math' as math;
import 'package:respawnd1/core/utils/geo.dart';

/// A single validated city/locality result from Places API (New), used by
/// the Organization service-area picker (see
/// ClinicSearchRepository.searchLocalities) — never a bare free-text
/// string, so "mani" or other fragments can't be saved as a service area.
class LocalityResult {
  final String placeId;
  final String name;
  final String? administrativeArea; // province/region, e.g. "Metro Manila"
  final String? countryCode; // ISO 3166-1 alpha-2, e.g. "PH"

  final double? lat;
  final double? lng;
  final double? radiusKm;

  const LocalityResult({
    required this.placeId,
    required this.name,
    this.administrativeArea,
    this.countryCode,
    this.lat,
    this.lng,
    this.radiusKm,
  });

  /// Parses one entry from Places API (New)'s `places[]` array, reading
  /// `addressComponents` for the province/region and country — only
  /// present when requested in the field mask (see searchLocalities).
  factory LocalityResult.fromPlacesJson(Map<String, dynamic> json) {
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final name = (displayName?['text'] as String?)?.trim() ?? '';
    final components = (json['addressComponents'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    String? findByType(String type) {
      for (final c in components) {
        final types = (c['types'] as List?)?.cast<String>() ?? const [];
        if (types.contains(type)) return (c['longText'] as String?)?.trim();
      }
      return null;
    }

    String? countryCode;
    for (final c in components) {
      final types = (c['types'] as List?)?.cast<String>() ?? const [];
      if (types.contains('country')) {
        countryCode = (c['shortText'] as String?)?.trim();
        break;
      }
    }

    final location = json['location'] as Map<String, dynamic>?;
    final lat = (location?['latitude'] as num?)?.toDouble();
    final lng = (location?['longitude'] as num?)?.toDouble();
    double? radiusKm;
    final viewport = json['viewport'] as Map<String, dynamic>?;
    final high = viewport?['high'] as Map<String, dynamic>?;
    final low = viewport?['low'] as Map<String, dynamic>?;
    if (lat != null && lng != null && high != null && low != null) {
      final r1 = haversineDistanceKm(lat, lng,
          (high['latitude'] as num).toDouble(), (high['longitude'] as num).toDouble());
      final r2 = haversineDistanceKm(lat, lng,
          (low['latitude'] as num).toDouble(), (low['longitude'] as num).toDouble());
      radiusKm = double.parse(math.max(r1, r2).toStringAsFixed(2));
    }

    return LocalityResult(
      placeId: json['id'] as String? ?? '',
      name: name,
      administrativeArea: findByType('administrative_area_level_1'),
      countryCode: countryCode,
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
    );
  }
}
