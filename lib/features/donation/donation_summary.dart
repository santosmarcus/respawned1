import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../generalhome/history_provider.dart';
import '../generalhome/history_screen.dart';
import 'cancel_dialog.dart';
import 'donation_page.dart';
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
    // Watch history to react to cancellation/un-cancellation
    final history = ref.watch(historyProvider);
    
    // Find the latest state of this history item if available
    final currentHistoryItem = donation.historyItem != null 
        ? history.firstWhere((item) => item.id == donation.historyItem!.id, orElse: () => donation.historyItem!)
        : null;

    final isSponsorship = currentHistoryItem?.type == HistoryType.sponsorship;
    final isInactive = currentHistoryItem?.sponsorshipStatus == 'inactive';
    final bool isBeforeExpiry = currentHistoryItem?.nextChargeDate != null && 
                                DateTime.now().isBefore(currentHistoryItem!.nextChargeDate!);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
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
                      Icon(
                        isInactive ? Icons.cancel_outlined : Icons.check_circle,
                        color: isInactive ? Colors.red : AppColors.greenrspwn,
                        size: 80,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isInactive ? 'Sponsorship Cancelled' : 'Thank You!',
                        style: GoogleFonts.tiltWarp(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        isSponsorship 
                          ? (isInactive ? 'This sponsorship will end soon.' : 'Your sponsorship is now active.')
                          : 'Your donation was successful.',
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
                            isInactive ? 'Ends On:' : 'Next Charge Date:',
                            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                          ),
                          Text(
                            DateFormat('MMMM dd, yyyy').format(currentHistoryItem!.nextChargeDate!),
                            style: GoogleFonts.zain(
                              fontSize: 15, 
                              fontWeight: FontWeight.bold, 
                              color: isInactive ? Colors.red : AppColors.greenrspwn
                            ),
                          ),
                        ],
                      ),
                      if (!isInactive) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Next Charge Amount:',
                              style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                            ),
                            Text(
                              '₱${(currentHistoryItem.nextChargeAmount ?? donation.item.amount).toStringAsFixed(2)}',
                              style: GoogleFonts.zain(
                                fontSize: 15, 
                                fontWeight: FontWeight.bold, 
                                color: AppColors.greenrspwn
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _showChangeAmountDialog(context, ref, currentHistoryItem),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              'Change Next Amount',
                              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.greenrspwn,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ],
                    const Divider(height: 24, thickness: 0.5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Total Paid:',
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
                            style: GoogleFonts.zain(fontSize: 14),
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
                            style: GoogleFonts.zain(fontSize: 14),
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
                
                if (isSponsorship && (!isInactive || isBeforeExpiry)) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (isInactive) {
                          _showUncancelDialog(context, ref, currentHistoryItem!.id);
                        } else {
                          _showCancelDialog(context, ref, currentHistoryItem!);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isInactive ? AppColors.greenrspwn : Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isInactive ? 'Reactivate Sponsorship' : 'Cancel Sponsorship',
                        style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
  
                if (currentHistoryItem?.type == HistoryType.inKindDonation && 
                    currentHistoryItem?.status == InKindStatus.inProgress) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showCancelInKindDialog(context, ref, currentHistoryItem!.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Cancel Donation',
                        style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const HistoryPage()),
                          );
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
      ),
    );

  }

  void _showCancelInKindDialog(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Donation', style: GoogleFonts.tiltWarp()),
        content: Text(
          'Are you sure you want to cancel this in-kind donation?',
          style: GoogleFonts.zain(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No, Keep It'),
          ),
          TextButton(
            onPressed: () {
              ref.read(historyProvider.notifier).updateStatus(id, InKindStatus.cancelled);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Donation cancelled.')),
              );
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref, HistoryItem item) {
    final expiryDate = DateFormat('MMMM dd, yyyy').format(item.nextChargeDate!);
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

  void _showUncancelDialog(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reactivate Sponsorship', style: GoogleFonts.tiltWarp()),
        content: Text(
          'Do you want to reactivate this sponsorship? You will be charged again at the end of your current period.',
          style: GoogleFonts.zain(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          TextButton(
            onPressed: () {
              ref.read(historyProvider.notifier).unCancelSponsorship(id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sponsorship reactivated successfully!')),
              );
            },
            child: const Text('Yes, Reactivate', style: TextStyle(color: AppColors.greenrspwn)),
          ),
        ],
      ),
    );
  }

  void _showChangeAmountDialog(BuildContext context, WidgetRef ref, HistoryItem item) {
    final controller = TextEditingController(text: (item.nextChargeAmount ?? item.amount ?? 0.0).toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Update Next Payment', style: GoogleFonts.tiltWarp()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the new amount for your next charge on ${DateFormat('MMM dd, yyyy').format(item.nextChargeDate!)}.',
              style: GoogleFonts.zain(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: 'New Amount',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.greenrspwn, width: 2),
                ),
              ),
              style: GoogleFonts.tiltWarp(fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                ref.read(historyProvider.notifier).updateSponsorshipAmount(item.id, amount);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Next payment amount updated to ₱${amount.toInt()}.')),
                );
              }
            },
            child: const Text('Update Amount', style: TextStyle(color: AppColors.greenrspwn, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
