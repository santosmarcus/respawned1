import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/volunteer/volunteer_application.dart';

/// `volunteerApplications/{uid}`. firestore.rules: the applicant writes
/// their own (always back to pending); organization staff approve or reject.
class VolunteerApplicationRepository {
  VolunteerApplicationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _apps => _db.collection('volunteerApplications');

  Stream<VolunteerApplication?> watchMine(String uid) =>
      _apps.doc(uid).snapshots().map((d) => d.exists ? VolunteerApplication.fromDoc(d) : null);

  Future<void> submit(VolunteerApplication app) =>
      _apps.doc(app.uid).set(app.toSubmission());

  /// Staff list, newest first. Sorted client-side to avoid an index.
  Stream<List<VolunteerApplication>> watchByStatus(VolunteerApplicationStatus status) {
    return _apps.where('status', isEqualTo: status.name).snapshots().map((snap) {
      final list = snap.docs.map(VolunteerApplication.fromDoc).toList()
        ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0)));
      return list;
    });
  }

  Future<void> review({
    required String uid,
    required bool approve,
    required String reviewerUid,
    String? note,
  }) {
    return _apps.doc(uid).update({
      'status': approve ? VolunteerApplicationStatus.approved.name : VolunteerApplicationStatus.rejected.name,
      'reviewedBy': reviewerUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewNote': ?(note == null || note.trim().isEmpty ? null : note.trim()),
    });
  }
}
