import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'collar_tag_form_screen.dart';

class CollarIdTagIntroScreen extends StatelessWidget {
  const CollarIdTagIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Yellow arc hero
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: const BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.elliptical(200, 80),
                      bottomRight: Radius.elliptical(200, 80),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Create Pet\nCollar Tags',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tiltWarp(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Make it easier for others to help your pet find their way home!',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create a digital collar tag with:',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  _bullet('Pet details and photo'),
                  _bullet('Medical and vaccination records'),
                  _bullet('Emergency contact information'),
                  _bullet('QR code access'),
                  const SizedBox(height: 20),
                  Text(
                    'When scanned, you will be notified of the location and the '
                        'pet\'s profile becomes instantly accessible, helping rescuers '
                        'identify and contact you quickly.',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A small fee applies, with all proceeds donated to the Loved '
                        'by the Gapz organization to support animal rescue and welfare programs.',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 40),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CollarTagFormScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      child: Text(
                        'Create Now!',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(color: AppColors.textPrimary)),
        Expanded(
          child: Text(text,
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
}