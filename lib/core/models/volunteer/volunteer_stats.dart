import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Recognition a volunteer earns from attended events. Ids, thresholds and
/// order match functions/volunteer_stats.js, which decides who has them.
enum VolunteerBadge {
  firstEvent('first_event', 'First event', 'Came to a first volunteer event', Icons.pets, minEvents: 1),
  helpingPaw('helping_paw', 'Helping paw', 'Came to 5 events', Icons.volunteer_activism, minEvents: 5),
  regular('regular', 'Regular', 'Came to 10 events', Icons.star_outline, minEvents: 10),
  champion('champion', 'Champion', 'Came to 25 events', Icons.emoji_events_outlined, minEvents: 25),
  communityHelper('community_helper', 'Community helper', 'Helped 3 different organizations', Icons.groups_outlined,
      minOrganizations: 3);

  const VolunteerBadge(this.id, this.label, this.description, this.icon, {this.minEvents, this.minOrganizations});

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final int? minEvents;
  final int? minOrganizations;

  static VolunteerBadge? fromId(String id) {
    for (final b in values) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// The attendance badges, lowest first.
  static List<VolunteerBadge> get eventTiers => [for (final b in values) if (b.minEvents != null) b];
}

/// `users/{uid}.volunteerStats`, written by the syncVolunteerStats function
/// from staff-marked attendance. Users can't write it (firestore.rules).
class VolunteerStats {
  const VolunteerStats({
    required this.attendedCount,
    required this.organizationCount,
    required this.badges,
    this.firstAttendedAt,
    this.lastAttendedAt,
  });

  final int attendedCount;
  final int organizationCount;

  /// Earned badges in [VolunteerBadge] order; unknown ids are skipped.
  final List<VolunteerBadge> badges;
  final DateTime? firstAttendedAt;
  final DateTime? lastAttendedAt;

  /// Null when the user has no stats yet (never attended, or attendance
  /// marked before the function was deployed and not backfilled).
  static VolunteerStats? fromUserData(Map<String, dynamic>? user) {
    final raw = user?['volunteerStats'];
    if (raw is! Map) return null;
    final ids = raw['badges'] is List ? (raw['badges'] as List).whereType<String>().toSet() : const <String>{};
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    return VolunteerStats(
      attendedCount: (raw['attendedCount'] as num?)?.toInt() ?? 0,
      organizationCount: (raw['organizationCount'] as num?)?.toInt() ?? 0,
      badges: [for (final b in VolunteerBadge.values) if (ids.contains(b.id)) b],
      firstAttendedAt: date(raw['firstAttendedAt']),
      lastAttendedAt: date(raw['lastAttendedAt']),
    );
  }

  /// The next attendance badge not yet earned, or null once all are.
  VolunteerBadge? get nextEventBadge {
    for (final b in VolunteerBadge.eventTiers) {
      if (attendedCount < b.minEvents!) return b;
    }
    return null;
  }

  /// Events still needed for [nextEventBadge] (0 when there is none).
  int get eventsToNextBadge {
    final next = nextEventBadge;
    return next == null ? 0 : next.minEvents! - attendedCount;
  }
}
