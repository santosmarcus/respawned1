/// A single result from a Places API (New) clinic search (Nearby or Text
/// Search) — see ClinicSearchRepository. Not a Firestore model; this only
/// carries data between the search UI and the moment a clinic is saved
/// onto a rescue case (RescueCase.vetClinic* fields).
class ClinicSearchResult {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool? openNow;
  final double? rating;

  /// Places API (New) returns this directly on Nearby/Text Search results
  /// when requested in the field mask — unlike the legacy Places Web
  /// Service, no separate Place Details call is needed to get it.
  final String? phone;

  const ClinicSearchResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.openNow,
    this.rating,
    this.phone,
  });

  /// Parses one entry from Places API (New)'s `places[]` array. Response
  /// shape reference: https://developers.google.com/maps/documentation/places/web-service/nearby-search
  factory ClinicSearchResult.fromPlacesJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final openingHours = json['currentOpeningHours'] as Map<String, dynamic>?;
    final name = (displayName?['text'] as String?)?.trim();
    return ClinicSearchResult(
      placeId: json['id'] as String? ?? '',
      name: (name != null && name.isNotEmpty) ? name : 'Unnamed clinic',
      address: json['formattedAddress'] as String? ?? '',
      lat: (location?['latitude'] as num?)?.toDouble() ?? 0,
      lng: (location?['longitude'] as num?)?.toDouble() ?? 0,
      openNow: openingHours?['openNow'] as bool?,
      rating: (json['rating'] as num?)?.toDouble(),
      phone: json['nationalPhoneNumber'] as String?,
    );
  }
}
