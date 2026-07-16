import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../userauth/history_provider.dart';
import 'cancel_dialog.dart';
import 'models.dart';

final donationSummaryProvider = ChangeNotifierProvider.autoDispose.family<DonationSummaryNotifier, DonationSummaryParams>((ref, params) {
  return DonationSummaryNotifier(
    charityName: params.charityName,
    donationMethod: params.donationMethod,
    item: params.item,
    referenceNumber: params.referenceNumber,
    timestamp: params.timestamp,
    historyItem: params.historyItem,
  );
});

class DonationSummaryParams {
  final String charityName;
  final String donationMethod;
  final DonationItem item;
  final String referenceNumber;
  final DateTime timestamp;
  final HistoryItem? historyItem;

  DonationSummaryParams({
    required this.charityName,
    required this.donationMethod,
    required this.item,
    required this.referenceNumber,
    required this.timestamp,
    this.historyItem,
  });
}

class DonationSummaryNotifier extends ChangeNotifier {
  final String charityName;
  final String donationMethod;
  final DonationItem item;
  final String referenceNumber;
  final DateTime timestamp;
  final HistoryItem? historyItem;
  final double totalAmount;

  DonationSummaryNotifier({
    required this.charityName,
    required this.donationMethod,
    required this.item,
    required this.referenceNumber,
    required this.timestamp,
    this.historyItem,
  }) : totalAmount = item.amount;
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
        side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.1)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
      ),
    );
  }
}

class DonationSummaryScreen extends ConsumerWidget {
  const DonationSummaryScreen({super.key, required this.params});

  final DonationSummaryParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donation = ref.watch(donationSummaryProvider(params));
    // Watch history to react to cancellation
    final history = ref.watch(historyProvider);
    final currentHistoryItem = donation.historyItem != null 
        ? history.firstWhere((item) => item.id == donation.historyItem!.id, orElse: () => donation.historyItem!)
        : null;

    final isSponsorship = currentHistoryItem?.type == HistoryType.sponsorship;
    final isCancelled = currentHistoryItem?.isCancelled ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () {
            Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
          },
        ),
        title: Text(
          isSponsorship ? 'Sponsorship Summary' : 'Donation Summary',
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
                    const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 80),
                    const SizedBox(height: 12),
                    Text(
                      'Thank You!',
                      style: GoogleFonts.tiltWarp(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      isSponsorship ? 'Your sponsorship is now active.' : 'Your donation was successful.',
                      style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
              if (isSponsorship && currentHistoryItem?.pet != null) ...[
                DonationSummarySectionCard(
                  title: 'Sponsored Pet',
                  icon: Icons.pets_outlined,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.tearspwn.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.pets, color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentHistoryItem!.pet!.name,
                              style: GoogleFonts.zain(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Recurring monthly support',
                              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],

              DonationSummarySectionCard(
                title: 'Organization',
                icon: Icons.volunteer_activism_outlined,
                children: <Widget>[
                  Text(
                    donation.charityName,
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: isSponsorship ? 'Sponsorship Details' : 'Donation Details',
                icon: Icons.attach_money_outlined,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            donation.item.description,
                            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '₱${donation.item.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  if (isSponsorship && currentHistoryItem?.nextChargeDate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isCancelled ? 'Status:' : 'Next Charge Date:',
                          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                        ),
                        Text(
                          isCancelled 
                              ? 'Cancelled (Ends ${DateFormat('MMMM dd, yyyy').format(currentHistoryItem!.nextChargeDate!)})'
                              : DateFormat('MMMM dd, yyyy').format(currentHistoryItem!.nextChargeDate!),
                          style: GoogleFonts.zain(
                            fontSize: 15, 
                            fontWeight: FontWeight.bold, 
                            color: isCancelled ? Colors.red : AppColors.greenrspwn
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 24, thickness: 0.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Total:',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '₱${donation.totalAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: 'Payment Info',
                icon: Icons.payment_outlined,
                children: <Widget>[
                  Text(
                    donation.donationMethod,
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                        ),
                        Text(
                          donation.referenceNumber,
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                        ),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(donation.timestamp),
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              if (isSponsorship && !isCancelled) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      _showCancelDialog(context, ref, currentHistoryItem!);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: Text(
                      'Cancel Sponsorship',
                      style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 25),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Placeholder for navigating to history
                        debugPrint('View History pressed');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                      ),
                      child: Text(
                        'History',
                        style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                      ),
                      child: Text(
                        'Home',
                        style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref, HistoryItem item) {
    final expiryDate = item.nextChargeDate != null 
        ? DateFormat('MMMM dd, yyyy').format(item.nextChargeDate!)
        : 'the end of your current period';
    showCancelDialog(
      context: context,
      title: 'Are You Sure?',
      message: 'You are about to cancel your sponsorship. It will remain active until $expiryDate.',
      onConfirm: () {
        ref.read(historyProvider.notifier).cancelSponsorship(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sponsorship cancelled successfully.')),
        );
      },
    );
  }
}
