import 'package:cloud_firestore/cloud_firestore.dart';

enum TransporterApplicationStatus {
  pending,
  approved,
  rejected;

  String get label => switch (this) {
        TransporterApplicationStatus.pending => 'Under review',
        TransporterApplicationStatus.approved => 'Approved',
        TransporterApplicationStatus.rejected => 'Not approved',
      };

  static TransporterApplicationStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => TransporterApplicationStatus.pending);
}

/// `transporterApplications/{uid}`: the identity documents a pet transporter
/// submits from transporter_verification_screen.dart. Private to the
/// applicant and organization staff (firestore.rules); staff approve or
/// reject it, which also sets `users/{uid}.isVerified` /
/// `transporterVerificationStatus`.
class TransporterApplication {
  final String uid;
  final String name;
  final String mobileNumber;
  final String? vehicleType;
  final String? licensePlate;
  final String? licenseFrontUrl;
  final String? licenseBackUrl;
  final String? portraitUrl;
  final String? antiRabiesUrl;
  final TransporterApplicationStatus status;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  const TransporterApplication({
    required this.uid,
    required this.name,
    required this.mobileNumber,
    this.vehicleType,
    this.licensePlate,
    this.licenseFrontUrl,
    this.licenseBackUrl,
    this.portraitUrl,
    this.antiRabiesUrl,
    this.status = TransporterApplicationStatus.pending,
    this.reviewNote,
    this.reviewedBy,
    this.submittedAt,
    this.reviewedAt,
  });

  factory TransporterApplication.fromMap(String uid, Map<String, dynamic> d) {
    DateTime? ts(String k) => d[k] is Timestamp ? (d[k] as Timestamp).toDate() : null;
    String? str(String k) {
      final v = (d[k] as String?)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return TransporterApplication(
      uid: uid,
      name: str('name') ?? '',
      mobileNumber: str('mobileNumber') ?? '',
      vehicleType: str('vehicleType'),
      licensePlate: str('licensePlate'),
      licenseFrontUrl: str('licenseFrontUrl'),
      licenseBackUrl: str('licenseBackUrl'),
      portraitUrl: str('portraitUrl'),
      antiRabiesUrl: str('antiRabiesUrl'),
      status: TransporterApplicationStatus.fromName(d['status'] as String?),
      reviewNote: str('reviewNote'),
      reviewedBy: str('reviewedBy'),
      submittedAt: ts('submittedAt'),
      reviewedAt: ts('reviewedAt'),
    );
  }

  factory TransporterApplication.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TransporterApplication.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// The identity documents, in display order, skipping missing ones.
  List<({String label, String url})> get documents => [
        if (portraitUrl != null) (label: 'Portrait', url: portraitUrl!),
        if (licenseFrontUrl != null) (label: "Driver's license (front)", url: licenseFrontUrl!),
        if (licenseBackUrl != null) (label: "Driver's license (back)", url: licenseBackUrl!),
        if (antiRabiesUrl != null) (label: 'Anti-rabies record', url: antiRabiesUrl!),
      ];
}
