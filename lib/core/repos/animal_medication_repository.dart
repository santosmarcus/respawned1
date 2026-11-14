import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/rescue/medication.dart';
import 'package:respawnd1/core/models/rescue/care_update.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';

/// Medication orders and dose records for an animal.
///
/// Paths: `animals/{animalId}/medications/{planId}` (admins write) and
/// `animals/{animalId}/medicationDoses/{doseId}` (carers and admins write).
/// firestore.rules enforces who may write each; this class only shapes data.
class AnimalMedicationRepository {
  AnimalMedicationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _plans(String animalId) =>
      _db.collection('animals').doc(animalId).collection('medications');

  CollectionReference<Map<String, dynamic>> _doses(String animalId) =>
      _db.collection('animals').doc(animalId).collection('medicationDoses');

  CollectionReference<Map<String, dynamic>> _log(String animalId) =>
      _db.collection('animals').doc(animalId).collection('managementLogs');

  /// Starting and ending an order is written to the animal's log (shown on
  /// the record and in Audit) in the same write as the change itself.
  Map<String, dynamic> _logEntry(String animalId, String action, String description, Map<String, dynamic> values) {
    final user = FirebaseAuth.instance.currentUser;
    return {
      'animalId': animalId,
      'action': action,
      'details': description,
      'description': description,
      'eventType': 'medication',
      'actorId': ?user?.uid,
      'actorName': ?(user?.displayName ?? user?.email),
      'actorEmail': ?user?.email,
      'newValues': values,
      'sourceModule': 'medication',
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  Stream<List<MedicationPlan>> watchPlans(String animalId) {
    return _plans(animalId).snapshots().map((snap) {
      final plans = snap.docs
          .map((d) => MedicationPlan.fromDoc(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      return plans;
    });
  }

  /// Doses from the last [days] days, keyed by dose id so [doseStatusFor]
  /// can look them up directly. The screen only shows today and the
  /// past week, so older history isn't loaded.
  Stream<Map<String, MedicationDose>> watchDoses(String animalId, {int days = 8}) {
    final since = dayOnly(DateTime.now()).subtract(Duration(days: days));
    return _doses(animalId)
        .where('day', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .snapshots()
        .map((snap) => {
          for (final d in snap.docs) d.id: MedicationDose.fromDoc(d.id, d.data()),
        });
  }

  Future<void> addPlan({
    required String animalId,
    required String drug,
    required String dose,
    required int timesPerDay,
    required DateTime startDate,
    DateTime? endDate,
    String? createdBy,
    List<MediaRef> attachments = const [],
  }) async {
    final plan = MedicationPlan(
      id: '',
      animalId: animalId,
      drug: drug.trim(),
      dose: dose.trim(),
      timesPerDay: timesPerDay.clamp(1, 4),
      startDate: startDate,
      endDate: endDate,
      createdBy: createdBy,
      attachments: attachments,
    );
    final batch = _db.batch();
    final ref = _plans(animalId).doc();
    batch.set(ref, plan.toMap());
    batch.set(
      _log(animalId).doc(),
      _logEntry(animalId, 'Medication order started', '${plan.drug} · ${plan.dose} · ${plan.timesPerDay}x a day', {
        'drug': plan.drug,
        'dose': plan.dose,
        'timesPerDay': plan.timesPerDay,
        'planId': ref.id,
      }),
    );
    await batch.commit();
  }

  /// Ends a plan from today on; history stays for the audit trail.
  Future<void> endPlan({required String animalId, required String planId, String? drug}) async {
    final batch = _db.batch()
      ..update(_plans(animalId).doc(planId), {
        'active': false,
        'endDate': Timestamp.fromDate(dayOnly(DateTime.now())),
      })
      ..set(
        _log(animalId).doc(),
        _logEntry(animalId, 'Medication order ended', drug ?? 'Medication order', {'planId': planId, 'drug': ?drug}),
      );
    await batch.commit();
  }

  /// Records a dose. The deterministic id means a slot can only be recorded
  /// once; a second tap rewrites the same document with the same content.
  Future<void> logDose({
    required String animalId,
    required String planId,
    required DateTime day,
    required int slot,
    required String givenBy,
    String? givenByName,
    List<String> mediaUrls = const [],
    List<String> mediaTypes = const [],
    String? note,
  }) async {
    final id = doseIdFor(planId, day, slot);
    await _doses(animalId).doc(id).set({
      'planId': planId,
      'animalId': animalId,
      'day': Timestamp.fromDate(dayOnly(day)),
      'slot': slot,
      'givenBy': givenBy,
      'givenByName': ?givenByName,
      'givenAt': FieldValue.serverTimestamp(),
      'mediaUrls': mediaUrls,
      if (mediaTypes.isNotEmpty) 'mediaTypes': mediaTypes,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  // ---- Care updates -------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _careUpdates(String animalId) =>
      _db.collection('animals').doc(animalId).collection('careUpdates');

  /// Newest first.
  Stream<List<CareUpdate>> watchCareUpdates(String animalId, {int limit = 20}) {
    return _careUpdates(animalId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => [for (final d in snap.docs) CareUpdate.fromDoc(animalId, d)]);
  }

  Future<void> addCareUpdate({
    required String animalId,
    required CareUpdateType type,
    required String note,
    List<MediaRef> media = const [],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _careUpdates(animalId).add(CareUpdate.newDoc(
      type: type,
      note: note,
      media: media,
      authorId: user?.uid ?? '',
      authorName: user?.displayName ?? user?.email,
    ));
  }

  // ---- Across every animal (dashboard missed-dose alert) -----------------

  /// Every active medication order, keyed by animal id.
  Stream<Map<String, List<MedicationPlan>>> watchActivePlansByAnimal() {
    return _db.collectionGroup('medications').where('active', isEqualTo: true).snapshots().map((snap) {
      final out = <String, List<MedicationPlan>>{};
      for (final d in snap.docs) {
        final animalId = d.reference.parent.parent?.id;
        if (animalId == null) continue;
        out.putIfAbsent(animalId, () => []).add(MedicationPlan.fromDoc(d.id, d.data()));
      }
      return out;
    });
  }

  /// Doses recorded in the last [days] days, keyed by dose id.
  Stream<Map<String, MedicationDose>> watchRecentDosesEverywhere({int days = 7}) {
    final since = dayOnly(DateTime.now()).subtract(Duration(days: days));
    return _db
        .collectionGroup('medicationDoses')
        .where('day', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .snapshots()
        .map((snap) => {for (final d in snap.docs) d.id: MedicationDose.fromDoc(d.id, d.data())});
  }
}
