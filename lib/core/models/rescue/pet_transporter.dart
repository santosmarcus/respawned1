import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed view over a `users/{uid}` doc for accounts with role
/// 'pet_transporter' (see onboard_screen.dart / role_screen.dart, the only
/// two places that ever write that exact role string). Vehicle/plate/photo
/// live under the nested `transporterVerification` map written by
/// transporter_verification_screen.dart, which may be entirely absent for
/// an account that registered but never completed verification.
class PetTransporter {
  final String uid;
  final String name;
  final String? phone;
  final String? photoUrl;
  final String? vehicleType;
  final String? licensePlate;
  final bool isVerified;

  const PetTransporter({
    required this.uid,
    required this.name,
    this.phone,
    this.photoUrl,
    this.vehicleType,
    this.licensePlate,
    this.isVerified = false,
  });

  factory PetTransporter.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final verification = data['transporterVerification'] as Map<String, dynamic>?;
    final name = (data['name'] as String?)?.trim();
    return PetTransporter(
      uid: doc.id,
      name: (name != null && name.isNotEmpty) ? name : 'Unnamed Transporter',
      phone: data['phone'] as String?,
      photoUrl: verification?['portraitUrl'] as String?,
      vehicleType: verification?['vehicleType'] as String?,
      licensePlate: verification?['licensePlate'] as String?,
      isVerified: data['isVerified'] as bool? ?? false,
    );
  }
}
