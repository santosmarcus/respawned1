import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/case_id.dart' as case_id_util;
import 'package:respawnd1/core/utils/species_summary.dart' as species_summary_util;

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
  final String? animalType; // species — legacy single-animal field
  /// Newer multi-animal reports: one entry per animal, each a
  /// `{species, breed, sex, size, colorMarkings}` map. Empty for reports
  /// saved before this field existed — [speciesSummary]/[allSpecies]/
  /// [animalCount] all fall back to [animalType] in that case.
  final List<Map<String, dynamic>> animals;
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

  // ---- Treatment / discharge / deceased ----------------------------
  // dateAdmitted and currentCondition already existed (written by
  // admin_track_case_page.dart / the old treatment_detail_page.dart) —
  // reused here, not duplicated. readyForDischarge/dischargedAt/deceasedAt/
  // treatmentUpdatedAt/latestTreatmentUpdateType are new; causeOfDeath
  // already existed too.
  final DateTime? dateAdmitted;
  final String? currentCondition;
  final bool readyForDischarge;
  final DateTime? dischargedAt;
  final DateTime? deceasedAt;
  final String? causeOfDeath;
  final DateTime? treatmentUpdatedAt;
  final String? latestTreatmentUpdateType;

  // ---- Intake -------------------------------------------------------
  final String? intakeDestinationName;
  final String? intakeDestinationAddress;
  final double? intakeDestinationLat;
  final double? intakeDestinationLng;
  final DateTime? intakeConfirmedAt;
  final DateTime? intakeReceivedAt;

  // ---- Quarantine (optional) -----------------------------------------
  // 'active' | 'completed' | null (never started / skipped).
  final String? quarantineStatus;
  final DateTime? quarantineStartedAt;
  final int? quarantineDurationDays;
  final DateTime? quarantineScheduledEndAt;
  final DateTime? quarantineEndedAt;
  final String? quarantineEndReason;

  /// Full original document — read-only fallback for fields not modeled
  /// above (pickup/dropoff coordinates, transit tracking fields, treatment
  /// logs, etc. owned by other features).
  final Map<String, dynamic> raw;

  const RescueCase({
    required this.id,
    required this.status,
    this.animalType,
    this.animals = const [],
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
    this.dateAdmitted,
    this.currentCondition,
    this.readyForDischarge = false,
    this.dischargedAt,
    this.deceasedAt,
    this.causeOfDeath,
    this.treatmentUpdatedAt,
    this.latestTreatmentUpdateType,
    this.intakeDestinationName,
    this.intakeDestinationAddress,
    this.intakeDestinationLat,
    this.intakeDestinationLng,
    this.intakeConfirmedAt,
    this.intakeReceivedAt,
    this.quarantineStatus,
    this.quarantineStartedAt,
    this.quarantineDurationDays,
    this.quarantineScheduledEndAt,
    this.quarantineEndedAt,
    this.quarantineEndReason,
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
      animals: List<dynamic>.from(data['animals'] ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
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
      dateAdmitted: data['dateAdmitted'] is Timestamp ? (data['dateAdmitted'] as Timestamp).toDate() : null,
      currentCondition: data['currentCondition'] as String?,
      readyForDischarge: data['readyForDischarge'] as bool? ?? false,
      dischargedAt: data['dischargedAt'] is Timestamp ? (data['dischargedAt'] as Timestamp).toDate() : null,
      // deceasedAt is the new authoritative signal; legacy cases only ever
      // set animalStatus:'Deceased' (see treatment_detail_page.dart's prior
      // version) with no deceasedAt at all, so isDeceased below checks both.
      deceasedAt: data['deceasedAt'] is Timestamp ? (data['deceasedAt'] as Timestamp).toDate() : null,
      causeOfDeath: data['causeOfDeath'] as String?,
      treatmentUpdatedAt:
          data['treatmentUpdatedAt'] is Timestamp ? (data['treatmentUpdatedAt'] as Timestamp).toDate() : null,
      latestTreatmentUpdateType: data['latestTreatmentUpdateType'] as String?,
      intakeDestinationName: data['intakeDestinationName'] as String?,
      intakeDestinationAddress: data['intakeDestinationAddress'] as String?,
      intakeDestinationLat: (data['intakeDestinationLat'] as num?)?.toDouble(),
      intakeDestinationLng: (data['intakeDestinationLng'] as num?)?.toDouble(),
      intakeConfirmedAt:
          data['intakeConfirmedAt'] is Timestamp ? (data['intakeConfirmedAt'] as Timestamp).toDate() : null,
      intakeReceivedAt:
          data['intakeReceivedAt'] is Timestamp ? (data['intakeReceivedAt'] as Timestamp).toDate() : null,
      quarantineStatus: data['quarantineStatus'] as String?,
      quarantineStartedAt:
          data['quarantineStartedAt'] is Timestamp ? (data['quarantineStartedAt'] as Timestamp).toDate() : null,
      quarantineDurationDays: (data['quarantineDurationDays'] as num?)?.toInt(),
      quarantineScheduledEndAt: data['quarantineScheduledEndAt'] is Timestamp
          ? (data['quarantineScheduledEndAt'] as Timestamp).toDate()
          : null,
      quarantineEndedAt:
          data['quarantineEndedAt'] is Timestamp ? (data['quarantineEndedAt'] as Timestamp).toDate() : null,
      quarantineEndReason: data['quarantineEndReason'] as String?,
      raw: data,
    );
  }

  String get shortCaseId => case_id_util.shortCaseId(id);

  bool get hasSavedClinic => vetClinicName != null && vetClinicName!.isNotEmpty;

  /// e.g. "Dog ×2, Cat" — prefers [animals], falls back to [animalType].
  String get speciesSummary =>
      species_summary_util.summarizeSpecies(animals: animals, legacyAnimalType: animalType);

  /// Every animal's species, ungrouped — one entry per animal. Used for
  /// filter/search matching so a multi-animal case matches on any of its
  /// species, not just the first/legacy one.
  List<String> get allSpecies =>
      species_summary_util.speciesList(animals: animals, legacyAnimalType: animalType);

  /// Number of animals this case covers — [animals].length, or 1 for a
  /// legacy single-animal report.
  int get animalCount => species_summary_util.animalCountOf(animals: animals);

  /// True once a Death Report has been recorded. Checks the new
  /// [deceasedAt] field first, falling back to the legacy
  /// `animalStatus:'Deceased'` flag (in [raw]) so older death reports
  /// (recorded before [deceasedAt] existed) still read as deceased.
  bool get isDeceased => deceasedAt != null || raw['animalStatus'] == 'Deceased';

  /// Whole days since admission (day of admission counts as day 1), or 0
  /// if there's no admission date on file yet.
  int get daysInTreatment {
    if (dateAdmitted == null) return 0;
    return DateTime.now().difference(dateAdmitted!).inDays + 1;
  }

  /// True while quarantine is genuinely still in progress: status is
  /// 'active' AND (no scheduled end yet, or that end hasn't passed). Once
  /// the scheduled end has passed, this flips to false immediately — even
  /// before RescueCaseRepository.checkAndCompleteQuarantineIfDue has had a
  /// chance to persist quarantineStatus:'completed' — so the UI never
  /// shows a quarantine as "active" past its own deadline just because
  /// nobody has reopened the case yet.
  bool get isQuarantineActive {
    if (quarantineStatus != 'active') return false;
    if (quarantineScheduledEndAt == null) return true;
    return DateTime.now().isBefore(quarantineScheduledEndAt!);
  }

  /// True once quarantine has ended, whether that was recorded (manual end
  /// or already-persisted automatic end) or only derived client-side
  /// because the scheduled end time has passed.
  bool get isQuarantineEffectivelyOver {
    if (quarantineStatus == null) return true; // never started
    if (quarantineStatus == 'completed' || quarantineStatus == 'skipped') return true;
    if (quarantineScheduledEndAt != null && DateTime.now().isAfter(quarantineScheduledEndAt!)) return true;
    return false;
  }

  /// True once the organization has made *any* decision about quarantine
  /// (started it, or explicitly skipped it) — used to stop re-prompting
  /// "Start Quarantine / Skip" on every visit to Intake Details once a
  /// choice has been made.
  bool get hasQuarantineDecision => quarantineStatus != null;
}
