/// The one way dates are shown: `Nov 12, 2026`, `3:05 PM`,
/// `Nov 12, 2026 · 3:05 PM`.
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `Nov 12, 2026`
String formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// `3:05 PM`
String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// `Nov 12, 2026 · 3:05 PM`
String formatDateTime(DateTime d) => '${formatDate(d)} · ${formatTime(d)}';

/// [formatDate], or [fallback] when there is no date.
String formatDateOr(DateTime? d, String fallback) => d == null ? fallback : formatDate(d);

/// [formatDateTime], or [fallback] when there is no date.
String formatDateTimeOr(DateTime? d, String fallback) => d == null ? fallback : formatDateTime(d);
