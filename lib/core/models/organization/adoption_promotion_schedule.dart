import 'package:cloud_firestore/cloud_firestore.dart';

/// How often an organization reminds its staff to post adoptable animals
/// to its Facebook Page. Mirrors `organizations/{orgId}/integrations/
/// facebookPromotion`, written only by the backend
/// (functions/adoption_promotion.js; facebookPublishAnimalRecords stamps
/// [lastPostedAt]). Nothing is posted on its own: at each slot, people
/// allowed to share to Facebook get a reminder with suggested animals.
///
/// Keep the option lists equal to functions/adoption_promotion_rules.js.
class AdoptionPromotionSchedule {
  static const intervalWeekOptions = [1, 2, 4];
  static const minAnimalsPerPost = 1;
  static const maxAnimalsPerPost = 6;

  /// Scheduled reminders on/off.
  final bool enabled;

  /// Extra nudges between slots when animals have never been shared or
  /// have waited a while without applicants.
  final bool smartSuggestions;
  final int intervalWeeks;

  /// 1 = Monday .. 7 = Sunday (DateTime.weekday), Manila time.
  final int dayOfWeek;

  /// 0..23, Manila time.
  final int hour;
  final int animalsPerPost;
  final DateTime? nextDueAt;
  final DateTime? lastReminderAt;
  final DateTime? lastPostedAt;
  final String? lastPostUrl;
  final List<String> lastSuggestedIds;

  const AdoptionPromotionSchedule({
    this.enabled = false,
    this.smartSuggestions = false,
    this.intervalWeeks = 1,
    this.dayOfWeek = DateTime.saturday,
    this.hour = 10,
    this.animalsPerPost = 3,
    this.nextDueAt,
    this.lastReminderAt,
    this.lastPostedAt,
    this.lastPostUrl,
    this.lastSuggestedIds = const [],
  });

  /// The defaults shown before an Admin sets anything.
  static const initial = AdoptionPromotionSchedule();

  bool get isOff => !enabled && !smartSuggestions;

  factory AdoptionPromotionSchedule.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    DateTime? asDate(Object? v) => v is Timestamp ? v.toDate() : null;
    int pick(Object? v, int fallback, bool Function(int) ok) => v is int && ok(v) ? v : fallback;
    return AdoptionPromotionSchedule(
      enabled: d['enabled'] == true,
      smartSuggestions: d['smartSuggestions'] == true,
      intervalWeeks: pick(d['intervalWeeks'], 1, intervalWeekOptions.contains),
      dayOfWeek: pick(d['dayOfWeek'], DateTime.saturday, (v) => v >= 1 && v <= 7),
      hour: pick(d['hour'], 10, (v) => v >= 0 && v <= 23),
      animalsPerPost: pick(d['animalsPerPost'], 3, (v) => v >= minAnimalsPerPost && v <= maxAnimalsPerPost),
      nextDueAt: asDate(d['nextDueAt']),
      lastReminderAt: asDate(d['lastReminderAt']),
      lastPostedAt: asDate(d['lastPostedAt']),
      lastPostUrl: d['lastPostUrl'] as String?,
      lastSuggestedIds: (d['lastSuggestedIds'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// What facebookSaveAdoptionPromotion accepts.
  Map<String, dynamic> toCallableMap() => {
    'enabled': enabled,
    'smartSuggestions': smartSuggestions,
    'intervalWeeks': intervalWeeks,
    'dayOfWeek': dayOfWeek,
    'hour': hour,
    'animalsPerPost': animalsPerPost,
  };

  AdoptionPromotionSchedule copyWith({
    bool? enabled,
    bool? smartSuggestions,
    int? intervalWeeks,
    int? dayOfWeek,
    int? hour,
    int? animalsPerPost,
  }) =>
      AdoptionPromotionSchedule(
        enabled: enabled ?? this.enabled,
        smartSuggestions: smartSuggestions ?? this.smartSuggestions,
        intervalWeeks: intervalWeeks ?? this.intervalWeeks,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        hour: hour ?? this.hour,
        animalsPerPost: animalsPerPost ?? this.animalsPerPost,
        nextDueAt: nextDueAt,
        lastReminderAt: lastReminderAt,
        lastPostedAt: lastPostedAt,
        lastPostUrl: lastPostUrl,
        lastSuggestedIds: lastSuggestedIds,
      );

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static String weekdayLabel(int day) => _weekdays[(day - 1).clamp(0, 6)];

  static String hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:00 ${hour < 12 ? 'AM' : 'PM'}';
  }

  static String intervalLabel(int weeks) => switch (weeks) {
    1 => 'Every week',
    2 => 'Every 2 weeks',
    _ => 'Every 4 weeks',
  };

  /// e.g. "Every week on Saturday at 10:00 AM".
  String get summary {
    final parts = <String>[];
    if (enabled) {
      parts.add('${intervalLabel(intervalWeeks)} on ${weekdayLabel(dayOfWeek)} at ${hourLabel(hour)}');
    }
    if (smartSuggestions) parts.add(enabled ? 'plus smart suggestions' : 'Smart suggestions only');
    return parts.isEmpty ? 'No reminders' : parts.join(', ');
  }
}

/// One animal open for adoption, as facebookAdoptionPromotionSuggestions
/// ranks it (most in need of a post first).
class PromotionCandidate {
  final String id;
  final String name;
  final bool neverShared;
  final bool hasApplicants;
  final bool waiting;
  final DateTime? lastSharedAt;

  const PromotionCandidate({
    required this.id,
    required this.name,
    this.neverShared = false,
    this.hasApplicants = false,
    this.waiting = false,
    this.lastSharedAt,
  });

  factory PromotionCandidate.fromMap(Map<String, dynamic> m) {
    final last = m['lastSharedMs'];
    return PromotionCandidate(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      neverShared: m['neverShared'] == true,
      hasApplicants: m['hasApplicants'] == true,
      waiting: m['waiting'] == true,
      lastSharedAt: last is num ? DateTime.fromMillisecondsSinceEpoch(last.toInt()) : null,
    );
  }

  /// Short reason shown under the name.
  String get reason {
    if (neverShared) return hasApplicants ? 'Never shared · has applicants' : 'Never shared';
    if (waiting) return 'Waiting without applicants';
    if (hasApplicants) return 'Has applicants';
    return 'Shared before';
  }
}

class PromotionSuggestions {
  final List<PromotionCandidate> animals;
  final List<String> suggestedIds;
  final String caption;
  final int animalsPerPost;

  const PromotionSuggestions({
    required this.animals,
    required this.suggestedIds,
    required this.caption,
    required this.animalsPerPost,
  });
}
