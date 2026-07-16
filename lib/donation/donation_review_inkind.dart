import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../userauth/history_provider.dart';
import 'models.dart';
import 'donation_summary_inkind.dart';

class DonationReviewInKindScreen extends ConsumerWidget {
  final InKindDonationReviewParams params;

  const DonationReviewInKindScreen({super.key, required this.params});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Review Donation',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionCard(
                title: 'Organization',
                icon: Icons.volunteer_activism_outlined,
                children: <Widget>[
                  Text(
                    params.organizationName,
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Shipping Address',
                icon: Icons.location_on_outlined,
                children: <Widget>[
                  Text(
                    params.address,
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Donation Details',
                icon: Icons.inventory_2_outlined,
                children: <Widget>[
                  Text(
                    'Category',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  Text(
                    params.category,
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Clarification / Items',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  Text(
                    params.clarification,
                    style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                  ),
                  const Divider(height: 24, thickness: 0.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Anonymous Donation',
                        style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                      ),
                      Text(
                        params.isAnonymous ? 'Yes' : 'No',
                        style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final refNumber = 'REF-IK-${DateTime.now().millisecondsSinceEpoch}';
                    final now = DateTime.now();

                    // Record in history
                    ref.read(historyProvider.notifier).addHistoryItem(
                      HistoryItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        type: HistoryType.inKindDonation,
                        organizer: params.organizationName,
                        dateTime: now,
                        refNumber: refNumber,
                        status: InKindStatus.inProgress,
                        category: params.category,
                        clarification: params.clarification,
                        isAnonymous: params.isAnonymous,
                        address: params.address,
                      ),
                    );

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InKindDonationSummaryScreen(
                          params: InKindDonationSummaryParams(
                            charityName: params.organizationName,
                            category: params.category,
                            clarification: params.clarification,
                            isAnonymous: params.isAnonymous,
                            referenceNumber: refNumber,
                            timestamp: now,
                            address: params.address,
                          ),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  ),
                  child: Text(
                    'Confirm Donation',
                    style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          ...children,
        ],
      ),
    );
  }
}
