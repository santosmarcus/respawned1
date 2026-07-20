import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/models/rescue/saved_clinic.dart';

/// Per-user clinic bookmarks — `users/{uid}/savedClinics/{placeId}`.
/// Independent of any rescue case: saving/unsaving here never touches the
/// `vetClinic*` fields already written on a case doc (see
/// RescueCaseRepository.assignClinic), so unbookmarking never affects
/// clinic info already recorded on an existing case.
class SavedClinicsRepository {
  SavedClinicsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _savedClinicsOf(String uid) =>
      _db.collection('users').doc(uid).collection('savedClinics');

  Future<List<SavedClinic>> fetchSavedClinics(String uid) async {
    final snap = await _savedClinicsOf(uid).orderBy('savedAt', descending: true).get();
    return snap.docs.map(SavedClinic.fromFirestore).toList();
  }

  Stream<List<SavedClinic>> streamSavedClinics(String uid) {
    return _savedClinicsOf(uid).orderBy('savedAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(SavedClinic.fromFirestore).toList(),
        );
  }

  /// `placeId` is the document ID, so saving the same clinic twice is an
  /// idempotent overwrite (refreshing name/address/phone + savedAt), never
  /// a duplicate document.
  Future<void> saveClinic(String uid, ClinicSearchResult clinic) async {
    await _savedClinicsOf(uid)
        .doc(clinic.placeId)
        .set(SavedClinic.fromClinicSearchResult(clinic).toFirestore());
  }

  Future<void> unsaveClinic(String uid, String placeId) async {
    await _savedClinicsOf(uid).doc(placeId).delete();
  }
}
