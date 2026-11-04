import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/medication.dart';

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
    );
    await _plans(animalId).add(plan.toMap());
  }

  /// Ends a plan from today on; history stays for the audit trail.
  Future<void> endPlan({required String animalId, required String planId}) async {
    await _plans(animalId).doc(planId).update({
      'active': false,
      'endDate': Timestamp.fromDate(dayOnly(DateTime.now())),
    });
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
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }
}
