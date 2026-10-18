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
