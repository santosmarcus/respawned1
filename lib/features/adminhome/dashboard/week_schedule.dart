import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/events_card.dart' show signUpText;

/// Within one day, items show in this order.
enum ScheduleKind {
  event(Icons.event),
  interview(Icons.record_voice_over),
  handover(Icons.home),
  followUp(Icons.fact_check),
  vaccine(Icons.vaccines),
  care(Icons.healing);

  const ScheduleKind(this.icon);
  final IconData icon;
}

class ScheduleItem {
  final ScheduleKind kind;

  /// Calendar day only.
  final DateTime day;
  final String? time;
  final String title;
  final String subtitle;
  final void Function(BuildContext context) open;

  const ScheduleItem({
    required this.kind,
    required this.day,
    required this.title,
    required this.subtitle,
    required this.open,
    this.time,
  });
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Everything with a recorded date from today through the next 6 days.
/// Only recorded dates are used: an interview without an appointment date
/// or a vaccine without a next-due date never appears. Items already past
/// due are left to Priority actions.
List<ScheduleItem> buildWeekSchedule({
  required DateTime now,
  List<AdoptionApplication> interviews = const [],
  List<AdoptionApplication> approved = const [],
  List<OpenFollowUp> followUps = const [],
  List<AnimalRecord> animals = const [],
  Map<String, List<VaccinationRecord>> vaccinations = const {},
  Map<String, List<CareRecord>> care = const {},
  List<VolunteerEvent> events = const [],
}) {
  final start = _day(now);
  final end = start.add(const Duration(days: 7));
  bool inWeek(DateTime? d) => d != null && !_day(d).isBefore(start) && _day(d).isBefore(end);
  String animalName(AnimalRecord a) => a.name.isNotEmpty ? a.name : '${a.species} (unnamed)';
  String petOf(AdoptionApplication a) => a.animalName.isEmpty ? 'animal' : a.animalName;

  final items = <ScheduleItem>[
    for (final e in events)
      if (!e.isCancelled && inWeek(e.startAt))
        ScheduleItem(
          kind: ScheduleKind.event,
          day: _day(e.startAt),
          time: e.time,
          title: e.title,
          subtitle: signUpText(e),
          open: (ctx) => openEvent(ctx, e.id),
        ),
    for (final a in interviews)
      if (a.interviewCompletedAt == null && a.noShowAt == null && inWeek(a.appointmentDate))
        ScheduleItem(
          kind: ScheduleKind.interview,
          day: _day(a.appointmentDate!),
          time: a.appointmentTime,
          title: 'Interview · ${petOf(a)}',
          subtitle: [a.adopterName, a.appointmentType].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          open: (ctx) => openApplication(ctx, a),
        ),
    for (final a in approved)
      if (a.releasedAt == null && inWeek(a.scheduledReleaseDate))
        ScheduleItem(
          kind: ScheduleKind.handover,
          day: _day(a.scheduledReleaseDate!),
          title: 'Handover · ${petOf(a)}',
          subtitle: a.adopterName,
          open: (ctx) => openApplication(ctx, a),
        ),
    for (final f in followUps)
      if (inWeek(f.record.scheduledDate))
        ScheduleItem(
          kind: ScheduleKind.followUp,
          day: _day(f.record.scheduledDate),
          title: 'Follow-up ${f.record.sequenceNumber > 0 ? '#${f.record.sequenceNumber} ' : ''}· ${petOf(f.app)}',
          subtitle: f.app.adopterName,
          open: (ctx) => openApplication(ctx, f.app),
        ),
    for (final a in animals) ...[
      // Latest dose per vaccine decides the next due date.
      for (final v in _latestPerVaccine(vaccinations[a.id] ?? const []))
        if (inWeek(v.nextDueDate))
          ScheduleItem(
            kind: ScheduleKind.vaccine,
            day: _day(v.nextDueDate),
            title: 'Vaccine due · ${animalName(a)}',
            subtitle: v.vaccineName,
            open: (ctx) => openAnimalRecord(ctx, a),
          ),
      for (final r in CareRecord.latestByType(care[a.id] ?? const []).values)
        if (inWeek(r.nextDueDate))
          ScheduleItem(
            kind: ScheduleKind.care,
            day: _day(r.nextDueDate!),
            title: '${r.type.label} due · ${animalName(a)}',
            subtitle: r.product?.isNotEmpty == true ? r.product! : 'Record it on the Medical tab',
            open: (ctx) => openAnimalRecord(ctx, a),
          ),
    ],
  ];
  // Stable: by day, then kind; insertion order breaks ties.
  final indexed = items.asMap().entries.toList()
    ..sort((x, y) {
      final byDay = x.value.day.compareTo(y.value.day);
      if (byDay != 0) return byDay;
      final byKind = x.value.kind.index.compareTo(y.value.kind.index);
      return byKind != 0 ? byKind : x.key.compareTo(y.key);
    });
  return [for (final e in indexed) e.value];
}

List<VaccinationRecord> _latestPerVaccine(List<VaccinationRecord> records) {
  final latest = <String, VaccinationRecord>{};
  for (final r in records) {
    final key = r.vaccineName.toLowerCase();
    if (!latest.containsKey(key) || r.dateAdministered.isAfter(latest[key]!.dateAdministered)) latest[key] = r;
  }
  return latest.values.toList();
}

const _shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dayHeading(DateTime day, DateTime now) {
  final diff = _day(day).difference(_day(now)).inDays;
  if (diff == 0) return 'Today · ${shortDate(day)}';
  if (diff == 1) return 'Tomorrow · ${shortDate(day)}';
  return '${_shortWeekdays[day.weekday - 1]} · ${shortDate(day)}';
}

class WeekScheduleCard extends ConsumerStatefulWidget {
  const WeekScheduleCard({super.key});

  @override
  ConsumerState<WeekScheduleCard> createState() => _WeekScheduleCardState();
}

class _WeekScheduleCardState extends ConsumerState<WeekScheduleCard> {
  static const _initial = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final interviews = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.interview)));
    final approved = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved)));
    final followUps = ref.watch(orgOpenFollowUpsProvider);
    final records = ref.watch(allAnimalRecordsProvider);
    final vax = ref.watch(vaccinationsByAnimalProvider);
    final care = ref.watch(careRecordsByAnimalProvider);
    final events = ref.watch(upcomingEventsProvider);

    final sources = <(AsyncValue<Object?>, String)>[
      (interviews, 'interviews'),
      (approved, 'handovers'),
      (followUps, 'follow-ups'),
      (records, 'animal records'),
      (vax, 'vaccinations'),
      (care, 'care records'),
      (events, 'events'),
    ];
    final failed = [for (final (v, name) in sources) if (v.hasError) name];
    final loading = sources.every((s) => !s.$1.hasValue && !s.$1.hasError);

    final now = DateTime.now();
    final items = buildWeekSchedule(
      now: now,
      interviews: interviews.asData?.value ?? const [],
      approved: approved.asData?.value ?? const [],
      followUps: followUps.asData?.value ?? const [],
      animals: (records.asData?.value ?? const <AnimalRecord>[]).where(isInCare).toList(),
      vaccinations: vax.asData?.value ?? const {},
      care: care.asData?.value ?? const {},
      events: events.asData?.value ?? const [],
    );
    final shown = _all ? items : items.take(_initial).toList();

    final children = <Widget>[];
    DateTime? currentDay;
    for (final item in shown) {
      if (item.day != currentDay) {
        currentDay = item.day;
        children.add(CardLabel(dayHeading(item.day, now)));
      }
      children.add(_ScheduleRow(item: item));
    }

    return SectionCard(
      icon: Icons.event_note,
      title: 'Next 7 days',
      trailing: items.isEmpty
          ? null
          : Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 1),
              decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '${items.length}',
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.background),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const DashLoading(label: 'Checking the calendar…')
          else if (items.isEmpty)
            const DashEmpty('Nothing scheduled in the next 7 days.', severity: DashSeverity.info)
          else
            ...children,
          if (items.length > _initial)
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Container(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _all ? 'Show less' : 'View all ${items.length}',
                      style: dashBody(size: 14, weight: FontWeight.w700),
                    ),
                    Icon(_all ? Icons.expand_less : Icons.chevron_right, size: 18, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
          if (failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DetailLine(
                Icons.cloud_off_outlined,
                'Some items may be missing: couldn’t load ${failed.join(', ')}.',
                color: DashSeverity.critical.color,
                maxLines: null,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Only items with a recorded date. Overdue items are in Priority actions.', style: dashMuted()),
          ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final ScheduleItem item;
  const _ScheduleRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => item.open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: AppColors.tearspwn, shape: BoxShape.circle),
              child: Icon(item.kind.icon, size: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14, weight: FontWeight.w700),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: dashMuted(12.5)),
                ],
              ),
            ),
            if (item.time != null && item.time!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(item.time!, style: dashBody(size: 12.5, weight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
