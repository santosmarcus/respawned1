/// A single validated city/locality result from Places API (New), used by
/// the Organization service-area picker (see
/// ClinicSearchRepository.searchLocalities) — never a bare free-text
/// string, so "mani" or other fragments can't be saved as a service area.
class LocalityResult {
  final String placeId;
  final String name;
  final String? administrativeArea; // province/region, e.g. "Metro Manila"
  final String? countryCode; // ISO 3166-1 alpha-2, e.g. "PH"

  const LocalityResult({
    required this.placeId,
    required this.name,
    this.administrativeArea,
    this.countryCode,
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

    return LocalityResult(
      placeId: json['id'] as String? ?? '',
      name: name,
      administrativeArea: findByType('administrative_area_level_1'),
      countryCode: countryCode,
    );
  }
}
