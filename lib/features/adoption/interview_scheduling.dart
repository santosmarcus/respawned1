/// Interview-appointment scheduling template — shared by the user's "Book
/// appointment" step (adoption_process.dart) and the admin's interview
/// Reschedule action (adoption_application_detail_page.dart /
/// interview_reschedule_sheet.dart) so both read the exact same visit types
/// and day-of-week time slots instead of two independently-maintained
/// copies. Promoted out of adoption_process.dart, where these values used
/// to live as a private field — no values changed.
library;

const List<String> kInterviewTypes = ['On-site Visit', 'Online'];

// Weekday-indexed (0 = Monday ... 6 = Sunday, closed) available time slots.
const Map<int, List<String>> kInterviewTimeSlots = {
  0: ['9:00 AM', '10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
  1: ['9:00 AM', '10:00 AM', '11:00 AM', '1:00 PM', '2:00 PM', '3:00 PM', '4:00 PM'],
  2: ['10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM'],
  3: ['9:00 AM', '10:00 AM', '11:00 AM', '1:00 PM', '3:00 PM', '4:00 PM'],
  4: ['9:00 AM', '10:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
  5: ['10:00 AM', '11:00 AM', '12:00 PM'],
  6: [], // Sunday – closed
};

bool isInterviewClosedDay(DateTime date) => date.weekday == DateTime.sunday;

List<String> interviewSlotsForDate(DateTime date) {
  final dow = (date.weekday - 1) % 7;
  return kInterviewTimeSlots[dow] ?? const [];
}

/// Combines an appointment date with one of this file's own "9:00 AM"-style
/// time slot strings into a real DateTime — used to gate the admin's
/// Complete Interview action on whether the scheduled time has actually
/// arrived yet. Falls back to just the date (midnight) if the time string
/// doesn't parse, so a malformed/legacy value never crashes the check.
DateTime combineInterviewDateTime(DateTime date, String? time) {
  if (time == null) return date;
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(time.trim());
  if (match == null) return date;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final isPm = match.group(3)!.toUpperCase() == 'PM';
  if (isPm && hour != 12) hour += 12;
  if (!isPm && hour == 12) hour = 0;
  return DateTime(date.year, date.month, date.day, hour, minute);
}
