import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/media_ref.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/geo.dart';

/// Report verification: what staff look at before deciding whether a rescue
/// report is real, and the record of what they decided.
///
/// Stored on `cases/{id}`:
///   - `reportEvidence`: how the report was made (written with the report);
///   - `liveProofRequest` / `liveProof`: staff ask the reporter for a fresh
///     photo or video, and the reporter's answer;
///   - `verification`: the desk check result, the rider sent (if any) and
///     what the rider found.

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;
String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

/// How far apart two points are, in metres; null when either is unknown.
double? metresBetween(double? lat1, double? lng1, double? lat2, double? lng2) {
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
  return haversineDistanceKm(lat1, lng1, lat2, lng2) * 1000;
}

/// "120 m" or "3.4 km".
String formatDistance(double metres) =>
    metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';

// ---- Evidence captured with the report -------------------------------------

/// How the reporter set the pin on the map.
enum PinSource {
  gps('their phone\'s location'),
  map('a tap on the map'),
  search('an address search');

  const PinSource(this.label);
  final String label;

  static PinSource? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// What the reporter's phone recorded while filing the report. These come
/// from the reporter's own device, so they are hints for staff, not proof.
class ReportEvidence {
  const ReportEvidence({
    this.cameraMediaCount = 0,
    this.galleryMediaCount = 0,
    this.pinSource,
    this.deviceLat,
    this.deviceLng,
    this.deviceAccuracyM,
    this.deviceFixAt,
  });

  /// Photos and videos taken inside the report form.
  final int cameraMediaCount;

  /// Photos and videos picked from the phone's gallery.
  final int galleryMediaCount;
  final PinSource? pinSource;

  /// Where the phone itself was (its last GPS fix), which can differ from
  /// the pin the reporter placed.
  final double? deviceLat;
  final double? deviceLng;
  final double? deviceAccuracyM;
  final DateTime? deviceFixAt;

  int get mediaCount => cameraMediaCount + galleryMediaCount;

  static ReportEvidence? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return ReportEvidence(
      cameraMediaCount: (raw['cameraMediaCount'] as num?)?.toInt() ?? 0,
      galleryMediaCount: (raw['galleryMediaCount'] as num?)?.toInt() ?? 0,
      pinSource: PinSource.fromName(raw['pinSource'] as String?),
      deviceLat: _double(raw['deviceLat']),
      deviceLng: _double(raw['deviceLng']),
      deviceAccuracyM: _double(raw['deviceAccuracyM']),
      deviceFixAt: _date(raw['deviceFixAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'cameraMediaCount': cameraMediaCount,
        'galleryMediaCount': galleryMediaCount,
        'pinSource': ?pinSource?.name,
        'deviceLat': ?deviceLat,
        'deviceLng': ?deviceLng,
        'deviceAccuracyM': ?deviceAccuracyM,
        if (deviceFixAt != null) 'deviceFixAt': Timestamp.fromDate(deviceFixAt!),
      };
}

/// How much a single check supports the report.
enum EvidenceLevel { supports, caution, concern, unknown }

/// One line of the desk check.
class EvidenceFlag {
  const EvidenceFlag(this.level, this.label, [this.detail]);

  final EvidenceLevel level;
  final String label;
  final String? detail;
}

/// Reporter within this distance of the pin counts as "at the location".
const double kAtLocationMetres = 300;

/// Beyond this the phone was clearly somewhere else.
const double kFarFromLocationMetres = 2000;

/// The automatic checks on a report: where the phone was, and where the
/// photos came from. [pinLat]/[pinLng] is the reported location.
List<EvidenceFlag> evidenceFlags(ReportEvidence? evidence, {double? pinLat, double? pinLng}) {
  if (evidence == null) {
    return const [
      EvidenceFlag(EvidenceLevel.unknown, 'No evidence details', 'This report was filed before these checks existed.'),
    ];
  }
  final flags = <EvidenceFlag>[];

  final distance = metresBetween(evidence.deviceLat, evidence.deviceLng, pinLat, pinLng);
  if (distance == null) {
    flags.add(const EvidenceFlag(
      EvidenceLevel.unknown,
      'Phone location not shared',
      'The reporter\'s phone gave no location, so it can\'t be compared with the pin.',
    ));
  } else {
    final accuracy = evidence.deviceAccuracyM;
    final accuracyNote = accuracy == null ? '' : ' (GPS accurate to ${accuracy.round()} m)';
    if (distance <= kAtLocationMetres) {
      flags.add(EvidenceFlag(
        EvidenceLevel.supports,
        'Reporter was at the location',
        'Their phone was ${formatDistance(distance)} from the pin$accuracyNote.',
      ));
    } else {
      flags.add(EvidenceFlag(
        distance > kFarFromLocationMetres ? EvidenceLevel.concern : EvidenceLevel.caution,
        'Reporter was ${formatDistance(distance)} from the pin',
        'The pin was set by ${evidence.pinSource?.label ?? 'hand'}$accuracyNote.',
      ));
    }
  }

  final total = evidence.mediaCount;
  if (total > 0) {
    if (evidence.galleryMediaCount == 0) {
      flags.add(EvidenceFlag(
        EvidenceLevel.supports,
        total == 1 ? 'Photo taken in the app' : 'All $total photos or videos taken in the app',
        'Taken with the camera while filing the report.',
      ));
    } else {
      flags.add(EvidenceFlag(
        EvidenceLevel.caution,
        evidence.cameraMediaCount == 0
            ? (total == 1 ? 'Photo came from the gallery' : 'All $total photos or videos came from the gallery')
            : '${evidence.galleryMediaCount} of $total photos or videos came from the gallery',
        'Gallery files could have been taken at another time or place.',
      ));
    }
  }
  return flags;
}

// ---- Reporter track record -------------------------------------------------

/// A reporter's earlier reports, as a quick trust signal.
class ReporterTrackRecord {
  const ReporterTrackRecord({this.total = 0, this.falseReports = 0, this.otherRejected = 0, this.actedOn = 0});

  /// Earlier reports, not counting the one being reviewed.
  final int total;

  /// Rejected as "Invalid or false report".
  final int falseReports;

  /// Rejected for any other reason (out of area, duplicate, ...).
  final int otherRejected;

  /// Accepted by an organization at some point.
  final int actedOn;

  /// Builds the record from the reporter's other case documents.
  factory ReporterTrackRecord.fromCases(Iterable<Map<String, dynamic>> cases) {
    var total = 0, falseReports = 0, otherRejected = 0, actedOn = 0;
    for (final data in cases) {
      total++;
      final status = RescueStatus.fromFirestoreValue(data['status'] as String?);
      if (status == RescueStatus.rejected) {
        if (data['rejectionReason'] == RejectionReason.invalidOrFalseReport.name) {
          falseReports++;
        } else {
          otherRejected++;
        }
      } else if (status != RescueStatus.pendingReview &&
          status != RescueStatus.verifying &&
          status != RescueStatus.possibleDuplicate &&
          status != RescueStatus.merged) {
        actedOn++;
      }
    }
    return ReporterTrackRecord(total: total, falseReports: falseReports, otherRejected: otherRejected, actedOn: actedOn);
  }

  EvidenceFlag get flag {
    if (total == 0) {
      return const EvidenceFlag(EvidenceLevel.unknown, 'First report from this person', 'No earlier reports to go by.');
    }
    final reports = total == 1 ? '1 earlier report' : '$total earlier reports';
    final detail = '$actedOn acted on, $falseReports rejected as false'
        '${otherRejected > 0 ? ', $otherRejected rejected for other reasons' : ''}.';
    if (falseReports >= 2 || (falseReports > 0 && actedOn == 0)) {
      return EvidenceFlag(EvidenceLevel.concern, '$reports, $falseReports rejected as false', detail);
    }
    if (falseReports > 0) return EvidenceFlag(EvidenceLevel.caution, '$reports, 1 rejected as false', detail);
    if (actedOn > 0) return EvidenceFlag(EvidenceLevel.supports, '$reports, none false', detail);
    return EvidenceFlag(EvidenceLevel.unknown, '$reports, none acted on yet', detail);
  }
}

// ---- Corroboration ---------------------------------------------------------

/// Whether anyone else backs the report up.
///
/// [otherReports]: separate reports of the same kind of animal nearby, from
/// other people (including ones already merged into this case).
/// [sightings]: community updates on this case saying the animal is there
/// or has moved. [notThere]: community updates saying no animal is there or
/// it was already rescued.
EvidenceFlag corroborationFlag({required int otherReports, required int sightings, required int notThere}) {
  String people(int n, String what) => '$n ${n == 1 ? 'person' : 'people'} $what';
  final parts = [
    if (otherReports > 0) '$otherReports other ${otherReports == 1 ? 'report' : 'reports'} nearby',
    if (sightings > 0) people(sightings, 'saw the animal'),
    if (notThere > 0) people(notThere, 'found no animal'),
  ];
  final detail = parts.isEmpty ? null : '${parts.join(', ')}.';
  final backing = otherReports + sightings;
  if (backing > 0 && notThere > 0) {
    return EvidenceFlag(EvidenceLevel.caution, 'Other people disagree about this animal', detail);
  }
  if (backing > 0) {
    return EvidenceFlag(EvidenceLevel.supports, 'Backed up by ${people(backing, 'besides the reporter')}', detail);
  }
  if (notThere > 0) {
    return EvidenceFlag(EvidenceLevel.concern, '${people(notThere, 'found')} no animal there', detail);
  }
  return const EvidenceFlag(EvidenceLevel.unknown, 'No one else has reported this animal');
}

// ---- Live proof ------------------------------------------------------------

/// Staff asked the reporter for a fresh photo or video.
class LiveProofRequest {
  const LiveProofRequest({this.requestedAt, this.requestedByName, this.note});

  final DateTime? requestedAt;
  final String? requestedByName;
  final String? note;

  static LiveProofRequest? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return LiveProofRequest(
      requestedAt: _date(raw['requestedAt']),
      requestedByName: _text(raw['requestedByName']),
      note: _text(raw['note']),
    );
  }
}

/// The reporter's answer: taken with the camera inside the app, stamped with
/// the time and the phone's location.
class LiveProof {
  const LiveProof({this.media = const [], this.submittedAt, this.lat, this.lng, this.accuracyM});

  final List<MediaRef> media;
  final DateTime? submittedAt;
  final double? lat;
  final double? lng;
  final double? accuracyM;

  static LiveProof? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return LiveProof(
      media: MediaRef.fromLists(
        List<String>.from(raw['mediaUrls'] as List? ?? const []),
        List<String>.from(raw['mediaTypes'] as List? ?? const []),
      ),
      submittedAt: _date(raw['submittedAt']),
      lat: _double(raw['lat']),
      lng: _double(raw['lng']),
      accuracyM: _double(raw['accuracyM']),
    );
  }

  /// How the proof compares with the reported location.
  EvidenceFlag flagAgainst({double? pinLat, double? pinLng}) {
    final distance = metresBetween(lat, lng, pinLat, pinLng);
    if (distance == null) {
      return const EvidenceFlag(
        EvidenceLevel.caution,
        'Live proof received, no location',
        'The reporter\'s phone gave no location with it.',
      );
    }
    if (distance <= kAtLocationMetres) {
      return EvidenceFlag(
        EvidenceLevel.supports,
        'Live proof taken at the location',
        '${formatDistance(distance)} from the pin.',
      );
    }
    return EvidenceFlag(
      distance > kFarFromLocationMetres ? EvidenceLevel.concern : EvidenceLevel.caution,
      'Live proof taken ${formatDistance(distance)} from the pin',
    );
  }
}

/// True while a request is waiting for the reporter: nothing sent back yet,
/// or the last proof is older than the latest request.
bool isLiveProofPending(LiveProofRequest? request, LiveProof? proof) {
  if (request == null) return false;
  if (proof == null || proof.submittedAt == null) return true;
  final asked = request.requestedAt;
  return asked != null && proof.submittedAt!.isBefore(asked);
}

// ---- The recorded result ---------------------------------------------------

/// What staff concluded from the desk check.
enum DeskOutcome {
  confirmedRemotely('Confirmed remotely', 'The report holds up without a visit.'),
  needsRider('Needs a rider', 'Send someone to check the location in person.'),
  couldNotConfirm('Could not confirm', 'Nothing so far shows the report is real.');

  const DeskOutcome(this.label, this.help);
  final String label;
  final String help;

  static DeskOutcome? fromName(String? name) {
    for (final o in values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// What the rider found at the location.
enum RiderOutcome {
  found('Animal found', 'The animal is at or near the reported location.'),
  notFound('Animal not found', 'No sign of the animal at the reported location.');

  const RiderOutcome(this.label, this.help);
  final String label;
  final String help;

  static RiderOutcome? fromName(String? name) {
    for (final o in values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// `cases/{id}.verification`.
class CaseVerification {
  const CaseVerification({
    this.deskOutcome,
    this.deskNote,
    this.deskByName,
    this.deskAt,
    this.riderId,
    this.riderName,
    this.riderAssignedAt,
    this.riderOutcome,
    this.riderNote,
    this.riderMedia = const [],
    this.riderRecordedAt,
    this.riderRecordedByName,
    this.riderLat,
    this.riderLng,
  });

  final DeskOutcome? deskOutcome;
  final String? deskNote;
  final String? deskByName;
  final DateTime? deskAt;

  /// The rider's account, when they use the app. A rider added by name only
  /// has a [riderName] and no id; staff record the result for them.
  final String? riderId;
  final String? riderName;
  final DateTime? riderAssignedAt;

  final RiderOutcome? riderOutcome;
  final String? riderNote;
  final List<MediaRef> riderMedia;
  final DateTime? riderRecordedAt;
  final String? riderRecordedByName;

  /// Where the rider's phone was when they recorded the result.
  final double? riderLat;
  final double? riderLng;

  bool get hasRider => riderName != null || riderId != null;

  /// A rider is out and hasn't reported back.
  bool get awaitingRider => hasRider && riderOutcome == null && deskOutcome == DeskOutcome.needsRider;

  /// The report is confirmed, from the desk or by the rider.
  bool get isConfirmed => riderOutcome == RiderOutcome.found ||
      (deskOutcome == DeskOutcome.confirmedRemotely && riderOutcome == null);

  static CaseVerification? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return CaseVerification(
      deskOutcome: DeskOutcome.fromName(raw['deskOutcome'] as String?),
      deskNote: _text(raw['deskNote']),
      deskByName: _text(raw['deskByName']),
      deskAt: _date(raw['deskAt']),
      riderId: _text(raw['riderId']),
      riderName: _text(raw['riderName']),
      riderAssignedAt: _date(raw['riderAssignedAt']),
      riderOutcome: RiderOutcome.fromName(raw['riderOutcome'] as String?),
      riderNote: _text(raw['riderNote']),
      riderMedia: MediaRef.fromLists(
        List<String>.from(raw['riderMediaUrls'] as List? ?? const []),
        List<String>.from(raw['riderMediaTypes'] as List? ?? const []),
      ),
      riderRecordedAt: _date(raw['riderRecordedAt']),
      riderRecordedByName: _text(raw['riderRecordedByName']),
      riderLat: _double(raw['riderLat']),
      riderLng: _double(raw['riderLng']),
    );
  }

  /// One-line summary for a card or a badge, or null when nothing is
  /// recorded yet.
  String? get summary {
    if (riderOutcome != null) return 'Rider: ${riderOutcome!.label.toLowerCase()}';
    if (awaitingRider) return 'Rider sent: ${riderName ?? 'unnamed'}';
    return deskOutcome?.label;
  }
}

/// Everything the verification panel reads off a case document.
class CaseVerificationState {
  const CaseVerificationState({this.evidence, this.request, this.proof, this.verification});

  final ReportEvidence? evidence;
  final LiveProofRequest? request;
  final LiveProof? proof;
  final CaseVerification? verification;

  factory CaseVerificationState.fromCase(Map<String, dynamic> data) => CaseVerificationState(
        evidence: ReportEvidence.fromMap(data['reportEvidence']),
        request: LiveProofRequest.fromMap(data['liveProofRequest']),
        proof: LiveProof.fromMap(data['liveProof']),
        verification: CaseVerification.fromMap(data['verification']),
      );

  bool get proofPending => isLiveProofPending(request, proof);

  /// True when anything about verification has been recorded.
  bool get hasRecord => request != null || proof != null || verification != null;
}
