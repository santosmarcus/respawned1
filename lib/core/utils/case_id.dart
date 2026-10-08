/// Canonical short "Case ID" shown to every user type (reporter/general
/// user, admin/NGO staff, pet transporter) for a `cases/{caseId}` document.
///
/// Before this existed, different screens truncated the same Firestore
/// doc ID to different lengths — 5 characters on several admin screens
/// (rescue_detail_page.dart, treatment_detail_page.dart, etc.) vs 7
/// characters everywhere else (the reporter's own track_case_page.dart,
/// notifications, activity feed, history, pet-transporter notifications).
/// The same case therefore displayed a different-looking "Case ID" — e.g.
/// "2N5EK" to an admin but "2N5EKXX" to the reporter for the exact same
/// case — making it impossible to cross-reference a case by ID between
/// user types. Every display of a shortened case ID should call this
/// function instead of truncating inline.
String shortCaseId(String? id) {
  if (id == null || id.isEmpty) return '-';
  return id.length >= 7 ? id.substring(0, 7).toUpperCase() : id.toUpperCase();
}
