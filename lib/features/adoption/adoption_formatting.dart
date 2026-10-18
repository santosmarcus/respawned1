// Extracted from adoption_process.dart (behavior-preserving refactor).

/// "January 5, 2026" — same format the adoption screens always used.
String formatAdoptionDate(DateTime d) =>
    '${_monthName(d.month)} ${d.day}, ${d.year}';

/// "3:05 PM".
String formatAdoptionTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

String _monthName(int m) => const [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][m];
