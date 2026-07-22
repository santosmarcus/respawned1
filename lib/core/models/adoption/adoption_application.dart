import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/adoption/return_request.dart';

/// Admin-facing pipeline phase. The user-side form (adoption_process.dart)
/// already wrote a looser set of raw `status` strings before this module
/// existed — [fromFirestoreValue] maps both the new canonical values this
/// module now writes AND every legacy value already sitting in Firestore,
/// so no backfill/migration is required and old applications still resolve
/// to a sensible phase.
enum AdoptionStatus {
  pending,
  interview,
  approved,
  adopted,
  rejected,
  withdrawn;

  String get firestoreValue => switch (this) {
        AdoptionStatus.pending => 'pending',
        AdoptionStatus.interview => 'interview',
        AdoptionStatus.approved => 'approved',
        AdoptionStatus.adopted => 'adopted',
        AdoptionStatus.rejected => 'rejected',
        AdoptionStatus.withdrawn => 'withdrawn',
      };

  String get label => switch (this) {
        AdoptionStatus.pending => 'Pending',
        AdoptionStatus.interview => 'Interview',
        AdoptionStatus.approved => 'Approved',
        AdoptionStatus.adopted => 'Adopted',
        AdoptionStatus.rejected => 'Rejected',
        AdoptionStatus.withdrawn => 'Withdrawn',
      };

  static AdoptionStatus fromFirestoreValue(String? value) => switch (value) {
        'pending' || 'pending_appointment' => AdoptionStatus.pending,
        'interview' || 'under_review' => AdoptionStatus.interview,
        'approved' || 'appointment_confirmed' => AdoptionStatus.approved,
        'adopted' || 'completed' || 'return_requested' || 'return_approved' => AdoptionStatus.adopted,
        'rejected' => AdoptionStatus.rejected,
        'withdrawn' => AdoptionStatus.withdrawn,
        _ => AdoptionStatus.pending,
      };

  /// Every raw string that should be treated as this status when querying —
  /// covers both the canonical value this module now writes and whatever
  /// legacy value(s) adoption_process.dart wrote before it existed, so a
  /// `whereIn` query never misses an old application.
  List<String> get queryValues => switch (this) {
        AdoptionStatus.pending => ['pending', 'pending_appointment'],
        AdoptionStatus.interview => ['interview', 'under_review'],
        AdoptionStatus.approved => ['approved', 'appointment_confirmed'],
        AdoptionStatus.adopted => ['adopted', 'completed', 'return_requested', 'return_approved'],
        AdoptionStatus.rejected => ['rejected'],
        AdoptionStatus.withdrawn => ['withdrawn'],
      };
}

enum FitAssessmentValue {
  notReviewed,
  goodCandidate,
  needsReview,
  notRecommended;

  String get label => switch (this) {
        FitAssessmentValue.notReviewed => 'Not Reviewed',
        FitAssessmentValue.goodCandidate => 'Good Candidate',
        FitAssessmentValue.needsReview => 'Needs Review',
        FitAssessmentValue.notRecommended => 'Not Recommended',
      };

  static FitAssessmentValue fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => FitAssessmentValue.notReviewed);
}

enum AdoptionFeeStatus {
  notRequired,
  unpaid,
  pendingVerification,
  paid,
  refunded,
  failed;

  String get label => switch (this) {
        AdoptionFeeStatus.notRequired => 'Not required',
        AdoptionFeeStatus.unpaid => 'Unpaid',
        AdoptionFeeStatus.pendingVerification => 'Pending verification',
        AdoptionFeeStatus.paid => 'Paid',
        AdoptionFeeStatus.refunded => 'Refunded',
        AdoptionFeeStatus.failed => 'Failed',
      };
}

/// One `adoptions/{id}` doc — parses the SAME nested structure the
/// user-side form (adoption_process.dart) already writes
/// (personal/household/petExperience/lifestyle/uploads/agreement), plus the
/// admin-only fields this module adds on top (interview/rejection/
/// reservation/release/fit-assessment). Never a second application model —
/// this is a typed read view of the one collection both sides share.
class AdoptionApplication {
  final String id;
  final Map<String, dynamic> raw;

  // Identity
  final String adopterId;
  final String adopterName;
  final String adopterEmail;
  final String adopterPhone;
  final String? adopterAge;
  final String? adopterCity;
  final String animalId;
  final String animalName;

  final AdoptionStatus status;
  final DateTime? createdAt;

  // Appointment
  final DateTime? appointmentDate;
  final String? appointmentType;
  final String? appointmentTime;
  final DateTime? interviewCompletedAt;
  final String? interviewCompletedBy;
  final DateTime? noShowAt;

  // Fit assessment (manual only — see FitAssessmentValue doc comment)
  final FitAssessmentValue fitAssessment;
  final String? fitAssessedBy;
  final DateTime? fitAssessedAt;

  // Rejection
  final List<String> rejectionReasons;
  final String? rejectionNotes;
  final DateTime? rejectedAt;
  final String? rejectedBy;

  // Approval
  final DateTime? approvedAt;
  final String? approvedBy;

  // Reservation (mirrors the animal doc's own reservedApplicationId — see
  // AnimalRecord — kept here too so the applicant's own status stream can
  // show "reserved for you" without a second read).
  final DateTime? reservedAt;

  // Release / adoption
  final DateTime? adoptedAt;
  final String? releasedBy;
  final String? releaseNotes;
  final DateTime? scheduledReleaseDate;
  final DateTime? releasedAt;
  final bool noFollowUpsPlanned;
  final String postAdoptionStatus; // 'inProgress' | 'completed'
  final DateTime? postAdoptionCompletedAt;
  final String? postAdoptionCompletedBy;

  // Withdrawal
  final DateTime? withdrawnAt;
  final String? withdrawalReason;

  // Payment — written by the existing adoption-fee payment sheet
  // (adoption_process.dart's _ReviewPaymentSheet). Source of truth for
  // AdoptionFeeStatus; never inferred from a bare boolean.
  final String? paymentStatus;
  final double? paymentAmount;
  final String? paymentMethod;
  final DateTime? paidAt;

  const AdoptionApplication({
    required this.id,
    required this.raw,
    required this.adopterId,
    required this.adopterName,
    required this.adopterEmail,
    required this.adopterPhone,
    this.adopterAge,
    this.adopterCity,
    required this.animalId,
    required this.animalName,
    required this.status,
    this.createdAt,
    this.appointmentDate,
    this.appointmentType,
    this.appointmentTime,
    this.interviewCompletedAt,
    this.interviewCompletedBy,
    this.noShowAt,
    this.fitAssessment = FitAssessmentValue.notReviewed,
    this.fitAssessedBy,
    this.fitAssessedAt,
    this.rejectionReasons = const [],
    this.rejectionNotes,
    this.rejectedAt,
    this.rejectedBy,
    this.approvedAt,
    this.approvedBy,
    this.reservedAt,
    this.adoptedAt,
    this.releasedBy,
    this.releaseNotes,
    this.scheduledReleaseDate,
    this.releasedAt,
    this.noFollowUpsPlanned = false,
    this.postAdoptionStatus = 'inProgress',
    this.postAdoptionCompletedAt,
    this.postAdoptionCompletedBy,
    this.withdrawnAt,
    this.withdrawalReason,
    this.paymentStatus,
    this.paymentAmount,
    this.paymentMethod,
    this.paidAt,
  });

  AdoptionFeeStatus get feeStatus => switch (paymentStatus) {
        'paid' => AdoptionFeeStatus.paid,
        'pending' => AdoptionFeeStatus.pendingVerification,
        'refunded' => AdoptionFeeStatus.refunded,
        'failed' => AdoptionFeeStatus.failed,
        null => AdoptionFeeStatus.unpaid,
        _ => AdoptionFeeStatus.unpaid,
      };

  bool get isOpen => status != AdoptionStatus.rejected && status != AdoptionStatus.withdrawn && status != AdoptionStatus.adopted;

  ReturnRequest? get returnRequest => ReturnRequest.fromMap(raw['returnRequest'] as Map<String, dynamic>?);

  factory AdoptionApplication.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final personal = (data['personal'] as Map?) ?? const {};
    final payment = (data['payment'] as Map?) ?? const {};
    final fitAssessmentMap = (data['fitAssessment'] as Map?) ?? const {};

    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;

    return AdoptionApplication(
      id: doc.id,
      raw: data,
      adopterId: personal['adopterId'] as String? ?? '',
      adopterName: personal['adopterName'] as String? ?? 'Unknown Applicant',
      adopterEmail: personal['adopterEmail'] as String? ?? '',
      adopterPhone: personal['adopterPhone'] as String? ?? '',
      adopterAge: personal['adopterAge'] as String?,
      adopterCity: personal['adopterCity'] as String?,
      // Defensively stringified — some already-submitted applications may
      // still have this stored as the adoption form's local catalog int id
      // rather than a real `animals/{id}` Firestore document id. See
      // AdoptionProcess's own doc comment for the underlying disconnect.
      animalId: personal['animalId'] == null ? '' : '${personal['animalId']}',
      animalName: personal['animalName'] as String? ?? '',
      status: AdoptionStatus.fromFirestoreValue(data['status'] as String?),
      createdAt: ts(data['createdAt']),
      appointmentDate: ts(data['appointmentDate']),
      appointmentType: data['appointmentType'] as String?,
      appointmentTime: data['appointmentTime'] as String?,
      interviewCompletedAt: ts(data['interviewCompletedAt']),
      interviewCompletedBy: data['interviewCompletedBy'] as String?,
      noShowAt: ts(data['noShowAt']),
      fitAssessment: FitAssessmentValue.fromName(fitAssessmentMap['value'] as String?),
      fitAssessedBy: fitAssessmentMap['assessedBy'] as String?,
      fitAssessedAt: ts(fitAssessmentMap['assessedAt']),
      rejectionReasons: List<String>.from(data['rejectionReasons'] ?? const []),
      rejectionNotes: data['rejectionNotes'] as String?,
      rejectedAt: ts(data['rejectedAt']),
      rejectedBy: data['rejectedBy'] as String?,
      approvedAt: ts(data['approvedAt']),
      approvedBy: data['approvedBy'] as String?,
      reservedAt: ts(data['reservedAt']),
      adoptedAt: ts(data['adoptedAt']),
      releasedBy: data['releasedBy'] as String?,
      releaseNotes: data['releaseNotes'] as String?,
      scheduledReleaseDate: ts(data['scheduledReleaseDate']),
      releasedAt: ts(data['releasedAt']),
      noFollowUpsPlanned: data['noFollowUpsPlanned'] as bool? ?? false,
      postAdoptionStatus: data['postAdoptionStatus'] as String? ?? 'inProgress',
      postAdoptionCompletedAt: ts(data['postAdoptionCompletedAt']),
      postAdoptionCompletedBy: data['postAdoptionCompletedBy'] as String?,
      withdrawnAt: ts(data['withdrawnAt']),
      withdrawalReason: data['withdrawalReason'] as String?,
      paymentStatus: payment['status'] as String?,
      paymentAmount: (payment['amount'] as num?)?.toDouble(),
      paymentMethod: payment['method'] as String?,
      paidAt: ts(payment['paidAt']),
    );
  }
}
