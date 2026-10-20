import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import 'certificate_view.dart';
import 'donation_page.dart';
import 'donation_summary.dart';

/// Shown instead of the receipt when the donor's payment completed the
/// campaign's goal (the backend sets donationPayments/{id}.completedCampaign
/// in the same transaction that closes the campaign).
class CampaignCompletedPage extends StatelessWidget {
  final String campaignTitle;
  final String paymentId;
  final DonationSummaryParams summary;

  const CampaignCompletedPage({
    super.key,
    required this.campaignTitle,
    required this.paymentId,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(color: AppColors.yellowrspwn, shape: BoxShape.circle),
                child: const Icon(Icons.pets, size: 64, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 28),
              Text('Thank you so much\nfor your support!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tiltWarp(fontSize: 28, height: 1.15, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              Text(
                'Your donation completed the goal for "$campaignTitle". '
                    'Donations for it are now closed, and you can follow where every peso goes in its Fund Tracking '
                    'under Past Campaigns.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 17, height: 1.3, color: AppColors.textPrimary),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => CertificateScreen(certificateId: paymentId))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('View My Certificate', style: GoogleFonts.tiltWarp(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => DonationSummaryScreen(params: summary))),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('View Receipt', style: GoogleFonts.tiltWarp(fontSize: 15)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const DonationPage()),
                      (route) => false,
                ),
                child: Text('Back to Donations', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
