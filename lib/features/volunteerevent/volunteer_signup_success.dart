import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'volunteer_page.dart';
import 'volunteer_eticket.dart';

class VolunteerSignUpSuccessPage extends StatelessWidget {
  final VolunteerEvent event;
  final String participantName;
  final String participantEmail;
  final String participantMobileNumber;
  final String participantNumber;

  const VolunteerSignUpSuccessPage({
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
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text('Registration Successful',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.textPrimary)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.greenrspwn),
            const SizedBox(height: 20),
            Text(
              'You\'re registered!',
              style: GoogleFonts.tiltWarp(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve successfully signed up for ${event.title}.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 15, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VolunteerETicketPage(
                        event: event,
                        participantName: participantName,
                        participantEmail: participantEmail,
                        participantMobileNumber: participantMobileNumber,
                        participantNumber: participantNumber,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('View E-Ticket',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  Navigator.popUntil(context, (r) => r.isFirst),
              child: Text('Back to Home',
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}