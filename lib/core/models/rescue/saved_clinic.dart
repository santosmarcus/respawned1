import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';

/// A user-bookmarked clinic — `users/{uid}/savedClinics/{placeId}`.
/// Deliberately lightweight (no full clinic profile): just enough to show
/// in the Select Clinic sheet and re-select without a fresh Places lookup.
/// `placeId` is always the document ID, which is what makes saving the
/// same clinic twice an overwrite rather than a duplicate.
class SavedClinic {
  final String placeId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final String? phone;
  final DateTime? savedAt;

  const SavedClinic({
    required this.placeId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.phone,
    this.savedAt,
  });

  factory SavedClinic.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['savedAt'];
    return SavedClinic(
      placeId: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Unnamed clinic',
      address: data['address'] as String?,
      lat: (data['latitude'] as num?)?.toDouble(),
      lng: (data['longitude'] as num?)?.toDouble(),
      phone: data['phone'] as String?,
      savedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  factory SavedClinic.fromClinicSearchResult(ClinicSearchResult clinic) => SavedClinic(
        placeId: clinic.placeId,
        name: clinic.name,
        address: clinic.address,
        lat: clinic.lat,
        lng: clinic.lng,
        phone: clinic.phone,
      );

  Map<String, dynamic> toFirestore() => {
        'placeId': placeId,
        'name': name,
        'address': address,
        'latitude': lat,
        'longitude': lng,
        'phone': phone,
        'savedAt': FieldValue.serverTimestamp(),
      };

  /// For rendering in the same list as live Places search results. Only
  /// meaningful when [lat]/[lng] are present — callers should skip a saved
  /// clinic with incomplete coordinates rather than plot it at (0,0).
  ClinicSearchResult? toClinicSearchResult() {
    if (lat == null || lng == null) return null;
    return ClinicSearchResult(
      placeId: placeId,
      name: name,
      address: address ?? '',
      lat: lat!,
      lng: lng!,
      phone: phone,
    );
  }
}
