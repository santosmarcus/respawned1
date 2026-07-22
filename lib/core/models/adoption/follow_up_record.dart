import 'package:cloud_firestore/cloud_firestore.dart';

/// A single scheduled check-in under `adoptions/{id}/followUps/{followUpId}`
/// — the admin-facing scheduling/status/reminder layer generated from the
/// release's [FollowUpScheduleRule]s. The follow-up's doc id matches the id
/// of the corresponding `adoptions/{id}/checkins/{id}` doc (the existing
/// user-side questionnaire storage) so the two never need a separate
/// `responseId` link.
enum FollowUpStatus {
  scheduled,
  reminderSent,
  submitted,
  confirmed,
  completed,
  cancelled;

  String get label => switch (this) {
        FollowUpStatus.scheduled => 'Upcoming',
        FollowUpStatus.reminderSent => 'Reminder Sent',
        FollowUpStatus.submitted => 'Submitted',
        FollowUpStatus.confirmed => 'Confirmed',
        FollowUpStatus.completed => 'Completed',
        FollowUpStatus.cancelled => 'Cancelled',
      };

  static FollowUpStatus fromName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => FollowUpStatus.scheduled);
}

class FollowUpRecord {
  final String id;
  final int sequenceNumber;
  final DateTime scheduledDate;
  final FollowUpStatus status;
  final String? scheduleRuleId;

  final DateTime? reminderSentAt;
  final int reminderCount;

  final DateTime? submittedAt;
  final DateTime? confirmedAt;
  final String? confirmedBy;
  final String? confirmationNotes;

  final DateTime? completedAt;
  final String? completedBy;
  final String? manualCompletionReason;

  final DateTime? originalScheduledDate;
  final DateTime? rescheduledAt;
  final String? rescheduledBy;
  final String? rescheduleReason;

  final Map<String, dynamic> raw;

  const FollowUpRecord({
    required this.id,
    required this.sequenceNumber,
    required this.scheduledDate,
    required this.status,
    this.scheduleRuleId,
    this.reminderSentAt,
    this.reminderCount = 0,
    this.submittedAt,
    this.confirmedAt,
    this.confirmedBy,
    this.confirmationNotes,
    this.completedAt,
    this.completedBy,
    this.manualCompletionReason,
    this.originalScheduledDate,
    this.rescheduledAt,
    this.rescheduledBy,
    this.rescheduleReason,
    required this.raw,
  });

  /// The status actually shown in the UI — "Overdue" is never persisted (a
  /// follow-up isn't complete just because its date passed), it's computed
  /// here on top of the real [status] whenever the due date is behind [now]
  /// and no response has come in yet.
  String displayStatus(DateTime now) {
    final isPastDue = scheduledDate.isBefore(now);
    if ((status == FollowUpStatus.scheduled || status == FollowUpStatus.reminderSent) && isPastDue) {
      return 'Overdue';
    }
    return status.label;
  }

  bool get isTerminal => status == FollowUpStatus.completed || status == FollowUpStatus.cancelled;

  factory FollowUpRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return FollowUpRecord(
      id: doc.id,
      sequenceNumber: (data['sequenceNumber'] as num?)?.toInt() ?? 0,
      scheduledDate: ts(data['scheduledDate']) ?? DateTime.now(),
      status: FollowUpStatus.fromName(data['status'] as String?),
      scheduleRuleId: data['scheduleRuleId'] as String?,
      reminderSentAt: ts(data['reminderSentAt']),
      reminderCount: (data['reminderCount'] as num?)?.toInt() ?? 0,
      submittedAt: ts(data['submittedAt']),
      confirmedAt: ts(data['confirmedAt']),
      confirmedBy: data['confirmedBy'] as String?,
      confirmationNotes: data['confirmationNotes'] as String?,
      completedAt: ts(data['completedAt']),
      completedBy: data['completedBy'] as String?,
      manualCompletionReason: data['manualCompletionReason'] as String?,
      originalScheduledDate: ts(data['originalScheduledDate']),
      rescheduledAt: ts(data['rescheduledAt']),
      rescheduledBy: data['rescheduledBy'] as String?,
      rescheduleReason: data['rescheduleReason'] as String?,
      raw: data,
    );
  }
}
