import 'package:cloud_firestore/cloud_firestore.dart';

/// Kinds of message in a case thread (`cases/{caseId}/messages`). Plain text
/// is the default (messages written before kinds existed have none).
enum CaseMessageKind {
  text,

  /// Staff (or the backend, when a community report comes in) ask the
  /// person who filed the report to confirm what another community member
  /// reported: the animal moved, was rescued by someone else, or is no
  /// longer there. The reporter answers on the message itself.
  confirmRequest,

  /// Staff ask the reporter for the animal's current location.
  locationRequest,

  /// A location the reporter shared (detected on their phone). Staff can
  /// apply it as the case's new location.
  location;

  static CaseMessageKind fromName(Object? v) => switch (v) {
        'confirm_request' => confirmRequest,
        'location_request' => locationRequest,
        'location' => location,
        _ => text,
      };

  String get firestoreValue => switch (this) {
        text => 'text',
        confirmRequest => 'confirm_request',
        locationRequest => 'location_request',
        location => 'location',
      };
}

/// Who rescued the animal, offered when the reporter confirms a "rescued by
/// another team" report.
const List<String> kRescuedByOptions = [
  'Another rescue group',
  'Barangay or LGU',
  'A neighbor or passerby',
  'The owner took it back',
  'Not sure',
];

class CaseMessage {
  const CaseMessage({
    required this.id,
    required this.kind,
    required this.text,
    this.senderId,
    this.senderName,
    this.senderRole,
    this.timestamp,
    this.reportId,
    this.reportCaseId,
    this.reportType,
    this.newAddress,
    this.lat,
    this.lng,
    this.address,
    this.status,
    this.answer,
    this.rescuedBy,
    this.answeredAt,
    this.appliedAt,
    this.appliedBy,
  });

  final String id;
  final CaseMessageKind kind;
  final String text;
  final String? senderId;
  final String? senderName;
  final String? senderRole;
  final DateTime? timestamp;

  // confirmRequest
  final String? reportId;
  final String? reportCaseId;

  /// The community report's type: moved | rescued | no_animal.
  final String? reportType;
  final String? newAddress;

  // location (and the reported spot of a "moved" confirmRequest)
  final double? lat;
  final double? lng;
  final String? address;

  /// confirmRequest / locationRequest: open | answered.
  final String? status;

  /// confirmRequest: yes | no.
  final String? answer;
  final String? rescuedBy;
  final DateTime? answeredAt;

  /// location: when staff made it the case's location.
  final DateTime? appliedAt;
  final String? appliedBy;

  bool get isOpen => status != 'answered';
  bool get confirmed => answer == 'yes';
  bool get isStaff => senderRole == 'organization' || senderId == 'admin';
  bool get isSystem => senderRole == 'system';

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  factory CaseMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CaseMessage(
      id: doc.id,
      kind: CaseMessageKind.fromName(d['kind']),
      text: (d['text'] as String?) ?? '',
      senderId: d['senderId'] as String?,
      senderName: d['senderName'] as String?,
      senderRole: d['senderRole'] as String?,
      timestamp: _date(d['timestamp']),
      reportId: d['reportId'] as String?,
      reportCaseId: d['reportCaseId'] as String?,
      reportType: d['reportType'] as String?,
      newAddress: d['newAddress'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      address: d['address'] as String?,
      status: d['status'] as String?,
      answer: d['answer'] as String?,
      rescuedBy: d['rescuedBy'] as String?,
      answeredAt: _date(d['answeredAt']),
      appliedAt: _date(d['appliedAt']),
      appliedBy: d['appliedBy'] as String?,
    );
  }

  /// The question asked for a community report of [type].
  static String confirmQuestion(String? type, {String? newAddress}) => switch (type) {
        'moved' => 'Someone reported that the animal moved'
            '${newAddress != null && newAddress.isNotEmpty ? ' to $newAddress' : ''}. Is this true?',
        'rescued' => 'Someone reported that the animal was already rescued by another team. Is this true?',
        'no_animal' => 'Someone reported that the animal is no longer at the location. Is this true?',
        _ => 'Please confirm the latest community report.',
      };
}

/// Suggested replies shown above the message box.
const List<String> kStaffSuggestedReplies = [
  'Is the animal still there?',
  'Thank you for the update!',
  'We\'re on our way.',
  'Can you send a recent photo?',
];

const List<String> kReporterSuggestedReplies = [
  'The animal is still here.',
  'The animal has moved.',
  'I\'m near the animal now.',
  'Thank you!',
];
