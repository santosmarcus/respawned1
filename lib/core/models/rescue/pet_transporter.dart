import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed view over a `users/{uid}` doc for accounts with role
/// 'pet_transporter' (see onboard_screen.dart / role_screen.dart, the only
/// two places that ever write that exact role string). Vehicle/plate/photo
/// live under the nested `transporterVerification` map written by
/// transporter_verification_screen.dart, which may be entirely absent for
/// an account that registered but never completed verification.
/// How recent `lastSeenAt` must be for `online: true` to still count as
/// actually online — a transporter who backgrounded/killed the app without
/// explicitly going offline should stop showing as available after this
/// window, not indefinitely. The single shared threshold for every
/// online/availability check in the app (assign_rider_page.dart's rider
/// list, and RescueCaseRepository.createAssignmentOffer's own
/// revalidation) — never hardcode a second number elsewhere.
const Duration kTransporterPresenceThreshold = Duration(minutes: 5);

class PetTransporter {
  final String uid;
  final String name;
  final String? phone;
  final String? photoUrl;
  final String? vehicleType;
  final String? licensePlate;
  final bool isVerified;
  final bool online;
  final DateTime? lastSeenAt;

  const PetTransporter({
    required this.uid,
    required this.name,
    this.phone,
    this.photoUrl,
    this.vehicleType,
    this.licensePlate,
    this.isVerified = false,
    this.online = false,
    this.lastSeenAt,
  });

  /// True only when the transporter's own app last wrote `online: true`
  /// AND that write is still fresh — see [kTransporterPresenceThreshold].
  /// A stale `online: true` (app killed/backgrounded without going
  /// offline) reads as offline here rather than trusting the boolean
  /// forever.
  bool get isOnline =>
      online && lastSeenAt != null && DateTime.now().difference(lastSeenAt!) <= kTransporterPresenceThreshold;

  /// [unnamedLabel] — 'Unnamed Transporter' by default, but this same model
  /// also backs the Volunteers directory (rescue_volunteer accounts share
  /// this exact users/{uid} field shape — see
  /// RescueCaseRepository.streamRescueVolunteers), which passes
  /// 'Unnamed Volunteer' instead so an unnamed entry never misdescribes a
  /// volunteer as a transporter.
  factory PetTransporter.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String unnamedLabel = 'Unnamed Transporter',
  }) {
    final data = doc.data() ?? <String, dynamic>{};
    final verification = data['transporterVerification'] as Map<String, dynamic>?;
    final name = (data['name'] as String?)?.trim();
    final lastSeen = data['lastSeenAt'];
    return PetTransporter(
      uid: doc.id,
      name: (name != null && name.isNotEmpty) ? name : unnamedLabel,
      phone: data['phone'] as String?,
      photoUrl: verification?['portraitUrl'] as String?,
      vehicleType: verification?['vehicleType'] as String?,
      licensePlate: verification?['licensePlate'] as String?,
      isVerified: data['isVerified'] as bool? ?? false,
      online: data['online'] as bool? ?? false,
      lastSeenAt: lastSeen is Timestamp ? lastSeen.toDate() : null,
    );
  }
}
