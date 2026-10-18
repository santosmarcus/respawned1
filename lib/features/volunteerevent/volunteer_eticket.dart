import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'volunteer_page.dart';

class VolunteerETicketPage extends StatelessWidget {
  final VolunteerEvent event;
  final String participantName;
  final String participantEmail;
  final String participantMobileNumber;
  final String participantNumber;

  const VolunteerETicketPage({
    super.key,
    required this.event,
    required this.participantName,
    required this.participantEmail,
    required this.participantMobileNumber,
    required this.participantNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close,
              color: AppColors.textPrimary, size: 24),
          onPressed: () =>
              Navigator.popUntil(context, (r) => r.isFirst),
        ),
        centerTitle: true,
        title: Text('Event E-Ticket',
            style: GoogleFonts.tiltWarp(
                fontSize: 20, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Participant number header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text('Participant Number',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 15,
                            color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      participantNumber,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),

            const _TicketDivider(),

            _TicketRow(label: 'Event Name', value: event.title),
            const _TicketDivider(),

            _TicketRow(
              label: 'Event Date and Time',
              value: '${event.date}\n${event.time}',
            ),
            const _TicketDivider(),

            _TicketRow(label: 'Event Address', value: event.addressFull),

            const SizedBox(height: 16),

            // Map placeholder
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(14),
              ),
            ),

            const SizedBox(height: 20),

            _TicketRow(label: 'Event Organizer', value: event.organizerName),
            const _TicketDivider(),

            _TicketRow(label: 'Participant Name', value: participantName),
            const _TicketDivider(),

            _TicketRow(label: 'Participant Email', value: participantEmail),
            const _TicketDivider(),

            _TicketRow(
                label: 'Participant Mobile Number',
                value: participantMobileNumber),
            const _TicketDivider(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _TicketRow extends StatelessWidget {
  final String label;
  final String value;
  const _TicketRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.tiltWarp(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.right,
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _TicketDivider extends StatelessWidget {
  const _TicketDivider();
  @override
  Widget build(BuildContext context) => const Divider(
      height: 1, thickness: 0.5, color: Color(0xFFDDDDDD));
}