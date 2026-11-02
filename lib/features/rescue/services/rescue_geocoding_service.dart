// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

const String _geocodingApiKey = 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0';

/// Google Geocoding / Places HTTP calls used by the Report a Stray map.
/// Moved verbatim from the page (same endpoints, timeouts, fallbacks and
/// debug logging); the page still owns the loading/UI state around them.
class RescueGeocodingService {
  const RescueGeocodingService();

  Future<String?> nearbyLandmark(LatLng pos) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${pos.latitude},${pos.longitude}'
        '&rankby=distance' // closest first
        '&type=point_of_interest' // landmarks, establishments, etc.
        '&key=$_geocodingApiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      debugPrint("===== NEARBY LANDMARK =====");
      debugPrint("STATUS: ${data['status']}");
      debugPrint("ERROR: ${data['error_message']}");

      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        return data['results'][0]['name'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint("Nearby landmark lookup failed: $e");
      return null;
    }
  }

  /// Reverse-geocodes [pos] to a formatted address, falling back to
  /// "lat, lng" (5 decimals) on any failure — never throws.
  Future<String> reverseGeocode(LatLng pos) async {
    String resolvedAddress;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}'
        '&key=$_geocodingApiKey',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      debugPrint("===== REVERSE GEOCODE =====");
      debugPrint("STATUS: ${data['status']}");
      debugPrint("ERROR: ${data['error_message']}");
      debugPrint("BODY: ${res.body}");

      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        resolvedAddress = data['results'][0]['formatted_address'];
      } else {
        // Fallback to coordinates
        resolvedAddress =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } catch (_) {
      resolvedAddress =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    }
    return resolvedAddress;
  }

  /// Forward-geocodes a typed [address]. Returns null when Google finds no
  /// result; throws on network/parse errors (the caller treats the two
  /// cases differently, as before).
  Future<({LatLng latLng, String formattedAddress})?> geocodeAddress(
    String address,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=${Uri.encodeComponent(address)}'
      '&key=$_geocodingApiKey',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 10));
    final data = jsonDecode(res.body);

    debugPrint("===== ADDRESS SEARCH =====");
    debugPrint("STATUS: ${data['status']}");
    debugPrint("ERROR: ${data['error_message']}");
    debugPrint("BODY: ${res.body}");

    if (res.statusCode == 200 &&
        data['status'] == 'OK' &&
        (data['results'] as List).isNotEmpty) {
      final loc = data['results'][0]['geometry']['location'];
      final latLng = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
      return (
        latLng: latLng,
        formattedAddress: data['results'][0]['formatted_address'] as String,
      );
    }
    return null;
  }
}
