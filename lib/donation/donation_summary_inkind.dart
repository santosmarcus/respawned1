import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../userauth/history_screen.dart';
import 'cancel_dialog.dart';
import 'donation_page.dart';
import 'models.dart';

class InKindDonationSummaryParams {
  final String charityName;
  final String category;
  final String clarification;
  final bool isAnonymous;
  final String referenceNumber;
  final DateTime timestamp;
  final String address;
  final InKindStatus? status;

  InKindDonationSummaryParams({
    required this.charityName,
    required this.category,
    required this.clarification,
    required this.isAnonymous,
    required this.referenceNumber,
    required this.timestamp,
    required this.address,
    this.status,
  });
}

class DonationSummarySectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const DonationSummarySectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: AppColors.textPrimary.withOpacity(0.1)),
      ),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: AppColors.textPrimary, size: 24),
                const SizedBox(width: 10),
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
            const Divider(height: 20, thickness: 0.5),
            ...children,
          ],
        ),
      ),
    );
  }
}

class InKindDonationSummaryScreen extends StatelessWidget {
  const InKindDonationSummaryScreen({
    super.key,
    required this.params,
    this.onCancel,
  });

  final InKindDonationSummaryParams params;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final bool isInProgress = params.status == InKindStatus.inProgress;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Donation Summary',
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
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Column(
                  children: [
                    Icon(
                      params.status == InKindStatus.cancelled
                          ? Icons.cancel
                          : Icons.check_circle,
                      color: params.status == InKindStatus.cancelled
                          ? Colors.red
                          : Colors.green,
                      size: 80,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      params.status == InKindStatus.cancelled
                          ? 'Donation Cancelled'
                          : 'Thank You!',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      params.status == InKindStatus.cancelled
                          ? 'This donation request has been cancelled.'
                          : 'Your donation request was received!',
                      style: GoogleFonts.zain(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              DonationSummarySectionCard(
                title: 'Organization',
                icon: Icons.volunteer_activism_outlined,
                children: <Widget>[
                  Text(
                    params.charityName,
                    style: GoogleFonts.zain(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: 'Drop-off Address',
                icon: Icons.location_on_outlined,
                children: <Widget>[
                  Text(
                    params.address,
                    style: GoogleFonts.zain(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary),
                  ),
                  if (isInProgress) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Please drop off your items at this location.',
                      style: GoogleFonts.zain(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: 'Donation Details',
                icon: Icons.inventory_2_outlined,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Category:',
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          params.category,
                          style: GoogleFonts.zain(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Items / Clarification:',
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          params.clarification,
                          style: GoogleFonts.zain(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: 'Confirmation Details',
                icon: Icons.receipt_long_outlined,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Reference:',
                          style: GoogleFonts.zain(fontSize: 14),
                        ),
                        Text(
                          params.referenceNumber,
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Date & Time:',
                          style: GoogleFonts.zain(fontSize: 14),
                        ),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm')
                              .format(params.timestamp),
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const HistoryScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        backgroundColor: const Color(0xFFFFD95E),
                        foregroundColor: Colors.black,
                        textStyle: GoogleFonts.tiltWarp(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('History'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const DonationPage()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        backgroundColor: const Color(0xFFFFD95E),
                        foregroundColor: Colors.black,
                        textStyle: GoogleFonts.tiltWarp(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Donations'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (isInProgress && onCancel != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      showCancelDialog(
                        context: context,
                        title: 'Are You Sure?',
                        message: 'You are about to cancel your donation. This cannot be undone.',
                        onConfirm: () {
                          onCancel!();
                          Navigator.of(context).pop();
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: Text(
                      'Cancel Donation',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
