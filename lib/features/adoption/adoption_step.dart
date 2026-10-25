// Extracted from adoption_process.dart (behavior-preserving refactor).

/// The adoption workflow's steps — the single source of truth for which
/// screen the applicant sees (see AdoptionProcess / its step widgets).
enum AdoptionStep {
  intro, // 1st step - Lets start
  bookAppointment, // 2nd step  – Book appointment
  appReview, // 3rd step  – Application review
  timeToMeet, // 4th step  – Appointment confirmed
  adoptionDay, // 5th step  – Adoption Day! (success)
  appReject, // 5th step  – Application Update (rejected)
  withdrawn, // 5th step  – Application withdrawn by adopter
}

/// Labels for the five tracker circles, left to right.
const List<String> kAdoptionStepLabels = [
  'Fill out adoption form',
  'Book appointment',
  'Application review',
  'Time to meet!',
  'Adoption Day',
];

/// The five tracker circles' steps, left to right.
const List<AdoptionStep> kAdoptionTrackerSteps = [
  AdoptionStep.intro,
  AdoptionStep.bookAppointment,
  AdoptionStep.appReview,
  AdoptionStep.timeToMeet,
  AdoptionStep.adoptionDay,
];

/// Which tracker circle is "current" for [step]. Rejected and withdrawn
/// applications stay on the review circle.
int adoptionTrackerIndex(AdoptionStep step) {
  switch (step) {
    case AdoptionStep.intro:
      return 0;
    case AdoptionStep.bookAppointment:
      return 1;
    case AdoptionStep.appReview:
      return 2;
    case AdoptionStep.timeToMeet:
      return 3;
    case AdoptionStep.adoptionDay:
      return 4;
    case AdoptionStep.appReject:
      return 2; // rejected stays at review
    case AdoptionStep.withdrawn:
      return 2; // withdrawn stays at review
  }
}

/// Application statuses that mean the animal has actually been released to
/// the adopter (so a `scheduledReleaseDate` on the doc is final, not a
/// draft the admin is still configuring).
const Set<String> kAdoptionReleasedStatuses = {
  'adopted',
  'completed',
  'return_requested',
  'return_approved',
};

// Recognizes both the canonical statuses the admin Adoption Application
// Review module now writes (pending/interview/approved/adopted) and the
// legacy values this form used to write on its own before that module
// existed — so an application submitted before this change still resumes
// at the right step. See AdoptionStatus.fromFirestoreValue for the same
// mapping used admin-side.
// [hasAppointment]: a Pending application with an already-booked
// appointment (booked but not yet admin-confirmed — the applicant's own
// booking no longer advances status itself) should resume on the Review
// step, not send the applicant back to re-book.
AdoptionStep adoptionStepForStatus(
  String? status, {
  required bool hasAppointment,
}) {
  switch (status) {
    case 'pending':
    case 'pending_appointment':
      return hasAppointment
          ? AdoptionStep.appReview
          : AdoptionStep.bookAppointment;
    case 'interview':
    case 'under_review':
      return AdoptionStep.appReview;
    case 'approved':
    case 'appointment_confirmed':
      return AdoptionStep.timeToMeet;
    case 'adopted':
    case 'completed':
    case 'return_requested':
    case 'return_approved':
      return AdoptionStep.adoptionDay;
    case 'rejected':
      return AdoptionStep.appReject;
    case 'withdrawn':
      return AdoptionStep.withdrawn;
    default:
      return AdoptionStep.intro;
  }
}

/// The step a saved application resumes on. Same as
/// [adoptionStepForStatus], except that the backend flips status to
/// 'adopted' the moment the org schedules the release (which may be a
/// future date/time) — the adopter shouldn't see "Adoption Day" until that
/// [scheduledReleaseDate] has actually arrived. Until then, stay on "Time
/// to Meet" so the delivery date/time, attempts, and reschedule option
/// remain visible and actionable.
AdoptionStep resolveAdoptionStep(
  String? status, {
  required bool hasAppointment,
  DateTime? scheduledReleaseDate,
  required DateTime now,
}) {
  final step = adoptionStepForStatus(status, hasAppointment: hasAppointment);
  if (step == AdoptionStep.adoptionDay &&
      scheduledReleaseDate != null &&
      now.isBefore(scheduledReleaseDate)) {
    return AdoptionStep.timeToMeet;
  }
  return step;
}
