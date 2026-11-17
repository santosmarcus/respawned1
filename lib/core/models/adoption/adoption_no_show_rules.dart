/// Missed adoption interviews (pending the organization's confirmation):
/// the first no-show lets the applicant book one more interview, the second
/// closes the application. Keep equal to MAX_INTERVIEW_NO_SHOWS in
/// functions/adoption_stall_rules.js.
const int kMaxInterviewNoShows = 2;

/// The reason written on an application closed by a second no-show.
const String kNoShowClosedReason = 'Did not attend the interview twice';

enum NoShowOutcome {
  /// Back to Pending with the appointment cleared: they may book again.
  rebook,

  /// Closed as rejected with [kNoShowClosedReason].
  close,
}

/// What recording a no-show does, given how many the application has had
/// before it (a legacy application with only `noShowAt` counts as one).
NoShowOutcome noShowOutcome({required int previousNoShows}) =>
    previousNoShows + 1 >= kMaxInterviewNoShows ? NoShowOutcome.close : NoShowOutcome.rebook;

/// How many no-shows an application has had, from its raw data.
int noShowCountOf(Map<String, dynamic> data) {
  final n = data['noShowCount'];
  if (n is num) return n.toInt();
  return data['noShowAt'] != null ? 1 : 0;
}
