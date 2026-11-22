import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/utils/animal_tag_codes.dart';
import 'package:respawnd1/core/utils/stream_combine.dart';

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
  CollectionReference<Map<String, dynamic>> get _publicAnimals => _db.collection('publicAnimals');
  DocumentReference<Map<String, dynamic>> _animalDoc(String animalId) => _animals.doc(animalId);
  CollectionReference<Map<String, dynamic>> _episodesOf(String animalId) =>
      _animalDoc(animalId).collection('medicalEpisodes');
  CollectionReference<Map<String, dynamic>> _vaccinationsOf(String animalId) =>
      _animalDoc(animalId).collection('vaccinations');
  CollectionReference<Map<String, dynamic>> _managementLogsOf(String animalId) =>
      _animalDoc(animalId).collection('managementLogs');
  CollectionReference<Map<String, dynamic>> _careRecordsOf(String animalId) =>
      _animalDoc(animalId).collection('careRecords');

  // ---- Reads --------------------------------------------------------

  Stream<AnimalRecord?> streamAnimalRecord(String animalId) {
    return _animalDoc(animalId).snapshots().map((doc) => doc.exists ? AnimalRecord.fromFirestore(doc) : null);
  }

  /// Public profiles (`publicAnimals/{id}`), the copy of each animal that
  /// isn't archived, hidden or deceased, written by the syncPublicAnimal
  /// function. What every non-staff screen reads: the adoption list, an
  /// animal's public page, a sponsor's or donor's view, a scanned QR tag.
  /// Parsed with [AnimalRecord.fromFirestore]; fields that aren't public
  /// (health details, reservation, rescue case, ...) come back empty.
  Stream<List<AnimalRecord>> streamPublicAnimals({String? organizationId}) {
    final Query<Map<String, dynamic>> q = organizationId == null
        ? _publicAnimals
        : _publicAnimals.where('organizationId', isEqualTo: organizationId);
    return q.snapshots().map(_parseAll);
  }

  Stream<AnimalRecord?> streamPublicAnimal(String animalId) {
    return _publicAnimals.doc(animalId).snapshots().map((doc) => doc.exists ? AnimalRecord.fromFirestore(doc) : null);
  }

  /// Every animal record the signed-in account may list — the list page
  /// applies search/filter/sort entirely client-side on top of this (same
  /// pattern OrganizationDirectoryRepository.search already uses), since
  /// Firestore can't combine free-text search across this many fields with
  /// the full range of sort options in one query. Fine at shelter-record
  /// scale. Platform staff get every animal, organization staff their own
  /// organization's (see [_listScope]).
  Stream<List<AnimalRecord>> streamAllAnimalRecords() => _scopedRecords((q) => q);

  /// Every record created from one source rescue/intake case, ordered by
  /// [AnimalRecord.sourceAnimalIndex] — powers "View Animal Record(s)" from
  /// Intake Details (see AnimalRecordsFlowPage).
  Stream<List<AnimalRecord>> streamRecordsForCase(String caseId) {
    return _scopedRecords((q) => q.where('linkedCaseId', isEqualTo: caseId)).map((records) {
      records.sort((a, b) => (a.sourceAnimalIndex ?? 0).compareTo(b.sourceAnimalIndex ?? 0));
      return records;
    });
  }

  /// One-shot version of the scoped list queries, for save-time checks.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryScoped(
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q) refine,
  ) async {
    final scope = await _listScope();
    if (scope == null) return (await refine(_animals).get()).docs;
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final org in scope) {
      try {
        docs.addAll((await refine(_animals.where('organizationId', isEqualTo: org)).get()).docs);
      } on FirebaseException {
        // Legacy records with no organization are readable only by
        // organization staff; a carer is denied them.
        if (org.isNotEmpty) rethrow;
      }
    }
    return docs;
  }

  /// The organizations whose animals the signed-in account may list, or
  /// null for every animal (platform staff). firestore.rules'
  /// canReadAnimal can only prove a list query that filters on
  /// organizationId, so staff read their own organization plus legacy
  /// records that have none.
  Future<List<String>?> _listScope() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    final user = (await _db.collection('users').doc(uid).get()).data() ?? const <String, dynamic>{};
    if (const ['admin', 'ngo_staff'].contains(user['role'])) return null;
    final orgId = (user['organizationId'] as String?) ?? '';
    return orgId.isEmpty ? const [] : [orgId, ''];
  }

  Stream<List<AnimalRecord>> _scopedRecords(
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q) refine,
  ) async* {
    final scope = await _listScope();
    if (scope == null) {
      yield* refine(_animals).snapshots().map(_parseAll);
      return;
    }
    if (scope.isEmpty) {
      yield const [];
      return;
    }
    final streams = [
      for (final org in scope)
        refine(_animals.where('organizationId', isEqualTo: org))
            .snapshots()
            .map(_parseAll)
            .transform(StreamTransformer<List<AnimalRecord>, List<AnimalRecord>>.fromHandlers(
              handleError: (error, stack, sink) {
                // See queryScoped: a carer is denied legacy records.
                if (org.isEmpty) {
                  sink.add(const []);
                } else {
                  sink.addError(error, stack);
                }
              },
            )),
    ];
    yield* combineLatest(streams).map((lists) => [for (final l in lists) ...l]);
  }

  /// Parses each document individually inside its own try/catch —
  /// AnimalRecord.fromFirestore already has its own internal fallback for a
  /// field-level parse failure, but this is the outer safety net for
  /// anything that still slips through (a genuinely corrupt document, a
  /// future field this model doesn't know about yet, ...): one bad
  /// document is logged and skipped, it never takes the whole list down
  /// with a single throw the way a bare `.map()` would.
  static List<AnimalRecord> _parseAll(QuerySnapshot<Map<String, dynamic>> snap) {
    final records = <AnimalRecord>[];
    for (final doc in snap.docs) {
      try {
        records.add(AnimalRecord.fromFirestore(doc));
      } catch (e) {
        debugPrint('[AnimalRecordRepository] Skipping unparseable animal record ${doc.id}: $e');
      }
    }
    return records;
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

  /// Every Animal Logs / Management-tab event (created, edited, vaccine
  /// added, archive, transfer, deceased, adopted, reserved, ...) appends
  /// here — this is what both the Management tab's own "View Logs" action
  /// and the header overflow menu's "View Logs" read, so there's one audit
  /// trail, not two.
  Stream<List<Map<String, dynamic>>> streamManagementLogs(String animalId) {
    return _managementLogsOf(animalId).orderBy('timestamp', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  /// Public entry point for callers outside this repository (Animal Record
  /// creation/edit, the Medical Profile sheet, the Add Vaccine sheet) that
  /// need to log an event without going through one of this repository's
  /// own state-changing methods. Internal methods below call the same
  /// underlying writer ([_addManagementLog]) so there is exactly one write
  /// path into `managementLogs`, never two.
  Future<void> logManagementEvent({
    required String animalId,
    required String eventType,
    required String action,
    String? description,
    String? actorId,
    String? actorName,
    String? actorEmail,
    String? actorRole,
    String? organizationId,
    Map<String, dynamic>? previousValues,
    Map<String, dynamic>? newValues,
    String? sourceModule,
    String? sourceRecordId,
  }) =>
      _addManagementLog(
        animalId: animalId,
        eventType: eventType,
        action: action,
        details: description,
        actorId: actorId,
        actorName: actorName,
        actorEmail: actorEmail,
        actorRole: actorRole,
        organizationId: organizationId,
        previousValues: previousValues,
        newValues: newValues,
        sourceModule: sourceModule,
        sourceRecordId: sourceRecordId,
      );

  /// The single writer behind every Animal Log entry. `action`/`details`
  /// are the original (pre-existing) fields the two log-list widgets
  /// already render — kept as-is for back-compat with legacy log docs that
  /// only ever had these two plus `timestamp`. Every field below them is
  /// additive: a legacy doc simply has them absent/null, never malformed.
  Future<void> _addManagementLog({
    required String animalId,
    required String action,
    String? details,
    String? eventType,
    String? actorId,
    String? actorName,
    String? actorEmail,
    String? actorRole,
    String? organizationId,
    Map<String, dynamic>? previousValues,
    Map<String, dynamic>? newValues,
    String? sourceModule,
    String? sourceRecordId,
  }) async {
    await _managementLogsOf(animalId).add({
      'animalId': animalId,
      'action': action,
      if (details != null && details.isNotEmpty) 'details': details,
      if (details != null && details.isNotEmpty) 'description': details,
      'eventType': ?eventType,
      if (actorId != null && actorId.isNotEmpty) 'actorId': actorId,
      if (actorName != null && actorName.isNotEmpty) 'actorName': actorName,
      if (actorEmail != null && actorEmail.isNotEmpty) 'actorEmail': actorEmail,
      if (actorRole != null && actorRole.isNotEmpty) 'actorRole': actorRole,
      if (organizationId != null && organizationId.isNotEmpty) 'organizationId': organizationId,
      if (previousValues != null && previousValues.isNotEmpty) 'previousValues': previousValues,
      if (newValues != null && newValues.isNotEmpty) 'newValues': newValues,
      'sourceModule': ?sourceModule,
      'sourceRecordId': ?sourceRecordId,
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
    await _addManagementLog(
      animalId: animal.id,
      eventType: 'intake_admitted',
      action: 'Animal admitted to Intake',
      details: reason,
      actorId: actorUid,
      actorName: actorName,
      sourceModule: 'medical',
      sourceRecordId: caseId,
    );

    return caseId;
  }

  // ---- Vaccinations ---------------------------------------------------

  /// Saves the record, then refreshes the animal doc's derived
  /// `vaccinated`/`vaccinesGiven` summary (never the reverse — those flat
  /// fields are always computed from records here, never hand-edited).
  Future<void> addVaccination({
    required String animalId,
    required VaccinationRecord record,
    String? actorId,
    String? actorEmail,
  }) async {
    await _vaccinationsOf(animalId).add(record.toFirestore());
    await _refreshVaccineSummary(animalId);
    await _addManagementLog(
      animalId: animalId,
      eventType: 'vaccine_added',
      action: 'Vaccine added',
      details: record.vaccineName,
      actorId: actorId,
      actorName: record.createdBy,
      actorEmail: actorEmail,
      newValues: {
        'vaccineName': record.vaccineName,
        'dateAdministered': record.dateAdministered.toIso8601String(),
        'nextDueDate': record.nextDueDate.toIso8601String(),
      },
    );
  }

  // ---- Preventive care (deworming, flea & tick, vet checkups) ----------

  Stream<List<CareRecord>> streamCareRecords(String animalId) {
    return _careRecordsOf(animalId).orderBy('dateGiven', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => CareRecord.fromFirestore(d, animalId)).toList(),
        );
  }

  /// Saves the record and keeps the Medical Profile's flat summary fields in
  /// step: a deworming record sets `dewormed`, a checkup moves
  /// `lastVetCheckup` forward (never back, so backfilling an old visit can't
  /// hide a newer one).
  Future<void> addCareRecord({
    required String animalId,
    required CareRecord record,
    String? actorId,
    String? actorEmail,
  }) async {
    await _careRecordsOf(animalId).add(record.toFirestore());
    final summary = <String, dynamic>{
      if (record.type == CareType.deworming) 'dewormed': true,
    };
    if (record.type == CareType.vetCheckup) {
      final current = (await _animalDoc(animalId).get()).data()?['lastVetCheckup'];
      final currentDate = current is Timestamp ? current.toDate() : null;
      if (currentDate == null || record.dateGiven.isAfter(currentDate)) {
        summary['lastVetCheckup'] = Timestamp.fromDate(record.dateGiven);
      }
    }
    if (summary.isNotEmpty) {
      await _animalDoc(animalId).update({...summary, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await _addManagementLog(
      animalId: animalId,
      eventType: 'care_added',
      action: '${record.type.label} recorded',
      details: record.product,
      actorId: actorId,
      actorName: record.createdBy,
      actorEmail: actorEmail,
      sourceModule: 'medical',
      newValues: {
        'type': record.type.name,
        'dateGiven': record.dateGiven.toIso8601String(),
        if (record.nextDueDate != null) 'nextDueDate': record.nextDueDate!.toIso8601String(),
      },
    );
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
      'spayedNeutered': ?spayedNeutered,
      'dewormed': ?dewormed,
      'allergies': ?allergies,
      'chronicConditions': ?chronicConditions,
      'currentMedications': ?currentMedications,
      if (lastVetCheckup != null) 'lastVetCheckup': Timestamp.fromDate(lastVetCheckup),
      'weightKg': ?weightKg,
      'bodyCondition': ?bodyCondition,
      'microchipStatus': ?microchipStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProfile({required String animalId, required Map<String, dynamic> fields}) async {
    await _animalDoc(animalId).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ---- Management tab ---------------------------------------------------

  // ---- Collar tags (QR and NFC) ------------------------------------------
  //
  // One registry for both types: animalTags/{code}, the document id being
  // the code itself, so a code belongs to at most one animal (firestore.rules
  // never lets a registration move to another animal). The animal keeps its
  // current code per type in qrTagId / nfcTagId; the rules only accept a
  // code there that is registered to that animal. See
  // core/utils/animal_tag_codes.dart for the shared code and payload.

  CollectionReference<Map<String, dynamic>> get _tags => _db.collection('animalTags');

  /// A code that is not registered yet. Codes are random, so a collision is
  /// very unlikely; [registerTag] re-checks inside its transaction.
  Future<String> newUnusedTagCode() async {
    for (var i = 0; i < 5; i++) {
      final code = newAnimalTagCode();
      if (!(await _tags.doc(code).get()).exists) return code;
    }
    throw StateError('Could not find an unused tag code. Try again.');
  }

  /// Registers [code] (or a new one) as the animal's [type] tag in one
  /// transaction: the registry entry, the animal's field, and retiring the
  /// code it replaces. Throws [DuplicateTagException] if the code already
  /// belongs to an animal (another one, or this one under the other type).
  /// Returns the registered code.
  Future<String> registerTag({
    required String animalId,
    required AnimalTagType type,
    String? code,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    final animalRef = _animalDoc(animalId);
    var chosen = (code ?? await newUnusedTagCode()).trim().toUpperCase();
    animalTagPayload(chosen); // throws on an empty or malformed code
    String? previous;
    await _db.runTransaction((tx) async {
      final animalSnap = await tx.get(animalRef);
      if (!animalSnap.exists) throw StateError('This animal record no longer exists.');
      final data = animalSnap.data()!;
      previous = (data[type.animalField] as String?)?.trim();
      final regSnap = await tx.get(_tags.doc(chosen));
      if (regSnap.exists) {
        final owner = regSnap.data()?['animalId'];
        throw DuplicateTagException(code: chosen, sameAnimal: owner == animalId);
      }
      final prevSnap = (previous ?? '').isNotEmpty ? await tx.get(_tags.doc(previous)) : null;

      tx.set(_tags.doc(chosen), {
        'code': chosen,
        'animalId': animalId,
        'organizationId': data['organizationId'] ?? '',
        'type': type.name,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': ?actorId,
      });
      tx.update(animalRef, {type.animalField: chosen, 'updatedAt': FieldValue.serverTimestamp()});
      if (prevSnap != null && prevSnap.exists && prevSnap.data()?['animalId'] == animalId) {
        tx.update(prevSnap.reference, {'active': false, 'deactivatedAt': FieldValue.serverTimestamp()});
      }
    });
    await _addManagementLog(
      animalId: animalId,
      eventType: '${type.name}${(previous ?? '').isEmpty ? 'Assigned' : 'Regenerated'}',
      action: '${type.label} ${(previous ?? '').isEmpty ? 'registered' : 'replaced'}',
      details: (previous ?? '').isEmpty ? null : 'Tags carrying the old code no longer open this animal.',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      previousValues: {if ((previous ?? '').isNotEmpty) type.animalField: previous},
      newValues: {type.animalField: chosen},
    );
    return chosen;
  }

  /// Removes the animal's [type] tag: retires its registry entry and clears
  /// the field. If that leaves an adoptable animal without any registered
  /// tag, it goes back to 'not_ready' in the same write (the collar tag is
  /// required to be adoptable). Returns true when that happened.
  Future<bool> removeTag({
    required String animalId,
    required AnimalTagType type,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    final animalRef = _animalDoc(animalId);
    String? previous;
    var unlisted = false;
    await _db.runTransaction((tx) async {
      final animalSnap = await tx.get(animalRef);
      if (!animalSnap.exists) return;
      final data = animalSnap.data()!;
      previous = (data[type.animalField] as String?)?.trim();
      final prevSnap = (previous ?? '').isNotEmpty ? await tx.get(_tags.doc(previous)) : null;
      final other = type == AnimalTagType.qr ? AnimalTagType.nfc : AnimalTagType.qr;
      final otherCode = (data[other.animalField] as String?)?.trim() ?? '';
      unlisted = data['adoptionStatus'] == 'adoptable' && otherCode.isEmpty;

      if (prevSnap != null && prevSnap.exists && prevSnap.data()?['animalId'] == animalId) {
        tx.update(prevSnap.reference, {'active': false, 'deactivatedAt': FieldValue.serverTimestamp()});
      }
      tx.update(animalRef, {
        type.animalField: FieldValue.delete(),
        if (unlisted) 'adoptionStatus': 'not_ready',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await _addManagementLog(
      animalId: animalId,
      eventType: '${type.name}Removed',
      action: '${type.label} removed',
      details: [
        'Tags carrying this code no longer open this animal.',
        if (unlisted) 'No registered collar tag is left, so the animal is no longer listed as adoptable.',
      ].join(' '),
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      previousValues: {
        if ((previous ?? '').isNotEmpty) type.animalField: previous,
        if (unlisted) 'adoptionStatus': 'adoptable',
      },
      newValues: {if (unlisted) 'adoptionStatus': 'not_ready'},
    );
    return unlisted;
  }

  /// QR codes assigned before the registry existed live only on the
  /// animal's qrTagId. Registers such a code so it counts as a registered
  /// tag (adoption eligibility, scanning). Does nothing when it is already
  /// registered; never takes over a code registered to another animal.
  Future<void> ensureLegacyQrRegistered(AnimalRecord animal) => _ensureLegacyQrRegistered(
        animalId: animal.id,
        qrTagId: animal.qrTagId,
        organizationId: animal.raw['organizationId'] as String?,
      );

  Future<void> _ensureLegacyQrRegistered({
    required String animalId,
    required String? qrTagId,
    required String? organizationId,
  }) async {
    final code = (qrTagId ?? '').trim();
    if (code.isEmpty || animalTagFromScan('$kAnimalTagPrefix$code') == null) return;
    final ref = _tags.doc(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;
      tx.set(ref, {
        'code': code,
        'animalId': animalId,
        'organizationId': organizationId ?? '',
        'type': AnimalTagType.qr.name,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'legacy': true,
      });
    });
  }

  /// The registry entry for [code] (animalId, active, type), or null.
  Future<Map<String, dynamic>?> tagRegistration(String code) async =>
      (await _tags.doc(code.trim().toUpperCase()).get()).data();

  /// Whether [code] is registered to [animalId] and active.
  Future<bool> isTagRegisteredTo(String animalId, String? code) async {
    if ((code ?? '').isEmpty) return false;
    final snap = await _tags.doc(code).get();
    return snap.exists && snap.data()?['animalId'] == animalId && snap.data()?['active'] == true;
  }

  /// Whether the animal has at least one registered collar tag (QR or NFC).
  /// Registers a legacy QR code first, so older animals aren't blocked.
  /// [data] is the animal document (qrTagId, nfcTagId, organizationId).
  Future<bool> hasRegisteredCollarTag(String animalId, Map<String, dynamic> data) async {
    final qr = data['qrTagId'] as String?;
    if ((qr ?? '').isNotEmpty) {
      try {
        await _ensureLegacyQrRegistered(
          animalId: animalId,
          qrTagId: qr,
          organizationId: data['organizationId'] as String?,
        );
      } catch (_) {
        // Fall through to the check below.
      }
      if (await isTagRegisteredTo(animalId, qr)) return true;
    }
    return isTagRegisteredTo(animalId, data['nfcTagId'] as String?);
  }

  // Kept for existing callers (Management tab): the QR case of the above.

  /// Assigns a QR tag if the animal has none, and returns it.
  Future<String> ensureQrTag({
    required String animalId,
    required String? existing,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    if (existing != null && existing.isNotEmpty) return existing;
    return registerTag(
      animalId: animalId,
      type: AnimalTagType.qr,
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
    );
  }

  /// Replaces the animal's QR tag with a new code and returns it. Tags
  /// printed with the old code stop opening this animal.
  Future<String> regenerateQrTag({
    required String animalId,
    required String? previous,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) =>
      registerTag(
        animalId: animalId,
        type: AnimalTagType.qr,
        actorId: actorId,
        actorName: actorName,
        actorEmail: actorEmail,
      );

  /// Removes the animal's QR tag. Returns true when the animal was taken
  /// off adoption because no registered tag is left.
  Future<bool> removeQrTag({
    required String animalId,
    required String? previous,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) =>
      removeTag(
        animalId: animalId,
        type: AnimalTagType.qr,
        actorId: actorId,
        actorName: actorName,
        actorEmail: actorEmail,
      );

  /// Hides or shows the animal on public adoption listings (P2-12).
  Future<void> setPublicProfileHidden({
    required String animalId,
    required bool hidden,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    await _animalDoc(animalId).update({'publicProfileHidden': hidden, 'updatedAt': FieldValue.serverTimestamp()});
    await _addManagementLog(
      animalId: animalId,
      eventType: hidden ? 'publicHidden' : 'publicShown',
      action: hidden ? 'Hidden from public profile' : 'Shown on public profile',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
    );
  }

  /// Sets the day-to-day shelter status. A returned animal given a new
  /// status stops reading "Returned" (its return history is kept).
  Future<void> setCareStatus({
    required String animalId,
    required CareStatus status,
    CareStatus? previous,
    String? note,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    await _animalDoc(animalId).update({
      'careStatus': status.firestoreValue,
      'careStatusUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(
      animalId: animalId,
      eventType: 'careStatus',
      action: 'Status set to ${status.label}',
      details: note,
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      previousValues: {'careStatus': previous?.label ?? 'Not set'},
      newValues: {'careStatus': status.label},
    );
  }

  Future<void> setArchived({
    required String animalId,
    required bool archived,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    await _animalDoc(animalId).update({'archived': archived, 'updatedAt': FieldValue.serverTimestamp()});
    await _addManagementLog(
      animalId: animalId,
      eventType: archived ? 'archived' : 'restored',
      action: archived ? 'Archived' : 'Restored',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
    );
  }

  /// Re-reads current state before writing — never trusts the UI's own
  /// enabled/disabled guard alone (spec: "Mark as Deceased" safety). Once an
  /// animal has actually been adopted (adoptionStatus == 'adopted') or has a
  /// transfer in progress (transferStatus == 'pending' — see
  /// AnimalRecord.isTransferredOut), this rejects the transition and neither
  /// writes the record nor creates a log entry, so a stale UI (an action
  /// tapped just before another admin's adopt/transfer commits) can never
  /// mark a since-rehomed animal deceased.
  Future<void> markDeceased({
    required String animalId,
    DateTime? date,
    String? cause,
    String? notes,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    final snap = await _animalDoc(animalId).get();
    final data = snap.data();
    if (data == null) throw StateError('Animal record not found.');
    final adoptionStatus = data['adoptionStatus'] as String?;
    if (adoptionStatus == 'adopted') {
      throw StateError('Unavailable after the animal has been transferred or adopted.');
    }
    if ((data['transferStatus'] as String?) == 'pending') {
      throw StateError('Unavailable after the animal has been transferred or adopted.');
    }

    await _animalDoc(animalId).update({
      'adoptionStatus': 'deceased',
      'status': 'deceased',
      'deceasedAt': date != null ? Timestamp.fromDate(date) : FieldValue.serverTimestamp(),
      if (cause != null && cause.isNotEmpty) 'deceasedCause': cause,
      if (notes != null && notes.isNotEmpty) 'deceasedNotes': notes,
      // Analytics gap 5: a euthanasia's second review must come from
      // someone other than the person who recorded it.
      'deceasedByUid': FirebaseAuth.instance.currentUser?.uid ?? actorId,
      'deceasedByName': ?actorName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(
      animalId: animalId,
      action: 'Marked deceased',
      details: cause == null || cause.isEmpty ? null : 'Cause: $cause',
      eventType: 'deceased',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      newValues: {'adoptionStatus': 'deceased', if (cause != null && cause.isNotEmpty) 'deceasedCause': cause},
    );
  }

  /// Only ever called after the existing adoption-application workflow has
  /// actually approved an application for this animal — this method itself
  /// performs no such check (that belongs to the adoption module, out of
  /// scope here); the Management tab UI is what's responsible for only
  /// exposing this action when that's true.
  Future<void> markAdopted({
    required String animalId,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    await _animalDoc(animalId).update({
      'adoptionStatus': 'adopted',
      'status': 'adopted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(
      animalId: animalId,
      eventType: 'adopted',
      action: 'Adoption/release completed',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      newValues: const {'adoptionStatus': 'adopted'},
    );
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
    String? actorId,
    String? actorName,
    String? actorEmail,
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
    await _addManagementLog(
      animalId: animalId,
      eventType: 'received',
      action: 'Animal received — returned by adopter, entered Intake for review',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      sourceModule: 'adoption',
      sourceRecordId: returnRequestId,
    );
  }

  Future<void> transferAnimal({
    required String animalId,
    required String targetType, // 'organization' | 'volunteer'
    required String targetName,
    String? targetOrgId,
    String? notes,
    String? actorId,
    String? actorName,
    String? actorEmail,
  }) async {
    await _animalDoc(animalId).update({
      'transferStatus': 'pending',
      'transferTargetType': targetType,
      'transferTargetName': targetName,
      'transferTargetOrgId': ?targetOrgId,
      if (notes != null && notes.isNotEmpty) 'transferNotes': notes,
      'transferredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addManagementLog(
      animalId: animalId,
      eventType: 'transferred',
      action: 'Transferred to $targetName ($targetType)',
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      newValues: {'transferTargetType': targetType, 'transferTargetName': targetName},
    );
  }
}

/// A collar tag code that is already registered to an animal.
class DuplicateTagException implements Exception {
  const DuplicateTagException({required this.code, required this.sameAnimal});
  final String code;

  /// Registered to this same animal (e.g. as its other tag type).
  final bool sameAnimal;

  @override
  String toString() => sameAnimal
      ? 'This tag ($code) is already registered to this animal.'
      : 'This tag ($code) is already registered to another animal. Remove it there first, or use a new tag.';
}
