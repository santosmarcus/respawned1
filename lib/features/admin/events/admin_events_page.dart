import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/events/admin_event_detail_page.dart';
import 'package:respawnd1/features/admin/events/event_form_page.dart';
import 'package:respawnd1/features/admin/events/state/event_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

enum _EventFilter {
  upcoming('Upcoming'),
  past('Past'),
  cancelled('Cancelled');

  const _EventFilter(this.label);
  final String label;

  bool matches(VolunteerEvent e) => switch (this) {
        _EventFilter.upcoming => !e.isCancelled && !e.isPast,
        _EventFilter.past => !e.isCancelled && e.isPast,
        _EventFilter.cancelled => e.isCancelled,
      };
}

/// The organization's own volunteer events: create, open, edit, cancel.
class AdminEventsPage extends ConsumerStatefulWidget {
  const AdminEventsPage({super.key});

  @override
  ConsumerState<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends ConsumerState<AdminEventsPage> {
  _EventFilter _filter = _EventFilter.upcoming;

  void _openForm(String organizationId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventFormPage(organizationId: organizationId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgIdAsync = ref.watch(currentOrganizationIdProvider);
    final organizationId = orgIdAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.events),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('Events', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      floatingActionButton: organizationId == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              onPressed: () => _openForm(organizationId),
              icon: const Icon(Icons.add),
              label: Text('New Event', style: GoogleFonts.tiltWarp(fontSize: 14)),
            ),
      body: orgIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _message('Could not load your organization.'),
        data: (orgId) {
          if (orgId == null) return _message('Link your account to an organization to manage events.');
          final eventsAsync = ref.watch(organizationEventsProvider(orgId));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in _EventFilter.values)
                      ChoiceChip(
                        label: Text(f.label, style: GoogleFonts.zain(fontSize: 13)),
                        selected: _filter == f,
                        selectedColor: AppColors.yellowrspwn,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: eventsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _message('Could not load events.'),
                  data: (events) {
                    var list = events.where(_filter.matches).toList();
                    // Most recent first for history; soonest first for upcoming.
                    if (_filter != _EventFilter.upcoming) list = list.reversed.toList();
                    if (list.isEmpty) {
                      return _message(_filter == _EventFilter.upcoming
                          ? 'No upcoming events. Tap New Event to create one.'
                          : 'No ${_filter.label.toLowerCase()} events.');
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _AdminEventCard(
                        event: list[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AdminEventDetailPage(eventId: list[i].id)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
}

class _AdminEventCard extends StatelessWidget {
  final VolunteerEvent event;
  final VoidCallback onTap;
  const _AdminEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final going = event.capacity == null ? '${event.goingCount} going' : '${event.goingCount}/${event.capacity} going';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('${event.date} · ${event.time}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  Text(event.location, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                EventStatusChip(event: event),
                const SizedBox(height: 6),
                Text(going, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventStatusChip extends StatelessWidget {
  final VolunteerEvent event;
  const EventStatusChip({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final (label, color) = event.isCancelled
        ? ('Cancelled', Colors.redAccent)
        : event.isPast
            ? ('Ended', AppColors.textSecondary)
            : event.isFull
                ? ('Full', AppColors.lavenderrspwn)
                : ('Open', AppColors.greenrspwn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}
