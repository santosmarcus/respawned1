import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';

/// Firestore access for the `animals` collection and its
/// `medicalEpisodes`/`vaccinations` subcollections — the first dedicated
/// repository for this collection (previously every animal-record write was
/// inline in the page itself). Composes [RescueCaseRepository] for the one
/// action that also touches `cases` (admitting an animal for medical care)
/// rather than duplicating case-creation logic here.
class AnimalRecordRepository {
  AnimalRecordRepository({FirebaseFirestore? firestore, RescueCaseRepository? caseRepository})
      : _db = firestore ?? FirebaseFirestore.instance,
        _caseRepo = caseRepository ?? RescueCaseRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final RescueCaseRepository _caseRepo;

  CollectionReference<Map<String, dynamic>> get _animals => _db.collection('animals');
  DocumentReference<Map<String, dynamic>> _animalDoc(String animalId) => _animals.doc(animalId);
  CollectionReference<Map<String, dynamic>> _episodesOf(String animalId) =>
      _animalDoc(animalId).collection('medicalEpisodes');
  CollectionReference<Map<String, dynamic>> _vaccinationsOf(String animalId) =>
      _animalDoc(animalId).collection('vaccinations');
  CollectionReference<Map<String, dynamic>> _managementLogsOf(String animalId) =>
      _animalDoc(animalId).collection('managementLogs');

  // ---- Reads --------------------------------------------------------

  Stream<AnimalRecord?> streamAnimalRecord(String animalId) {
    return _animalDoc(animalId).snapshots().map((doc) => doc.exists ? AnimalRecord.fromFirestore(doc) : null);
  }

  /// Every animal record — the list page applies search/filter/sort
  /// entirely client-side on top of this (same pattern
  /// OrganizationDirectoryRepository.search already uses), since Firestore
  /// can't combine free-text search across this many fields with the full
  /// range of sort options in one query. Fine at shelter-record scale.
  ///
  /// Parses each document individually inside its own try/catch —
  /// AnimalRecord.fromFirestore already has its own internal fallback for a
  /// field-level parse failure, but this is the outer safety net for
  /// anything that still slips through (a genuinely corrupt document, a
  /// future field this model doesn't know about yet, ...): one bad
  /// document is logged and skipped, it never takes the whole list down
  /// with a single throw the way a bare `.map()` would.
  Stream<List<AnimalRecord>> streamAllAnimalRecords() {
    return _animals.snapshots().map((snap) {
      final records = <AnimalRecord>[];
      for (final doc in snap.docs) {
        try {
          records.add(AnimalRecord.fromFirestore(doc));
        } catch (e) {
          debugPrint('[AnimalRecordRepository] Skipping unparseable animal record ${doc.id}: $e');
        }
      }
      return records;
    });
  }

  /// Every record created from one source rescue/intake case, ordered by
  /// [AnimalRecord.sourceAnimalIndex] — powers "View Animal Record(s)" from
  /// Intake Details (see AnimalRecordsFlowPage). Same per-doc isolation as
  /// [streamAllAnimalRecords].
  Stream<List<AnimalRecord>> streamRecordsForCase(String caseId) {
    return _animals.where('linkedCaseId', isEqualTo: caseId).snapshots().map((snap) {
      final records = <AnimalRecord>[];
      for (final doc in snap.docs) {
        try {
          records.add(AnimalRecord.fromFirestore(doc));
        } catch (e) {
          debugPrint('[AnimalRecordRepository] Skipping unparseable animal record ${doc.id}: $e');
        }
      }
      records.sort((a, b) => (a.sourceAnimalIndex ?? 0).compareTo(b.sourceAnimalIndex ?? 0));
      return records;
    });
  }

  Stream<List<MedicalEpisode>> streamMedicalEpisodes(String animalId) {
    return _episodesOf(animalId).orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => MedicalEpisode.fromFirestore(d, animalId)).toList(),
        );
  }

  Stream<List<VaccinationRecord>> streamVaccinations(String animalId) {
    return _vaccinationsOf(animalId).orderBy('dateAdministered', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => VaccinationRecord.fromFirestore(d, animalId)).toList(),
        );
  }

  /// Every Management-tab action (archive, transfer, deceased, adopted)
  /// appends here — this is what both the Management tab's own "View Logs"
  /// action and the header overflow menu's "View Logs" read, so there's one
  /// audit trail, not two.
  Stream<List<Map<String, dynamic>>> streamManagementLogs(String animalId) {
    return _managementLogsOf(animalId).orderBy('timestamp', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  Future<void> _addManagementLog({
    required String animalId,
    required String action,
    String? details,
  }) async {
    await _managementLogsOf(animalId).add({
      'action': action,
      if (details != null && details.isNotEmpty) 'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ---- Admission (Medical tab -> Admit Animal) -----------------------

  /// Opens a new medical episode for an animal already in the
  /// organization's records: creates the `cases` doc directly in the
  /// "needs a clinic" state (see RescueCaseRepository.createAdmissionCase),
  /// records a lightweight `medicalEpisodes` reference doc, and points the
  /// animal record's `currentCaseId` at it so the Medical tab knows what to
  /// watch. Returns the new case id — the caller opens showSelectClinicSheet
  /// with it immediately after.
  Future<String> admitAnimal({
    required AnimalRecord animal,
    required String reason,
    String? notes,
    required double shelterLat,
    required double shelterLng,
    String? shelterAddress,
    required String actorUid,
    required String actorName,
  }) async {
    final caseId = await _caseRepo.createAdmissionCase(
      sourceAnimalRecordId: animal.id,
      animalName: animal.name.isNotEmpty ? animal.name : animal.species,
      species: animal.species,
      admissionReason: reason,
      admissionNotes: notes,
      lat: shelterLat,
      lng: shelterLng,
      shelterAddress: shelterAddress,
      actorUid: actorUid,
      actorName: actorName,
    );

    final episode = MedicalEpisode(
      id: '',
      animalId: animal.id,
      sourceCaseId: caseId,
      reason: AdmissionReason.fromName(reason),
      notes: notes,
      createdBy: actorName,
    );
    await _episodesOf(animal.id).add(episode.toFirestore());
    await _animalDoc(animal.id).update({'currentCaseId': caseId, 'updatedAt': FieldValue.serverTimestamp()});

    return caseId;
  }

  // ---- Vaccinations ---------------------------------------------------

  /// Saves the record, then refreshes the animal doc's derived
  /// `vaccinated`/`vaccinesGiven` summary (never the reverse — those flat
  /// fields are always computed from records here, never hand-edited).
  Future<void> addVaccination({required String animalId, required VaccinationRecord record}) async {
    await _vaccinationsOf(animalId).add(record.toFirestore());
    await _refreshVaccineSummary(animalId);
  }

  Future<void> _refreshVaccineSummary(String animalId) async {
    final snap = await _vaccinationsOf(animalId).get();
    final records = snap.docs.map((d) => VaccinationRecord.fromFirestore(d, animalId)).toList();
    final names = records.map((r) => r.vaccineName).toSet().toList();
    // "Vaccinated" summary: true once at least one vaccine is on file and
    // none of them are overdue — a coarse derived flag, not the source of
    // truth (see VaccinationRecord.status for the real per-vaccine state).
    final anyOverdue = records.any((r) => r.status == VaccineStatus.overdue);
    await _animalDoc(animalId).update({
      'vaccinated': records.isNotEmpty && !anyOverdue,
      'vaccinesGiven': names,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Health / profile editing ----------------------------------------

  /// Partial update for the health-details fields only — used by the
  /// health-edit sheet. Never touches vaccinated (derived from vaccination
  /// records, see above) and never overwrites a field the caller didn't
  /// include, so a treatment-update flow that only wants to change one
  /// field (once that integration exists — see the module's TODO) can do
  /// so without clobbering the rest.
  Future<void> updateHealthDetails({
    required String animalId,
    bool? spayedNeutered,
    bool? dewormed,
    String? allergies,
    String? chronicConditions,
    String? currentMedications,
    DateTime? lastVetCheckup,
    double? weightKg,
    String? bodyCondition,
    String? microchipStatus,
  }) async {
    await _animalDoc(animalId).update({
      if (spayedNeutered != null) 'spayedNeutered': spayedNeutered,
      if (dewormed != null) 'dewormed': dewormed,
      if (allergies != null) 'allergies': allergies,
      if (chronicConditions != null) 'chronicConditions': chronicConditions,
      if (currentMedications != null) 'currentMedications': currentMedications,
      if (lastVetCheckup != null) 'lastVetCheckup': Timestamp.fromDate(lastVetCheckup),
      if (weightKg != null) 'weightKg': weightKg,
      if (bodyCondition != null) 'bodyCondition': bodyCondition,
      if (microchipStatus != null) 'microchipStatus': microchipStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProfile({required String animalId, required Map<String, dynamic> fields}) async {
    await _animalDoc(animalId).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ---- Management tab ---------------------------------------------------

  Future<void> setArchived({required String animalId, required bool archived}) async {
    await _animalDoc(animalId).update({'archived': archived, 'updatedAt': FieldValue.serverTimestamp()});
    await _addManagementLog(animalId: animalId, action: archived ? 'Archived' : 'Unarchived');
  }

  Future<void> markDeceased({
    required String animalId,
    DateTime? date,
    String? cause,
    String? notes,
  }) async {
    await _animalDoc(animalId).update({
      'adoptionStatus': 'deceased',
      'status': 'deceased',
      'deceasedAt': date != null ? Timestamp.fromDate(date) : FieldValue.serverTimestamp(),
      if (cause != null && cause.isNotEmpty) 'deceasedCause': cause,
      if (notes != null && notes.isNotEmpty) 'deceasedNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(
        animalId: animalId, action: 'Marked deceased', details: cause == null || cause.isEmpty ? null : 'Cause: $cause');
  }

  /// Only ever called after the existing adoption-application workflow has
  /// actually approved an application for this animal — this method itself
  /// performs no such check (that belongs to the adoption module, out of
  /// scope here); the Management tab UI is what's responsible for only
  /// exposing this action when that's true.
  Future<void> markAdopted({required String animalId}) async {
    await _animalDoc(animalId).update({
      'adoptionStatus': 'adopted',
      'status': 'adopted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(animalId: animalId, action: 'Marked adopted');
  }

  /// The "un-adopt" transition — called once an approved return has actually
  /// been retrieved (see AdoptionApplicationRepository.confirmAnimalRetrieved
  /// / the Return Details "Proceed to Intake" action). Never clears
  /// adoptedByUserId/adoptedApplicationId/adoptedAt: those stay as the
  /// historical record of the completed adoption (see AnimalRecord's own
  /// doc comment). adoptionStatus goes to 'not_ready' rather than back to
  /// 'adoptable' so the animal isn't publicly re-listed without an
  /// organization health/behavior review first (spec §22).
  Future<void> returnFromAdoption({
    required String animalId,
    required String returnRequestId,
    required String previousAdoptionId,
  }) async {
    await _animalDoc(animalId).update({
      'adoptionStatus': 'not_ready',
      'status': 'intake',
      'currentStatus': 'returned',
      'latestReturnRequestId': returnRequestId,
      'previousAdoptionId': previousAdoptionId,
      'returnedAt': FieldValue.serverTimestamp(),
      'reservedForUserId': FieldValue.delete(),
      'reservedApplicationId': FieldValue.delete(),
      'reservedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(animalId: animalId, action: 'Returned by adopter — entered Intake for review');
  }

  Future<void> transferAnimal({
    required String animalId,
    required String targetType, // 'organization' | 'volunteer'
    required String targetName,
    String? targetOrgId,
    String? notes,
  }) async {
    await _animalDoc(animalId).update({
      'transferStatus': 'pending',
      'transferTargetType': targetType,
      'transferTargetName': targetName,
      if (targetOrgId != null) 'transferTargetOrgId': targetOrgId,
      if (notes != null && notes.isNotEmpty) 'transferNotes': notes,
      'transferredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(animalId: animalId, action: 'Transfer initiated to $targetName ($targetType)');
  }
}
