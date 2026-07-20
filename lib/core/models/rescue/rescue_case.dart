import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/case_id.dart' as case_id_util;

/// A single entry in a case's `statusHistory` array — already used
/// throughout the app as `{'status': String, 'timestamp': Timestamp}`.
class StatusHistoryEntry {
  final String status;
  final DateTime? timestamp;

  const StatusHistoryEntry({required this.status, this.timestamp});

  factory StatusHistoryEntry.fromMap(Map<String, dynamic> map) {
    final ts = map['timestamp'];
    return StatusHistoryEntry(
      status: map['status'] as String? ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : Timestamp.now(),
      };
}

/// Typed view over a `cases/{caseId}` document.
///
/// This collection is shared with the reporter app and the pet-transporter
/// app (see lib/features/rescue and lib/features/pettransporter), which
/// read/write many fields this module doesn't otherwise need. [raw] keeps
/// the full original document so those fields are never dropped when this
/// model round-trips through [toUpdateMap] — every write path here uses a
/// partial `update()`, never a full document overwrite.
class RescueCase {
  final String id;
  final RescueStatus status;
  final String? animalType; // species
  final String? urgency; // 'Critical' | 'Medium' | 'Low', see UrgencyLevel
  final String? condition; // description
  final List<String> photoUrls;
  final String? address;
  final double? lat;
  final double? lng;
  final String? reporterId;
  final String? reporterName;
  final String? reporterPhone;
  final DateTime? createdAt;
  final String? interestedToAdopt;
  final String? scannedTagId; // QR/NFC tag scanned during reporting
  final String? willingAdopterId;
  final String? willingAdopterName;
  final String? willingAdopterType;
  final List<String> mergedCaseIds; // duplicate case IDs merged into this one
  final String? mergedIntoCaseId; // set when THIS case was merged elsewhere
  final RejectionReason? rejectionReason;
  final String? rejectionReasonOther;
  final String? organizationId;
  final bool openForTransfer;
  final List<StatusHistoryEntry> statusHistory;
  final String? assignedVolunteerId;
  final String? assignedVolunteerName;
  final String? assignedVehicle;
  final String? assignedPlate;
  final String? vetClinicName;
  final String? vetClinicAddress;
  final String? vetClinicPlaceId;
  final double? vetClinicLat;
  final double? vetClinicLng;
  final String? vetClinicPhone; // only populated when Places has one on file
  final DateTime? vetClinicSelectedAt;

  /// Full original document — read-only fallback for fields not modeled
  /// above (pickup/dropoff coordinates, transit tracking fields, treatment
  /// logs, etc. owned by other features).
  final Map<String, dynamic> raw;

  const RescueCase({
    required this.id,
    required this.status,
    this.animalType,
    this.urgency,
    this.condition,
    this.photoUrls = const [],
    this.address,
    this.lat,
    this.lng,
    this.reporterId,
    this.reporterName,
    this.reporterPhone,
    this.createdAt,
    this.interestedToAdopt,
    this.scannedTagId,
    this.willingAdopterId,
    this.willingAdopterName,
    this.willingAdopterType,
    this.mergedCaseIds = const [],
    this.mergedIntoCaseId,
    this.rejectionReason,
    this.rejectionReasonOther,
    this.organizationId,
    this.openForTransfer = false,
    this.statusHistory = const [],
    this.assignedVolunteerId,
    this.assignedVolunteerName,
    this.assignedVehicle,
    this.assignedPlate,
    this.vetClinicName,
    this.vetClinicAddress,
    this.vetClinicPlaceId,
    this.vetClinicLat,
    this.vetClinicLng,
    this.vetClinicPhone,
    this.vetClinicSelectedAt,
    this.raw = const {},
  });

  factory RescueCase.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return RescueCase.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  /// Convenience for screens still passing the case around as a raw map
  /// (matches the existing `Map<String, dynamic> data` constructor pattern
  /// used by rescue_detail_page.dart and friends).
  factory RescueCase.fromMap(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'];
    return RescueCase(
      id: id,
      status: RescueStatus.fromFirestoreValue(data['status'] as String?),
      animalType: data['animalType'] as String?,
      urgency: data['urgency'] as String?,
      condition: data['condition'] as String?,
      photoUrls: List<String>.from(data['photoUrls'] ?? const []),
      address: data['address'] as String?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      reporterId: data['reporterId'] as String?,
      reporterName: data['reporterName'] as String?,
      reporterPhone: data['reporterPhone'] as String?,
      createdAt: ts is Timestamp ? ts.toDate() : null,
      interestedToAdopt: data['interestedToAdopt'] as String?,
      scannedTagId: data['scannedTagId'] as String?,
      willingAdopterId: data['willingAdopterId'] as String?,
      willingAdopterName: data['willingAdopterName'] as String?,
      willingAdopterType: data['willingAdopterType'] as String?,
      mergedCaseIds: List<String>.from(data['mergedCaseIds'] ?? const []),
      mergedIntoCaseId: data['mergedIntoCaseId'] as String?,
      rejectionReason: data['rejectionReason'] != null
          ? RejectionReason.fromName(data['rejectionReason'] as String?)
          : null,
      rejectionReasonOther: data['rejectionReasonOther'] as String?,
      organizationId: data['organizationId'] as String?,
      openForTransfer: data['openForTransfer'] as bool? ?? false,
      statusHistory: List<Map<String, dynamic>>.from(data['statusHistory'] ?? const [])
          .map(StatusHistoryEntry.fromMap)
          .toList(),
      assignedVolunteerId: data['assignedVolunteerId'] as String?,
      assignedVolunteerName: data['assignedVolunteerName'] as String?,
      assignedVehicle: data['assignedVehicle'] as String?,
      assignedPlate: data['assignedPlate'] as String?,
      vetClinicName: data['vetClinicName'] as String?,
      vetClinicAddress: data['vetClinicAddress'] as String?,
      vetClinicPlaceId: data['vetClinicPlaceId'] as String?,
      vetClinicLat: (data['vetClinicLat'] as num?)?.toDouble(),
      vetClinicLng: (data['vetClinicLng'] as num?)?.toDouble(),
      vetClinicPhone: data['vetClinicPhone'] as String?,
      vetClinicSelectedAt: data['vetClinicSelectedAt'] is Timestamp
          ? (data['vetClinicSelectedAt'] as Timestamp).toDate()
          : null,
      raw: data,
    );
  }

  String get shortCaseId => case_id_util.shortCaseId(id);

  bool get hasSavedClinic => vetClinicName != null && vetClinicName!.isNotEmpty;
}
