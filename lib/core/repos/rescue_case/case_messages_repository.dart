import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/rescue/case_message.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/repos/rescue_case/case_message_sender.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

/// The case thread (`cases/{caseId}/messages`) shared by the reporter and
/// the organization: plain messages, and the structured ones that drive the
/// community-report confirmations and location updates (CaseMessageKind).
class CaseMessagesRepository {
  CaseMessagesRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _messages(String caseId) =>
      _db.collection('cases').doc(caseId).collection('messages');

  Stream<List<CaseMessage>> watch(String caseId) => _messages(caseId)
      .orderBy('timestamp')
      .snapshots()
      .map((s) => s.docs.map(CaseMessage.fromDoc).toList());

  /// Sender fields for the signed-in reporter (their profile name).
  Future<Map<String, Object?>> _reporterFields() async {
    final user = FirebaseAuth.instance.currentUser;
    var name = '';
    try {
      final d = (await _db.collection('users').doc(user?.uid).get()).data();
      name = '${(d?['firstName'] as String?)?.trim() ?? ''} ${(d?['lastName'] as String?)?.trim() ?? ''}'.trim();
    } catch (_) {}
    if (name.isEmpty) name = user?.displayName?.trim() ?? '';
    return {
      'senderId': user?.uid,
      'senderName': name.isEmpty ? 'Reporter' : name,
      'senderRole': 'reporter',
    };
  }

  Future<Map<String, Object?>> _sender({required bool staff}) =>
      staff ? CaseMessageSender.staffFields(firestore: _db) : _reporterFields();

  Future<void> sendText(String caseId, String text, {required bool staff}) async {
    await _messages(caseId).add({
      ...await _sender(staff: staff),
      'kind': CaseMessageKind.text.firestoreValue,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Staff ask the reporter to confirm [report]. Does nothing when an open
  /// request for it already exists (the backend files one automatically
  /// when the report comes in).
  Future<void> requestConfirmation(String caseId, CommunityReport report) async {
    final existing = await _messages(caseId).where('reportId', isEqualTo: report.id).get();
    if (existing.docs.any((d) => d.data()['kind'] == CaseMessageKind.confirmRequest.firestoreValue)) return;
    await _messages(caseId).add({
      ...await _sender(staff: true),
      'kind': CaseMessageKind.confirmRequest.firestoreValue,
      'text': CaseMessage.confirmQuestion(report.type, newAddress: report.newAddress),
      'reportId': report.id,
      if (report.caseId != null && report.caseId != caseId) 'reportCaseId': report.caseId,
      'reportType': report.type,
      if (report.newAddress != null) 'newAddress': report.newAddress,
      if (report.newLat != null) 'lat': report.newLat,
      if (report.newLng != null) 'lng': report.newLng,
      'status': 'open',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// The reporter answers a confirmation request: the answer is kept on the
  /// request (staff read it from there) and posted as a reply.
  Future<void> answerConfirmation(String caseId, CaseMessage request, {required bool yes, String? rescuedBy}) async {
    final sender = await _sender(staff: false);
    final batch = _db.batch();
    batch.update(_messages(caseId).doc(request.id), {
      'status': 'answered',
      'answer': yes ? 'yes' : 'no',
      if (rescuedBy != null && rescuedBy.isNotEmpty) 'rescuedBy': rescuedBy,
      'answeredAt': FieldValue.serverTimestamp(),
      'answeredBy': sender['senderId'],
    });
    final reply = switch (request.reportType) {
      'moved' => yes ? 'Yes, the animal has moved.' : 'No, the animal has not moved.',
      'rescued' => yes
          ? 'Yes, it was rescued${rescuedBy != null && rescuedBy.isNotEmpty ? ' (${rescuedBy.toLowerCase()})' : ''}.'
          : 'No, it has not been rescued.',
      'no_animal' => yes ? 'Yes, the animal is no longer there.' : 'No, the animal is still there.',
      _ => yes ? 'Yes.' : 'No.',
    };
    batch.set(_messages(caseId).doc(), {
      ...sender,
      'kind': CaseMessageKind.text.firestoreValue,
      'text': reply,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Staff ask the reporter where the animal is now.
  Future<void> requestLocation(String caseId) async {
    await _messages(caseId).add({
      ...await _sender(staff: true),
      'kind': CaseMessageKind.locationRequest.firestoreValue,
      'text': 'Could you share where the animal is right now?',
      'status': 'open',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// The reporter shares a location (detected on their phone), answering
  /// any open location request.
  Future<void> shareLocation(String caseId,
      {required double lat, required double lng, String? address, List<CaseMessage> openRequests = const []}) async {
    final batch = _db.batch();
    batch.set(_messages(caseId).doc(), {
      ...await _sender(staff: false),
      'kind': CaseMessageKind.location.firestoreValue,
      'text': address == null || address.isEmpty ? 'Shared the animal\'s location.' : 'The animal is at $address.',
      'lat': lat,
      'lng': lng,
      'address': ?address,
      'timestamp': FieldValue.serverTimestamp(),
    });
    for (final r in openRequests) {
      batch.update(_messages(caseId).doc(r.id), {'status': 'answered', 'answeredAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  /// Staff make a shared location the case's location. The previous one is
  /// kept in locationHistory; the transporter is told by
  /// notifyTransporterCaseChanges.
  Future<void> applyLocation(String caseId, CaseMessage location) async {
    final lat = location.lat, lng = location.lng;
    if (lat == null || lng == null) throw StateError('This message has no location.');
    final sender = await _sender(staff: true);
    final caseRef = _db.collection('cases').doc(caseId);
    final caseData = (await caseRef.get()).data() ?? const {};
    final address = (location.address?.trim().isNotEmpty ?? false)
        ? location.address!.trim()
        : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    final actorName = (sender['senderStaffName'] ?? sender['senderName'] ?? 'Staff') as String;
    await RescueCaseStore(_db).recordAction(
      caseId: caseId,
      action: 'location_updated_from_reporter',
      statusLine: 'Location updated to "$address" (shared by the reporter, confirmed by $actorName).',
      actorUid: sender['senderId'] as String?,
      actorName: actorName,
      details: {'messageId': location.id},
      fields: {
        'address': address,
        'lat': lat,
        'lng': lng,
        'locationHistory': FieldValue.arrayUnion([
          {
            'previousAddress': caseData['address'],
            'previousLat': caseData['lat'],
            'previousLng': caseData['lng'],
            'address': address,
            'lat': lat,
            'lng': lng,
            'source': 'reporter_message',
            'messageId': location.id,
            'approvedBy': actorName,
            'approvedAt': Timestamp.now(),
          },
        ]),
      },
    );
    await _messages(caseId).doc(location.id).update({
      'appliedAt': FieldValue.serverTimestamp(),
      'appliedBy': actorName,
    });
  }
}
