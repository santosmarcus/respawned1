import 'package:cloud_firestore/cloud_firestore.dart';

/// A rescue report as the signed-in user may see it: the full `cases/{id}`
/// document for the people working it (staff, the reporter, the transporter
/// or rider on it, the willing adopter, verified transporters), otherwise
/// the public copy at `publicCases/{id}` (functions/public_cases.js), which
/// leaves out the reporter's details, the rider's location, notes and the
/// status history.
Stream<DocumentSnapshot<Map<String, dynamic>>> watchCaseOrPublic(String caseId, {FirebaseFirestore? firestore}) async* {
  final db = firestore ?? FirebaseFirestore.instance;
  try {
    await for (final snap in db.collection('cases').doc(caseId).snapshots()) {
      yield snap;
    }
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    yield* db.collection('publicCases').doc(caseId).snapshots();
  }
}

/// One-shot version of [watchCaseOrPublic].
Future<DocumentSnapshot<Map<String, dynamic>>> getCaseOrPublic(String caseId, {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  try {
    return await db.collection('cases').doc(caseId).get();
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    return db.collection('publicCases').doc(caseId).get();
  }
}
