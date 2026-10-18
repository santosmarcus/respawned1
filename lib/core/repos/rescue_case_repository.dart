import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_report.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';

import 'package:respawnd1/core/repos/rescue_case/case_duplicate_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/case_expense_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/case_intake_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/case_referral_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/case_status_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/clinic_assignment_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_query_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/repos/rescue_case/transport_assignment_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/treatment_log_repository.dart';

/// Firestore access for the admin rescue module. Reads/writes the existing
/// `cases` collection (shared with the reporter and pet-transporter apps —
/// see the doc comment on [RescueCase]) plus its new
/// `reports` / `referrals` / `activityLogs` subcollections.
///
/// Every write here is a partial `update()`/`set(..., merge: true)` or a
/// transaction — never a full-document overwrite — so fields owned by
/// other features are never clobbered.
///
/// This class is now a thin facade: each method delegates to a focused,
/// domain-specific repository under `core/repos/rescue_case/`, all sharing
/// one [RescueCaseStore]. Existing call sites keep using this class
/// unchanged; new code may use the domain repositories directly via the
/// public fields below.
class RescueCaseRepository {
  RescueCaseRepository({FirebaseFirestore? firestore})
    : this._withStore(RescueCaseStore(firestore ?? FirebaseFirestore.instance));

  RescueCaseRepository._withStore(RescueCaseStore store)
    : this._withTransport(store, TransportAssignmentRepository(store));

  RescueCaseRepository._withTransport(RescueCaseStore store, this.transport)
    : _store = store,
      queries = RescueCaseQueryRepository(store),
      status = CaseStatusRepository(store, transport),
      intake = CaseIntakeRepository(store, transport),
      duplicates = CaseDuplicateRepository(store),
      referrals = CaseReferralRepository(store),
      clinics = ClinicAssignmentRepository(store),
      treatment = TreatmentLogRepository(store),
      expenses = CaseExpenseRepository(store);

  final RescueCaseStore _store;
  final RescueCaseQueryRepository queries;
  final CaseStatusRepository status;
  final CaseIntakeRepository intake;
  final CaseDuplicateRepository duplicates;
  final CaseReferralRepository referrals;
  final ClinicAssignmentRepository clinics;
  final TransportAssignmentRepository transport;
  final TreatmentLogRepository treatment;
  final CaseExpenseRepository expenses;

  /// Delegates to [RescueCaseQueryRepository.streamCasesByStatuses].
  Stream<List<RescueCase>> streamCasesByStatuses(List<RescueStatus> statuses) =>
      queries.streamCasesByStatuses(statuses);

  /// Delegates to [CaseIntakeRepository.createAdmissionCase].
  Future<String> createAdmissionCase({
    required String sourceAnimalRecordId,
    required String animalName,
    required String species,
    required String admissionReason,
    String? admissionNotes,
    required double lat,
    required double lng,
    String? shelterAddress,
    required String actorUid,
    required String actorName,
  }) => intake.createAdmissionCase(
    sourceAnimalRecordId: sourceAnimalRecordId,
    animalName: animalName,
    species: species,
    admissionReason: admissionReason,
    admissionNotes: admissionNotes,
    lat: lat,
    lng: lng,
    shelterAddress: shelterAddress,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseIntakeRepository.createReturnIntakeCase].
  Future<String> createReturnIntakeCase({
    required String sourceAnimalRecordId,
    required String animalName,
    required String species,
    required String returnRequestId,
    required String previousAdoptionId,
    required String adopterName,
    required String returnReason,
    String? returnExplanation,
    List<String> returnPhotos = const [],
    required DateTime retrievedAt,
    required double lat,
    required double lng,
    String? shelterAddress,
    required String actorUid,
    required String actorName,
  }) => intake.createReturnIntakeCase(
    sourceAnimalRecordId: sourceAnimalRecordId,
    animalName: animalName,
    species: species,
    returnRequestId: returnRequestId,
    previousAdoptionId: previousAdoptionId,
    adopterName: adopterName,
    returnReason: returnReason,
    returnExplanation: returnExplanation,
    returnPhotos: returnPhotos,
    retrievedAt: retrievedAt,
    lat: lat,
    lng: lng,
    shelterAddress: shelterAddress,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [RescueCaseQueryRepository.streamCase].
  Stream<RescueCase?> streamCase(String caseId) => queries.streamCase(caseId);

  /// Delegates to [TreatmentLogRepository.streamTreatmentLogs].
  Stream<List<TreatmentLogEntry>> streamTreatmentLogs(String caseId) =>
      treatment.streamTreatmentLogs(caseId);

  /// Delegates to [CaseExpenseRepository.streamExpenses].
  Stream<List<Expense>> streamExpenses(String caseId) =>
      expenses.streamExpenses(caseId);

  /// Delegates to [RescueCaseQueryRepository.streamCompletedAnimalRecordIndexes].
  Stream<Set<int>> streamCompletedAnimalRecordIndexes(String caseId) =>
      queries.streamCompletedAnimalRecordIndexes(caseId);

  /// Delegates to [RescueCaseQueryRepository.streamReports].
  Stream<List<RescueReport>> streamReports(String caseId) =>
      queries.streamReports(caseId);

  /// Delegates to [CaseReferralRepository.streamReferrals].
  Stream<List<Referral>> streamReferrals(String caseId) =>
      referrals.streamReferrals(caseId);

  /// Delegates to [RescueCaseQueryRepository.streamActivityLogs].
  Stream<List<ActivityLogEntry>> streamActivityLogs(String caseId) =>
      queries.streamActivityLogs(caseId);

  /// Delegates to [RescueCaseQueryRepository.streamCommunityReports].
  Stream<List<CommunityReport>> streamCommunityReports(String caseId) =>
      queries.streamCommunityReports(caseId);

  /// Delegates to [CaseStatusRepository.approveLocationUpdate].
  Future<void> approveLocationUpdate({
    required String caseId,
    required String reportId,
    required String actorUid,
    required String actorName,
  }) => status.approveLocationUpdate(
    caseId: caseId,
    reportId: reportId,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseStatusRepository.rejectLocationUpdate].
  Future<void> rejectLocationUpdate({
    required String caseId,
    required String reportId,
    required String actorUid,
    required String actorName,
    String? reason,
  }) => status.rejectLocationUpdate(
    caseId: caseId,
    reportId: reportId,
    actorUid: actorUid,
    actorName: actorName,
    reason: reason,
  );

  /// Delegates to [TransportAssignmentRepository.streamPetTransporters].
  Stream<List<PetTransporter>> streamPetTransporters() =>
      transport.streamPetTransporters();

  /// Delegates to [TransportAssignmentRepository.streamRescueVolunteers].
  Stream<List<PetTransporter>> streamRescueVolunteers() =>
      transport.streamRescueVolunteers();

  /// Delegates to [TransportAssignmentRepository.resolveTransporterProfile].
  Future<TransporterProfile> resolveTransporterProfile({
    required String uid,
    required String fallbackName,
    required String type,
    required bool isDemo,
  }) => transport.resolveTransporterProfile(
    uid: uid,
    fallbackName: fallbackName,
    type: type,
    isDemo: isDemo,
  );

  /// Delegates to [TransportAssignmentRepository.streamLatestAssignment].
  Stream<TransportAssignment?> streamLatestAssignment(String caseId) =>
      transport.streamLatestAssignment(caseId);

  /// Delegates to [TransportAssignmentRepository.streamActiveAssignmentsByRider].
  Stream<Map<String, TransportAssignmentStatus>>
  streamActiveAssignmentsByRider() =>
      transport.streamActiveAssignmentsByRider();

  /// Delegates to [TransportAssignmentRepository.streamStalePendingAssignments].
  Stream<List<TransportAssignment>> streamStalePendingAssignments() =>
      transport.streamStalePendingAssignments();

  /// Delegates to [CaseDuplicateRepository.findPossibleDuplicates].
  Future<List<RescueCase>> findPossibleDuplicates(
    RescueCase source, {
    double radiusKm = 1.0,
    int limit = 20,
  }) => duplicates.findPossibleDuplicates(
    source,
    radiusKm: radiusKm,
    limit: limit,
  );

  /// Delegates to [CaseDuplicateRepository.distanceKmBetween].
  double distanceKmBetween(RescueCase a, RescueCase b) =>
      duplicates.distanceKmBetween(a, b);

  /// Delegates to [CaseStatusRepository.acceptCase].
  Future<void> acceptCase({
    required String caseId,
    required String actorUid,
    required String actorName,
    bool openForTransfer = false,
  }) => status.acceptCase(
    caseId: caseId,
    actorUid: actorUid,
    actorName: actorName,
    openForTransfer: openForTransfer,
  );

  /// Delegates to [CaseStatusRepository.rejectCase].
  Future<void> rejectCase({
    required String caseId,
    required RejectionReason reason,
    String? otherText,
    required String actorUid,
    required String actorName,
  }) => status.rejectCase(
    caseId: caseId,
    reason: reason,
    otherText: otherText,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseDuplicateRepository.flagPossibleDuplicate].
  Future<void> flagPossibleDuplicate({
    required String caseId,
    required String duplicateOfCaseId,
    required String actorUid,
    required String actorName,
  }) => duplicates.flagPossibleDuplicate(
    caseId: caseId,
    duplicateOfCaseId: duplicateOfCaseId,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseDuplicateRepository.keepSeparate].
  Future<void> keepSeparate({
    required String caseId,
    required String actorUid,
    required String actorName,
    List<String> dismissedCandidateIds = const [],
  }) => duplicates.keepSeparate(
    caseId: caseId,
    actorUid: actorUid,
    actorName: actorName,
    dismissedCandidateIds: dismissedCandidateIds,
  );

  /// Delegates to [CaseDuplicateRepository.mergeDuplicate].
  Future<void> mergeDuplicate({
    required String primaryCaseId,
    required String duplicateCaseId,
    required String actorUid,
    required String actorName,
  }) => duplicates.mergeDuplicate(
    primaryCaseId: primaryCaseId,
    duplicateCaseId: duplicateCaseId,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseStatusRepository.updateOwnershipInfo].
  Future<void> updateOwnershipInfo({
    required String caseId,
    required String
    ownershipStatus, // 'Unknown' | 'No known owner' | 'Possible owner' | 'Owner identified'
    String?
    ownedAnimalCategory, // 'Lost animal' | 'Neglect concern' | 'Abandonment concern' | 'Other'
    String? ownerName,
    String? ownerContact,
    String? ownershipNotes,
    required String actorUid,
    required String actorName,
  }) => status.updateOwnershipInfo(
    caseId: caseId,
    ownershipStatus: ownershipStatus,
    ownedAnimalCategory: ownedAnimalCategory,
    ownerName: ownerName,
    ownerContact: ownerContact,
    ownershipNotes: ownershipNotes,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseReferralRepository.referToOrganization].
  Future<String> referToOrganization({
    required String caseId,
    required String targetOrgId,
    required String targetOrgName,
    String? note,
    required String actorUid,
    required String actorName,
  }) => referrals.referToOrganization(
    caseId: caseId,
    targetOrgId: targetOrgId,
    targetOrgName: targetOrgName,
    note: note,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseReferralRepository.referToLgu].
  Future<String> referToLgu({
    required String caseId,
    required String barangay,
    required LguReferralReason reason,
    required String explanation,
    bool attachReportMedia = true,
    required String actorUid,
    required String actorName,
  }) => referrals.referToLgu(
    caseId: caseId,
    barangay: barangay,
    reason: reason,
    explanation: explanation,
    attachReportMedia: attachReportMedia,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseReferralRepository.referToVolunteer].
  Future<String> referToVolunteer({
    required String caseId,
    String? note,
    required String actorUid,
    required String actorName,
  }) => referrals.referToVolunteer(
    caseId: caseId,
    note: note,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [ClinicAssignmentRepository.assignClinic].
  Future<void> assignClinic({
    required String caseId,
    required String clinicName,
    String? clinicAddress,
    String? clinicPlaceId,
    double? clinicLat,
    double? clinicLng,
    String? clinicPhone,
    required String actorUid,
    required String actorName,
    String? availabilityStatus,
    bool closedWarningAcknowledged = false,
  }) => clinics.assignClinic(
    caseId: caseId,
    clinicName: clinicName,
    clinicAddress: clinicAddress,
    clinicPlaceId: clinicPlaceId,
    clinicLat: clinicLat,
    clinicLng: clinicLng,
    clinicPhone: clinicPhone,
    actorUid: actorUid,
    actorName: actorName,
    availabilityStatus: availabilityStatus,
    closedWarningAcknowledged: closedWarningAcknowledged,
  );

  /// Delegates to [ClinicAssignmentRepository.changeClinic].
  Future<void> changeClinic({
    required String caseId,
    required String previousClinicName,
    required String clinicName,
    String? clinicAddress,
    String? clinicPlaceId,
    double? clinicLat,
    double? clinicLng,
    String? clinicPhone,
    required String actorUid,
    required String actorName,
    String? availabilityStatus,
    bool closedWarningAcknowledged = false,
  }) => clinics.changeClinic(
    caseId: caseId,
    previousClinicName: previousClinicName,
    clinicName: clinicName,
    clinicAddress: clinicAddress,
    clinicPlaceId: clinicPlaceId,
    clinicLat: clinicLat,
    clinicLng: clinicLng,
    clinicPhone: clinicPhone,
    actorUid: actorUid,
    actorName: actorName,
    availabilityStatus: availabilityStatus,
    closedWarningAcknowledged: closedWarningAcknowledged,
  );

  /// Delegates to [TransportAssignmentRepository.createAssignmentOffer].
  Future<String> createAssignmentOffer({
    required String caseId,
    required String riderId,
    required String riderName,
    required String riderType,
    bool isDemo = false,
    bool allowReassign = false,
    String? vehicle,
    String? plate,
  }) => transport.createAssignmentOffer(
    caseId: caseId,
    riderId: riderId,
    riderName: riderName,
    riderType: riderType,
    isDemo: isDemo,
    allowReassign: allowReassign,
    vehicle: vehicle,
    plate: plate,
  );

  /// Delegates to [TransportAssignmentRepository.acceptAssignment].
  Future<void> acceptAssignment({
    required String caseId,
    required String assignmentId,
    required String riderId,
    required String riderName,
    required String riderVehicle,
    required String riderPlate,
  }) => transport.acceptAssignment(
    caseId: caseId,
    assignmentId: assignmentId,
    riderId: riderId,
    riderName: riderName,
    riderVehicle: riderVehicle,
    riderPlate: riderPlate,
  );

  /// Delegates to [TransportAssignmentRepository.rejectAssignment].
  Future<void> rejectAssignment({
    required String caseId,
    required String assignmentId,
    required String reason,
  }) => transport.rejectAssignment(
    caseId: caseId,
    assignmentId: assignmentId,
    reason: reason,
  );

  /// Delegates to [TransportAssignmentRepository.cancelAssignment].
  Future<void> cancelAssignment({
    required String caseId,
    required String assignmentId,
    String? reason,
  }) => transport.cancelAssignment(
    caseId: caseId,
    assignmentId: assignmentId,
    reason: reason,
  );

  /// Delegates to [TransportAssignmentRepository.reconcileStaleOffer].
  Future<void> reconcileStaleOffer({
    required String caseId,
    required String assignmentId,
  }) =>
      transport.reconcileStaleOffer(caseId: caseId, assignmentId: assignmentId);

  /// Delegates to [TransportAssignmentRepository.completeAssignment].
  Future<void> completeAssignment({
    required String caseId,
    required String assignmentId,
  }) =>
      transport.completeAssignment(caseId: caseId, assignmentId: assignmentId);

  /// Delegates to [TransportAssignmentRepository.resumeAssignmentAfterSafetyReport].
  Future<void> resumeAssignmentAfterSafetyReport({
    required String caseId,
    required String actorUid,
    required String actorName,
  }) => transport.resumeAssignmentAfterSafetyReport(
    caseId: caseId,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [TransportAssignmentRepository.addSafetyResponseNote].
  Future<void> addSafetyResponseNote({
    required String caseId,
    required String note,
    required String actorUid,
    required String actorName,
  }) => transport.addSafetyResponseNote(
    caseId: caseId,
    note: note,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseStatusRepository.reportAnimalDeath].
  Future<void> reportAnimalDeath({
    required String caseId,
    required int animalIndex,
    required String reason,
    required String confirmedBy,
    String? notes,
    String? photoUrl,
  }) => status.reportAnimalDeath(
    caseId: caseId,
    animalIndex: animalIndex,
    reason: reason,
    confirmedBy: confirmedBy,
    notes: notes,
    photoUrl: photoUrl,
  );

  /// Delegates to [CaseStatusRepository.updateCaseLocation].
  Future<void> updateCaseLocation({
    required String caseId,
    required double lat,
    required double lng,
    String? address,
    required String actorUid,
    required String actorName,
  }) => status.updateCaseLocation(
    caseId: caseId,
    lat: lat,
    lng: lng,
    address: address,
    actorUid: actorUid,
    actorName: actorName,
  );

  /// Delegates to [CaseStatusRepository.closeCase].
  Future<bool> closeCase({
    required String caseId,
    required ClosureReason reason,
    required String details,
    required String actorUid,
    required String actorName,
    String? actorRole,
    String? organizationId,
    String? lastKnownLocation,
    String? clinicUnavailableDetails,
    String? serviceTypeNeeded,
    List<int>? animalIndexes,
  }) => status.closeCase(
    caseId: caseId,
    reason: reason,
    details: details,
    actorUid: actorUid,
    actorName: actorName,
    actorRole: actorRole,
    organizationId: organizationId,
    lastKnownLocation: lastKnownLocation,
    clinicUnavailableDetails: clinicUnavailableDetails,
    serviceTypeNeeded: serviceTypeNeeded,
    animalIndexes: animalIndexes,
  );

  /// Delegates to [TreatmentLogRepository.newTreatmentLogId].
  String newTreatmentLogId(String caseId) =>
      treatment.newTreatmentLogId(caseId);

  /// Delegates to [TreatmentLogRepository.addTreatmentLog].
  Future<void> addTreatmentLog({
    required String caseId,
    required TreatmentLogEntry entry,
    String? logId,
  }) => treatment.addTreatmentLog(caseId: caseId, entry: entry, logId: logId);

  /// Delegates to [CaseIntakeRepository.transferAnimal].
  Future<void> transferAnimal({
    required String caseId,
    required String targetType,
    required String targetName,
    String? targetContact,
    String? targetAddress,
    String? targetOrganizationId,
    String? targetClinicPlaceId,
    double? targetLat,
    double? targetLng,
    required String reason,
    DateTime? transferDate,
    String? notes,
    required String actorUid,
    required String actorName,
    List<int>? animalIndexes,
  }) => intake.transferAnimal(
    caseId: caseId,
    targetType: targetType,
    targetName: targetName,
    targetContact: targetContact,
    targetAddress: targetAddress,
    targetOrganizationId: targetOrganizationId,
    targetClinicPlaceId: targetClinicPlaceId,
    targetLat: targetLat,
    targetLng: targetLng,
    reason: reason,
    transferDate: transferDate,
    notes: notes,
    actorUid: actorUid,
    actorName: actorName,
    animalIndexes: animalIndexes,
  );

  /// Delegates to [CaseIntakeRepository.releaseToReporter].
  Future<void> releaseToReporter({
    required String caseId,
    required String reporterId,
    required String reporterName,
    String? notes,
    required String actorUid,
    required String actorName,
    List<int>? animalIndexes,
  }) => intake.releaseToReporter(
    caseId: caseId,
    reporterId: reporterId,
    reporterName: reporterName,
    notes: notes,
    actorUid: actorUid,
    actorName: actorName,
    animalIndexes: animalIndexes,
  );

  /// Delegates to [CaseIntakeRepository.assignIntakeAction].
  Future<void> assignIntakeAction({
    required String caseId,
    required List<int> animalIndexes,
  }) => intake.assignIntakeAction(caseId: caseId, animalIndexes: animalIndexes);

  /// Delegates to [CaseIntakeRepository.completeIntakeForAnimals].
  Future<void> completeIntakeForAnimals({
    required String caseId,
    required List<int> animalIndexes,
  }) => intake.completeIntakeForAnimals(
    caseId: caseId,
    animalIndexes: animalIndexes,
  );

  /// Delegates to [RescueCaseQueryRepository.streamCasesByActiveStage].
  Stream<List<RescueCase>> streamCasesByActiveStage(String stage) =>
      queries.streamCasesByActiveStage(stage);

  /// Delegates to [CaseStatusRepository.closeDeceasedCase].
  Future<void> closeDeceasedCase({required String caseId}) =>
      status.closeDeceasedCase(caseId: caseId);

  /// Delegates to [CaseIntakeRepository.confirmIntake].
  Future<void> confirmIntake({
    required String caseId,
    required String destinationName,
    String? destinationAddress,
    String? destinationPlaceId,
    double? destinationLat,
    double? destinationLng,
    String? transporterUid,
    String? transporterName,
    String? transporterType,
    String? transporterVehicle,
    String? transporterPlate,
    bool isDemoTransporter = false,
  }) => intake.confirmIntake(
    caseId: caseId,
    destinationName: destinationName,
    destinationAddress: destinationAddress,
    destinationPlaceId: destinationPlaceId,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
    transporterUid: transporterUid,
    transporterName: transporterName,
    transporterType: transporterType,
    transporterVehicle: transporterVehicle,
    transporterPlate: transporterPlate,
    isDemoTransporter: isDemoTransporter,
  );

  /// Delegates to [CaseIntakeRepository.confirmAnimalReceived].
  Future<void> confirmAnimalReceived({
    required String caseId,
    String? currentAssignmentId,
    List<int>? animalIndexes,
  }) => intake.confirmAnimalReceived(
    caseId: caseId,
    currentAssignmentId: currentAssignmentId,
    animalIndexes: animalIndexes,
  );

  /// Delegates to [CaseIntakeRepository.startQuarantine].
  Future<void> startQuarantine({
    required String caseId,
    required int durationDays,
  }) => intake.startQuarantine(caseId: caseId, durationDays: durationDays);

  /// Delegates to [CaseIntakeRepository.endQuarantine].
  Future<void> endQuarantine({required String caseId, String? reason}) =>
      intake.endQuarantine(caseId: caseId, reason: reason);

  /// Delegates to [CaseIntakeRepository.skipQuarantine].
  Future<void> skipQuarantine({required String caseId}) =>
      intake.skipQuarantine(caseId: caseId);

  /// Delegates to [CaseIntakeRepository.checkAndCompleteQuarantineIfDue].
  Future<void> checkAndCompleteQuarantineIfDue(RescueCase c) =>
      intake.checkAndCompleteQuarantineIfDue(c);

  /// Delegates to [CaseIntakeRepository.checkAndCompleteIntakeIfDue].
  Future<void> checkAndCompleteIntakeIfDue(
    RescueCase c, {
    required int totalAnimalsExpected,
    required int completedCount,
  }) => intake.checkAndCompleteIntakeIfDue(
    c,
    totalAnimalsExpected: totalAnimalsExpected,
    completedCount: completedCount,
  );

  /// Delegates to [CaseExpenseRepository.addExpense].
  Future<void> addExpense({required String caseId, required Expense expense}) =>
      expenses.addExpense(caseId: caseId, expense: expense);

  /// Delegates to [CaseExpenseRepository.updateExpense].
  Future<void> updateExpense({
    required String caseId,
    required Expense expense,
  }) => expenses.updateExpense(caseId: caseId, expense: expense);

  /// Delegates to [CaseExpenseRepository.deleteExpense].
  Future<void> deleteExpense({
    required String caseId,
    required String expenseId,
  }) => expenses.deleteExpense(caseId: caseId, expenseId: expenseId);

  /// Delegates to [RescueCaseStore.addActivityLog].
  Future<void> addActivityLog({
    required String caseId,
    required String action,
    String? actorUid,
    String? actorName,
    String? actorRole,
    Map<String, dynamic>? details,
  }) => _store.addActivityLog(
    caseId: caseId,
    action: action,
    actorUid: actorUid,
    actorName: actorName,
    actorRole: actorRole,
    details: details,
  );
}
