/// A reporting window and the one it is compared with.
class Period {
  final DateTime from;
  final DateTime to;
  final Period? explicitPrevious;
  const Period(this.from, this.to, {Period? previous}) : explicitPrevious = previous;

  /// The comparison window: the previous calendar month or quarter for
  /// those ranges, otherwise the same length immediately before.
  Period get previous => explicitPrevious ?? Period(from.subtract(to.difference(from)), from);
  bool has(DateTime? t) => t != null && !t.isBefore(from) && t.isBefore(to);
}

enum AnalyticsRangeKind { lastDays, month, quarter, custom }

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Analytics gap 2: what the admin picked in the Analytics period menu.
/// A rolling window (30 / 90 / 365 days), a calendar month, a calendar
/// quarter, or a custom date range (whole days, end day included).
class AnalyticsRange {
  final AnalyticsRangeKind kind;
  final int days;
  final int year;
  final int index; // month 1-12 or quarter 1-4
  final DateTime? start;
  final DateTime? end; // inclusive day

  const AnalyticsRange.lastDays(this.days)
      : kind = AnalyticsRangeKind.lastDays,
        year = 0,
        index = 0,
        start = null,
        end = null;

  const AnalyticsRange.month(this.year, this.index)
      : kind = AnalyticsRangeKind.month,
        days = 0,
        start = null,
        end = null;

  const AnalyticsRange.quarter(this.year, this.index)
      : kind = AnalyticsRangeKind.quarter,
        days = 0,
        start = null,
        end = null;

  AnalyticsRange.custom(DateTime from, DateTime toInclusive)
      : kind = AnalyticsRangeKind.custom,
        days = 0,
        year = 0,
        index = 0,
        start = DateTime(from.year, from.month, from.day),
        end = DateTime(toInclusive.year, toInclusive.month, toInclusive.day);

  /// The window for this range as of [now]. Calendar ranges that include
  /// today stop at [now].
  Period period(DateTime now) {
    switch (kind) {
      case AnalyticsRangeKind.lastDays:
        return Period(now.subtract(Duration(days: days)), now);
      case AnalyticsRangeKind.month:
        final from = DateTime(year, index);
        final to = DateTime(year, index + 1);
        return Period(from, _cap(to, now), previous: Period(DateTime(year, index - 1), from));
      case AnalyticsRangeKind.quarter:
        final from = DateTime(year, (index - 1) * 3 + 1);
        final to = DateTime(year, (index - 1) * 3 + 4);
        return Period(from, _cap(to, now), previous: Period(DateTime(year, (index - 1) * 3 - 2), from));
      case AnalyticsRangeKind.custom:
        final to = end!.add(const Duration(days: 1));
        return Period(start!, _cap(to, now));
    }
  }

  static DateTime _cap(DateTime to, DateTime now) => to.isAfter(now) ? now : to;

  String get label => switch (kind) {
        AnalyticsRangeKind.lastDays => days == 365 ? 'Last 12 months' : 'Last $days days',
        AnalyticsRangeKind.month => '${_monthNames[index - 1]} $year',
        AnalyticsRangeKind.quarter => 'Q$index $year',
        AnalyticsRangeKind.custom => start!.year == end!.year
            ? '${_monthNames[start!.month - 1]} ${start!.day} – ${_monthNames[end!.month - 1]} ${end!.day}, ${end!.year}'
            : '${_monthNames[start!.month - 1]} ${start!.day}, ${start!.year} – '
                '${_monthNames[end!.month - 1]} ${end!.day}, ${end!.year}',
      };

  /// What the comparison is called in the cards ("vs Oct 2026").
  String get previousLabel => switch (kind) {
        AnalyticsRangeKind.month =>
          index == 1 ? '${_monthNames[11]} ${year - 1}' : '${_monthNames[index - 2]} $year',
        AnalyticsRangeKind.quarter => index == 1 ? 'Q4 ${year - 1}' : 'Q${index - 1} $year',
        _ => 'previous period',
      };

  /// A short slug for file names.
  String get fileSlug => switch (kind) {
        AnalyticsRangeKind.lastDays => 'last_${days}d',
        AnalyticsRangeKind.month => '$year-${index.toString().padLeft(2, '0')}',
        AnalyticsRangeKind.quarter => '$year-Q$index',
        AnalyticsRangeKind.custom =>
          '${start!.toIso8601String().substring(0, 10)}_to_${end!.toIso8601String().substring(0, 10)}',
      };

  @override
  bool operator ==(Object other) =>
      other is AnalyticsRange &&
      other.kind == kind &&
      other.days == days &&
      other.year == year &&
      other.index == index &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, days, year, index, start, end);
}
