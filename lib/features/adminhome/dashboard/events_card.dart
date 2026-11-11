import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

/// The organization's next volunteer event and its sign-ups, plus the two
/// after it. Counts come from the event's own `goingCount`.
class EventsCard extends ConsumerWidget {
  const EventsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      icon: Icons.event,
      title: 'Volunteer events',
      onOpen: () => openEvents(context),
      child: DashAsync<List<VolunteerEvent>>(
        value: ref.watch(upcomingEventsProvider),
        what: 'events',
        builder: (events) {
          if (events.isEmpty) {
            return const DashEmpty('No upcoming events.', severity: DashSeverity.info);
          }
          final next = events.first;
          final later = events.skip(1).take(2).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NextEvent(event: next),
              if (later.isNotEmpty) ...[
                const CardLabel('Also coming up'),
                for (final e in later) _LaterEventRow(event: e),
              ],
              if (events.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${plural(events.length - 3, 'more event')} scheduled', style: dashMuted()),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "12 of 20 signed up", or "12 signed up" when no limit is set.
String signUpText(VolunteerEvent e) =>
    e.capacity == null ? '${e.goingCount} signed up · no limit' : '${e.goingCount} of ${e.capacity} signed up';

class _NextEvent extends StatelessWidget {
  final VolunteerEvent event;
  const _NextEvent({required this.event});

  @override
  Widget build(BuildContext context) {
    final cap = event.capacity;
    final left = cap == null ? null : cap - event.goingCount;
    final starts = event.startAt;
    final now = DateTime.now();
    final days = DateTime(starts.year, starts.month, starts.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final when = days <= 0 ? 'Today' : (days == 1 ? 'Tomorrow' : 'In $days days');
    return InkWell(
      onTap: () => openEvent(context, event.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              StatusChip(when, tone: days <= 1 ? ChipTone.amber : ChipTone.info, icon: Icons.schedule),
            ],
          ),
          const SizedBox(height: 5),
          DetailLine(Icons.calendar_today, '${event.date} · ${event.time}'),
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 3),
            DetailLine(Icons.place_outlined, event.location),
          ],
          const SizedBox(height: 9),
          if (cap != null && cap > 0) ...[
            DashProgress(
              fraction: event.goingCount / cap,
              color: event.isFull ? DashSeverity.ok.color : AppColors.greenrspwn,
              semanticsLabel: signUpText(event),
            ),
            const SizedBox(height: 5),
          ],
          Row(
            children: [
              Expanded(child: Text(signUpText(event), style: dashBody(size: 13.5, weight: FontWeight.w700))),
              if (left != null)
                event.isFull
                    ? const StatusChip('Full', tone: ChipTone.green, icon: Icons.check)
                    : StatusChip('${plural(left, 'spot')} left', tone: ChipTone.info),
            ],
          ),
        ],
      ),
    );
  }
}

class _LaterEventRow extends StatelessWidget {
  final VolunteerEvent event;
  const _LaterEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openEvent(context, event.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14, weight: FontWeight.w700),
                  ),
                  Text('${shortDate(event.startAt)} · ${signUpText(event)}', style: dashMuted(12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
