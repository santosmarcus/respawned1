import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/events/admin_events_page.dart';
import 'package:respawnd1/features/admin/events/event_form_page.dart';
import 'package:respawnd1/features/admin/events/state/event_providers.dart';

/// One event's details, Edit/Cancel actions, and its sign-up list.
class AdminEventDetailPage extends ConsumerWidget {
  final String eventId;
  const AdminEventDetailPage({super.key, required this.eventId});

  Future<void> _cancel(BuildContext context, WidgetRef ref, VolunteerEvent event) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Cancel this event?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.goingCount == 0
                  ? 'It will be hidden from volunteers.'
                  : '${event.goingCount} people have signed up. It will be hidden from volunteers and marked cancelled on their tickets.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Event')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Cancel Event'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(volunteerEventRepositoryProvider).cancelEvent(event.id, reason: reason);
    } catch (e) {
      debugPrint('[AdminEventDetailPage] cancel failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel the event.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));
    final event = eventAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.background),
        title: Text('Event', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          if (event != null && !event.isCancelled && !event.isPast)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.background),
              onSelected: (v) {
                if (v == 'edit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventFormPage(organizationId: event.organizationId, existing: event),
                    ),
                  );
                } else {
                  _cancel(context, ref, event);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit Event')),
                PopupMenuItem(value: 'cancel', child: Text('Cancel Event')),
              ],
            ),
        ],
      ),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _centered('Could not load this event.'),
        data: (event) {
          if (event == null) return _centered('This event no longer exists.');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(event.title,
                        style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                  ),
                  EventStatusChip(event: event),
                ],
              ),
              const SizedBox(height: 10),
              _info(Icons.calendar_today_outlined, event.date),
              _info(Icons.access_time_outlined, event.time),
              _info(Icons.location_on_outlined, '${event.location}\n${event.addressFull}'),
              _info(
                Icons.people_outline,
                event.capacity == null
                    ? '${event.goingCount} signed up · no limit'
                    : '${event.goingCount} of ${event.capacity} spots taken',
              ),
              const SizedBox(height: 12),
              Text(event.description,
                  style: GoogleFonts.zain(fontSize: 14, height: 1.5, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text('Sign-ups', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              _RegistrationsList(eventId: event.id),
            ],
          );
        },
      ),
    );
  }

  Widget _centered(String text) => Center(
        child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
          ],
        ),
      );
}

class _RegistrationsList extends ConsumerWidget {
  final String eventId;
  const _RegistrationsList({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAsync = ref.watch(eventRegistrationsProvider(eventId));
    return regsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Text('Could not load sign-ups.',
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
      data: (regs) {
        if (regs.isEmpty) {
          return Text('No one has signed up yet.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
        }
        return Column(
          children: [
            for (final r in regs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.participantName.isEmpty ? 'Unnamed volunteer' : r.participantName,
                              style: GoogleFonts.zain(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(r.participantEmail,
                              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                          Text(
                            [
                              r.participantNumber,
                              if (r.registeredAt != null) 'Signed up ${DateFormat.yMMMd().format(r.registeredAt!)}',
                            ].join(' · '),
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (r.participantMobileNumber.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.call_outlined, color: AppColors.textPrimary),
                        onPressed: () async {
                          final uri = Uri(scheme: 'tel', path: r.participantMobileNumber);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
