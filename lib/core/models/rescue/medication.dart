import 'package:cloud_firestore/cloud_firestore.dart';

/// A standing medication order for an animal in the shelter, stored at
/// `animals/{animalId}/medications/{planId}`. Admins create and end plans;
/// carers record each dose they give (see [MedicationDose]).
class MedicationPlan {
  final String id;
  final String animalId;
  final String drug;
  final String dose;
  final int timesPerDay;
  final DateTime startDate;
  final DateTime? endDate;
  final bool active;
  final String? createdBy;

  const MedicationPlan({
    required this.id,
    required this.animalId,
    required this.drug,
    required this.dose,
    required this.timesPerDay,
    required this.startDate,
    this.endDate,
    this.active = true,
    this.createdBy,
  });

  /// Whether a dose is expected on [day] (calendar date, time ignored).
  bool isScheduledOn(DateTime day) {
    final d = dayOnly(day);
    if (!active || d.isBefore(dayOnly(startDate))) return false;
    if (endDate != null && d.isAfter(dayOnly(endDate!))) return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'animalId': animalId,
        'drug': drug,
        'dose': dose,
        'timesPerDay': timesPerDay,
        'startDate': Timestamp.fromDate(dayOnly(startDate)),
        if (endDate != null) 'endDate': Timestamp.fromDate(dayOnly(endDate!)),
        'active': active,
        if (createdBy != null) 'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory MedicationPlan.fromDoc(String id, Map<String, dynamic> data) => MedicationPlan(
        id: id,
        animalId: data['animalId'] as String? ?? '',
        drug: data['drug'] as String? ?? '',
        dose: data['dose'] as String? ?? '',
        timesPerDay: (data['timesPerDay'] as num?)?.toInt().clamp(1, 4) ?? 1,
        startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        endDate: (data['endDate'] as Timestamp?)?.toDate(),
        active: data['active'] as bool? ?? true,
        createdBy: data['createdBy'] as String?,
      );
}

/// One dose given (or to be given) on a day. Stored at
/// `animals/{animalId}/medicationDoses/{doseId}`, where [doseIdFor] makes
/// the id deterministic so a slot can only be recorded once.
class MedicationDose {
  final String id;
  final String planId;
  final String animalId;
  final DateTime day;
  final int slot;
  final String givenBy;
  final String? givenByName;
  final DateTime? givenAt;
  final List<String> mediaUrls;
  final String? note;

  const MedicationDose({
    required this.id,
    required this.planId,
    required this.animalId,
    required this.day,
    required this.slot,
    required this.givenBy,
    this.givenByName,
    this.givenAt,
    this.mediaUrls = const [],
    this.note,
  });

  factory MedicationDose.fromDoc(String id, Map<String, dynamic> data) => MedicationDose(
        id: id,
        planId: data['planId'] as String? ?? '',
        animalId: data['animalId'] as String? ?? '',
        day: (data['day'] as Timestamp?)?.toDate() ?? DateTime.now(),
        slot: (data['slot'] as num?)?.toInt() ?? 1,
        givenBy: data['givenBy'] as String? ?? '',
        givenByName: data['givenByName'] as String?,
        givenAt: (data['givenAt'] as Timestamp?)?.toDate(),
        mediaUrls: List<String>.from(data['mediaUrls'] as List? ?? const []),
        note: data['note'] as String?,
      );
}

/// Where a scheduled slot stands on a given day.
enum DoseStatus {
  /// Recorded as given.
  given,
  /// Today, not yet given.
  due,
  /// A past day with no record (shown to admins as missed).
  missed,
  /// A future day.
  upcoming;

  String get label => switch (this) {
        DoseStatus.given => 'Given',
        DoseStatus.due => 'Due today',
        DoseStatus.missed => 'Missed',
        DoseStatus.upcoming => 'Upcoming',
      };
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Deterministic id: `{planId}_{yyyy-MM-dd}_{slot}`.
String doseIdFor(String planId, DateTime day, int slot) {
  final d = dayOnly(day);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${planId}_${d.year}-$mm-${dd}_$slot';
}

/// Status of [slot] on [day]. [doses] is keyed by dose id. [now] is injected
/// so this stays pure and testable.
DoseStatus doseStatusFor({
  required String planId,
  required DateTime day,
  required int slot,
  required Map<String, MedicationDose> doses,
  required DateTime now,
}) {
  if (doses.containsKey(doseIdFor(planId, day, slot))) return DoseStatus.given;
  final d = dayOnly(day);
  final today = dayOnly(now);
  if (d == today) return DoseStatus.due;
  if (d.isBefore(today)) return DoseStatus.missed;
  return DoseStatus.upcoming;
}

/// Counts missed slots for [plans] across the days from [from] to [to]
/// (inclusive). Used for the admin "missed doses" figure.
int countMissedDoses({
  required List<MedicationPlan> plans,
  required Map<String, MedicationDose> doses,
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  var missed = 0;
  for (final plan in plans) {
    for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = d.add(const Duration(days: 1))) {
      if (!plan.isScheduledOn(d)) continue;
      for (var slot = 1; slot <= plan.timesPerDay; slot++) {
        if (doseStatusFor(
              planId: plan.id,
              day: d,
              slot: slot,
              doses: doses,
              now: now,
            ) ==
            DoseStatus.missed) {
          missed++;
        }
      }
    }
  }
  return missed;
}
