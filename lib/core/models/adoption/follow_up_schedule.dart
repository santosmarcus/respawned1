import 'package:cloud_firestore/cloud_firestore.dart';

/// One follow-up schedule rule ("Every [value] [unit] for [value] [unit]"),
/// spec section 3. A release can chain several of these consecutively (see
/// [StartMode.afterPreviousRule]) — this is the persisted configuration, not
/// just the dates it produces (see generateFollowUpDates below for that).

enum IntervalUnit {
  day,
  week,
  month;

  String get label => switch (this) {
        IntervalUnit.day => 'day',
        IntervalUnit.week => 'week',
        IntervalUnit.month => 'month',
      };

  static IntervalUnit fromName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => IntervalUnit.week);
}

enum DurationUnit {
  week,
  month,
  year;

  String get label => switch (this) {
        DurationUnit.week => 'week',
        DurationUnit.month => 'month',
        DurationUnit.year => 'year',
      };

  static DurationUnit fromName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => DurationUnit.month);
}

/// How a rule's own start date is anchored. [releaseDate] and [afterRelease]
/// currently resolve identically (both anchor at the release date) — kept as
/// distinct values for schema completeness since the spec lists them
/// separately, and because "first follow-up = anchor + interval" already
/// guarantees neither produces a Day-0 check-in.
enum StartMode {
  releaseDate,
  afterRelease,
  afterPreviousRule,
  customDate;

  static StartMode fromName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => StartMode.releaseDate);
}

/// Calendar-aware month/year addition — never approximates a month as 30
/// days. Clamps the day-of-month down if the target month is shorter (e.g.
/// Jan 31 + 1 month -> Feb 28/29).
DateTime addCalendarMonths(DateTime d, int months) {
  final totalMonths = d.month - 1 + months;
  final year = d.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = d.day > lastDayOfMonth ? lastDayOfMonth : d.day;
  return DateTime(year, month, day);
}

DateTime _addInterval(DateTime d, int value, IntervalUnit unit) => switch (unit) {
      IntervalUnit.day => d.add(Duration(days: value)),
      IntervalUnit.week => d.add(Duration(days: value * 7)),
      IntervalUnit.month => addCalendarMonths(d, value),
    };

DateTime _addDuration(DateTime d, int value, DurationUnit unit) => switch (unit) {
      DurationUnit.week => d.add(Duration(days: value * 7)),
      DurationUnit.month => addCalendarMonths(d, value),
      DurationUnit.year => addCalendarMonths(d, value * 12),
    };

class FollowUpScheduleRule {
  final String ruleId;
  final int order;
  final int intervalValue;
  final IntervalUnit intervalUnit;
  final int durationValue;
  final DurationUnit durationUnit;
  final StartMode startMode;
  final DateTime? customStartDate;
  final String? previousRuleId;
  final DateTime? createdAt;
  final String? createdBy;

  const FollowUpScheduleRule({
    required this.ruleId,
    required this.order,
    required this.intervalValue,
    required this.intervalUnit,
    required this.durationValue,
    required this.durationUnit,
    required this.startMode,
    this.customStartDate,
    this.previousRuleId,
    this.createdAt,
    this.createdBy,
  });

  String get frequencyLabel => 'Every ${intervalValue == 1 ? '' : '$intervalValue '}${intervalUnit.label}${intervalValue == 1 ? '' : 's'}';
  String get durationLabel => 'For $durationValue ${durationUnit.label}${durationValue == 1 ? '' : 's'}';
  String get startLabel => switch (startMode) {
        StartMode.releaseDate => 'On release date',
        StartMode.afterRelease => 'After release',
        StartMode.afterPreviousRule => 'After previous schedule',
        StartMode.customDate => 'Custom date',
      };

  FollowUpScheduleRule copyWith({
    int? order,
    int? intervalValue,
    IntervalUnit? intervalUnit,
    int? durationValue,
    DurationUnit? durationUnit,
    StartMode? startMode,
    DateTime? customStartDate,
    bool clearCustomStartDate = false,
    String? previousRuleId,
    bool clearPreviousRuleId = false,
  }) {
    return FollowUpScheduleRule(
      ruleId: ruleId,
      order: order ?? this.order,
      intervalValue: intervalValue ?? this.intervalValue,
      intervalUnit: intervalUnit ?? this.intervalUnit,
      durationValue: durationValue ?? this.durationValue,
      durationUnit: durationUnit ?? this.durationUnit,
      startMode: startMode ?? this.startMode,
      customStartDate: clearCustomStartDate ? null : (customStartDate ?? this.customStartDate),
      previousRuleId: clearPreviousRuleId ? null : (previousRuleId ?? this.previousRuleId),
      createdAt: createdAt,
      createdBy: createdBy,
    );
  }

  // NOTE: this map is always written nested inside the `followUpSchedules`
  // array field, never as a standalone document — Firestore does not
  // support FieldValue.serverTimestamp() inside arrays, so createdAt must
  // already be a concrete client-side value (see the repository call sites,
  // which always pass one) rather than defaulting to a sentinel here.
  Map<String, dynamic> toMap() => {
        'ruleId': ruleId,
        'order': order,
        'intervalValue': intervalValue,
        'intervalUnit': intervalUnit.name,
        'durationValue': durationValue,
        'durationUnit': durationUnit.name,
        'startMode': startMode.name,
        if (customStartDate != null) 'customStartDate': Timestamp.fromDate(customStartDate!),
        if (previousRuleId != null) 'previousRuleId': previousRuleId,
        'createdAt': Timestamp.fromDate(createdAt ?? DateTime.now()),
        if (createdBy != null) 'createdBy': createdBy,
      };

  factory FollowUpScheduleRule.fromMap(Map<String, dynamic> map) {
    final customStart = map['customStartDate'];
    final created = map['createdAt'];
    return FollowUpScheduleRule(
      ruleId: map['ruleId'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      intervalValue: (map['intervalValue'] as num?)?.toInt() ?? 1,
      intervalUnit: IntervalUnit.fromName(map['intervalUnit'] as String?),
      durationValue: (map['durationValue'] as num?)?.toInt() ?? 1,
      durationUnit: DurationUnit.fromName(map['durationUnit'] as String?),
      startMode: StartMode.fromName(map['startMode'] as String?),
      customStartDate: customStart is Timestamp ? customStart.toDate() : null,
      previousRuleId: map['previousRuleId'] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
      createdBy: map['createdBy'] as String?,
    );
  }
}

/// One generated follow-up date tagged with the rule that produced it —
/// used to stamp `scheduleRuleId` on each created FollowUp record.
typedef GeneratedFollowUpDate = ({DateTime date, String ruleId});

DateTime _resolveAnchor({
  required FollowUpScheduleRule rule,
  required DateTime releaseDate,
  required Map<String, List<DateTime>> datesByRuleId,
  required Map<String, FollowUpScheduleRule> rulesById,
  Set<String>? visiting,
}) {
  switch (rule.startMode) {
    case StartMode.releaseDate:
    case StartMode.afterRelease:
      return releaseDate;
    case StartMode.customDate:
      return rule.customStartDate ?? releaseDate;
    case StartMode.afterPreviousRule:
      final prevId = rule.previousRuleId;
      if (prevId == null) return releaseDate;
      final prevDates = datesByRuleId[prevId];
      if (prevDates != null && prevDates.isNotEmpty) return prevDates.last;
      final prevRule = rulesById[prevId];
      // Guard against a cyclical previousRuleId chain (shouldn't happen from
      // the UI, but never infinite-loop on bad data).
      final seen = visiting ?? <String>{};
      if (prevRule == null || seen.contains(prevRule.ruleId)) return releaseDate;
      final prevAnchor = _resolveAnchor(
        rule: prevRule,
        releaseDate: releaseDate,
        datesByRuleId: datesByRuleId,
        rulesById: rulesById,
        visiting: {...seen, rule.ruleId},
      );
      // Previous rule produced no dates (e.g. a 1-day duration with a
      // longer interval) — fall back to its anchor plus its full duration
      // window, so chaining still advances forward.
      return _addDuration(prevAnchor, prevRule.durationValue, prevRule.durationUnit);
  }
}

List<DateTime> _generateDatesForRule(FollowUpScheduleRule rule, DateTime anchor) {
  final cutoff = _addDuration(anchor, rule.durationValue, rule.durationUnit);
  final dates = <DateTime>[];
  var current = anchor;
  while (true) {
    final next = _addInterval(current, rule.intervalValue, rule.intervalUnit);
    if (next.isAfter(cutoff)) break;
    dates.add(next);
    current = next;
  }
  return dates;
}

/// Combined, chronological, deduped (by calendar day) preview across every
/// rule in [rules] — reorders by `order` first so `afterPreviousRule`
/// chaining always resolves against an already-generated predecessor.
/// First follow-up for each rule = its start anchor + one interval, never
/// the anchor date itself.
List<GeneratedFollowUpDate> generateFollowUpDates(List<FollowUpScheduleRule> rules, DateTime releaseDate) {
  final sorted = [...rules]..sort((a, b) => a.order.compareTo(b.order));
  final rulesById = {for (final r in sorted) r.ruleId: r};
  final datesByRuleId = <String, List<DateTime>>{};

  final tagged = <GeneratedFollowUpDate>[];
  for (final rule in sorted) {
    final anchor = _resolveAnchor(rule: rule, releaseDate: releaseDate, datesByRuleId: datesByRuleId, rulesById: rulesById);
    final dates = _generateDatesForRule(rule, anchor);
    datesByRuleId[rule.ruleId] = dates;
    for (final d in dates) {
      tagged.add((date: d, ruleId: rule.ruleId));
    }
  }

  tagged.sort((a, b) => a.date.compareTo(b.date));
  final seenDays = <String>{};
  final deduped = <GeneratedFollowUpDate>[];
  for (final t in tagged) {
    final key = '${t.date.year}-${t.date.month}-${t.date.day}';
    if (seenDays.add(key)) deduped.add(t);
  }
  return deduped;
}
