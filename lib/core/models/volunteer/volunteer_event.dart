import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// A volunteer event owned by one organization, stored at `events/{id}`.
/// Sign-ups live at `events/{id}/registrations/{uid}`; [goingCount] is kept
/// in step with them by [VolunteerEventRepository.register].
class VolunteerEvent {
  static const statusPublished = 'published';
  static const statusCancelled = 'cancelled';

  final String id;
  final String organizationId;
  final String title;
  final String description;

  /// Short place name shown on cards, e.g. "General Trias, Cavite".
  final String location;

  /// Full street address shown on the detail page and e-ticket.
  final String addressFull;
  final String organizerName;
  final DateTime startAt;
  final DateTime endAt;

  /// Null means no limit.
  final int? capacity;
  final int goingCount;
  final String status;
  final String? createdBy;

  // Per-viewer state, filled in by the user-side list.
  bool favorited;
  bool joined;

  VolunteerEvent({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.description,
    required this.location,
    required this.addressFull,
    required this.organizerName,
    required this.startAt,
    required this.endAt,
    this.capacity,
    this.goingCount = 0,
    this.status = statusPublished,
    this.createdBy,
    this.favorited = false,
    this.joined = false,
  });

  String get organizer => organizerName;
  String get date => DateFormat('EEEE, MMMM d, y').format(startAt);
  String get time => '${DateFormat.jm().format(startAt)} - ${DateFormat.jm().format(endAt)}';

  bool get isCancelled => status == statusCancelled;
  bool get isPast => endAt.isBefore(DateTime.now());
  bool get isFull => capacity != null && goingCount >= capacity!;

  /// Shown to users and open for sign-ups.
  bool get isOpen => !isCancelled && !isPast && !isFull;

  factory VolunteerEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime ts(Object? v) => v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    return VolunteerEvent(
      id: doc.id,
      organizationId: data['organizationId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',
      addressFull: data['addressFull'] as String? ?? '',
      organizerName: data['organizerName'] as String? ?? '',
      startAt: ts(data['startAt']),
      endAt: ts(data['endAt']),
      capacity: (data['capacity'] as num?)?.toInt(),
      goingCount: (data['goingCount'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? statusPublished,
      createdBy: data['createdBy'] as String?,
    );
  }

  /// Fields an organization edits; status/goingCount are managed separately.
  Map<String, dynamic> toEditableMap() => {
        'title': title,
        'description': description,
        'location': location,
        'addressFull': addressFull,
        'organizerName': organizerName,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'capacity': capacity,
      };
}

/// One person's sign-up for an event.
class EventRegistration {
  final String uid;
  final String participantName;
  final String participantEmail;
  final String participantMobileNumber;
  final String participantNumber;
  final DateTime? registeredAt;

  const EventRegistration({
    required this.uid,
    required this.participantName,
    required this.participantEmail,
    required this.participantMobileNumber,
    required this.participantNumber,
    this.registeredAt,
  });

  factory EventRegistration.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['registeredAt'];
    return EventRegistration(
      uid: doc.id,
      participantName: data['participantName'] as String? ?? '',
      participantEmail: data['participantEmail'] as String? ?? '',
      participantMobileNumber: data['participantMobileNumber'] as String? ?? '',
      participantNumber: data['participantNumber'] as String? ?? '',
      registeredAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
