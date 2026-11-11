import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/transporter_application.dart';

/// `transporterApplications/{uid}`. firestore.rules: the applicant writes
/// their own (always back to pending, from transporter_verification_screen
/// .dart); approved organization staff read and review them.
class TransporterApplicationRepository {
  TransporterApplicationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _apps => _db.collection('transporterApplications');

  Stream<TransporterApplication?> watch(String uid) =>
      _apps.doc(uid).snapshots().map((d) => d.exists ? TransporterApplication.fromDoc(d) : null);

  /// Staff list, newest first. Sorted client-side to avoid an index.
  Stream<List<TransporterApplication>> watchByStatus(TransporterApplicationStatus status) {
    return _apps.where('status', isEqualTo: status.name).snapshots().map((snap) {
      final list = snap.docs.map(TransporterApplication.fromDoc).toList()
        ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0)));
      return list;
    });
  }

  /// Records the decision on the application and applies it to the
  /// transporter's account in one batch, so the two can't disagree:
  /// approved -> `isVerified: true`, rejected -> `isVerified: false` (the
  /// transporter's profile then offers to resubmit).
  Future<void> review({
    required String uid,
    required bool approve,
    required String reviewerUid,
    String? note,
  }) {
    final status = approve ? TransporterApplicationStatus.approved : TransporterApplicationStatus.rejected;
    final trimmed = note?.trim();
    final batch = _db.batch()
      ..update(_apps.doc(uid), {
        'status': status.name,
        'reviewedBy': reviewerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewNote': (trimmed == null || trimmed.isEmpty) ? FieldValue.delete() : trimmed,
      })
      ..update(_db.collection('users').doc(uid), {
        'isVerified': approve,
        'transporterVerificationStatus': status.name,
      });
    return batch.commit();
  }
}
