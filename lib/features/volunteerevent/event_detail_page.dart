import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'volunteer_page.dart';
import 'volunteer_signup_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'volunteer_eticket.dart';

class VolunteerEventDetailPage extends StatefulWidget {
  final VolunteerEvent event;
  final VoidCallback onFavorite;
  final MarkJoinedCallback onMarkJoined;

  const VolunteerEventDetailPage({
    super.key,
    required this.event,
    required this.onFavorite,
    required this.onMarkJoined,
  });

  @override
  State<VolunteerEventDetailPage> createState() =>
      _VolunteerEventDetailPageState();
}

class _VolunteerEventDetailPageState
    extends State<VolunteerEventDetailPage> {
  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined,
                color: AppColors.textPrimary, size: 22),
            onPressed: () {},
          ),
          StatefulBuilder(
            builder: (context, setIcon) => IconButton(
              icon: Icon(
                event.favorited ? Icons.favorite : Icons.favorite_border,
                color: event.favorited
                    ? const Color(0xFFE05C5C)
                    : AppColors.textPrimary,
                size: 22,
              ),
              onPressed: () {
                widget.onFavorite();
                setIcon(() {}); // redraw just the icon
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Image placeholder
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(16),
              ),
            ),

            const SizedBox(height: 20),

            // Title
            Text(
              event.title,
              style: GoogleFonts.tiltWarp(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),

            const SizedBox(height: 10),

            // Date + going count
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 13, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  event.date,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 85),
                Text(
                  '${event.goingCount} people are going',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.access_time_outlined,
                    size: 13, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  event.time,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // About
            Text(
              'About the Event',
              style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              event.description,
              style: GoogleFonts.zain(
                  fontSize: 14,
                  height: 1.6,
                  color: AppColors.textPrimary),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, thickness: 0.8, color: Color(0xFFDDDDDD)),
            const SizedBox(height: 20),

            // Organizer
            Text(
              'Organizer',
              style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.slaterspwn,
                  child: const Icon(Icons.person_outline,
                      color: AppColors.textSecondary, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  event.organizerName,
                  style: GoogleFonts.zain(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Address
            Text(
              'Address',
              style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    event.addressFull,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'View on Google Maps',
                    style: GoogleFonts.zain(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Map placeholder
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(12),
              ),
            ),

            const SizedBox(height: 28),

            // Joined / View E-Ticket button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: event.joined
                    ? () => _openETicket(context)
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VolunteerSignUpPage(
                        event: event,
                        onMarkJoined: widget.onMarkJoined,
                      ),
                    ),
                  ).then((_) => setState(() {}));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  event.joined ? 'View E-Ticket' : 'Join event',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }


  Future<void> _openETicket(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('volunteerRegistrations')
        .doc(widget.event.id.toString())
        .get();

    if (!mounted) return;

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration details not found.')),
      );
      return;
    }

    final data = doc.data()!;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VolunteerETicketPage(
          event: widget.event,
          participantName: data['participantName'] ?? '',
          participantEmail: data['participantEmail'] ?? '',
          participantMobileNumber: data['participantMobileNumber'] ?? '',
          participantNumber: data['participantNumber'] ?? '',
        ),
      ),
    );
  }
}