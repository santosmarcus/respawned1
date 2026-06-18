import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'models.dart';

final donationSummaryProvider = ChangeNotifierProvider.autoDispose.family<DonationSummaryNotifier, DonationSummaryParams>((ref, params) {
  return DonationSummaryNotifier(
    charityName: params.charityName,
    donationMethod: params.donationMethod,
    item: params.item,
    referenceNumber: params.referenceNumber,
    timestamp: params.timestamp,
  );
});

class DonationSummaryParams {
  final String charityName;
  final String donationMethod;
  final DonationItem item;
  final String referenceNumber;
  final DateTime timestamp;

  DonationSummaryParams({
    required this.charityName,
    required this.donationMethod,
    required this.item,
    required this.referenceNumber,
    required this.timestamp,
  });
}

class DonationSummaryNotifier extends ChangeNotifier {
  final String charityName;
  final String donationMethod;
  final DonationItem item;
  final String referenceNumber;
  final DateTime timestamp;
  final double totalAmount;

  DonationSummaryNotifier({
    required this.charityName,
    required this.donationMethod,
    required this.item,
    required this.referenceNumber,
    required this.timestamp,
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
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: Colors.grey[700], size: 24),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.tiltWarp(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const Divider(height: 20, thickness: 1, indent: 0, endIndent: 0),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
          },
        ),
        title: Text(
          'Donation Summary',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
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
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 80),
                    SizedBox(height: 10),
                    Text(
                      'Thank You!',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text('Your donation was successful.'),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              DonationSummarySectionCard(
                title: 'Organization',
                icon: Icons.volunteer_activism_outlined,
                children: <Widget>[
                  Text(
                    donation.charityName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationSummarySectionCard(
                title: 'Donation Details',
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
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '₱${donation.item.amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 18, thickness: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Total:',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '₱${donation.totalAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                        const Text(
                          'Reference:',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          donation.referenceNumber,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          'Date & Time:',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(donation.timestamp),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                        // Placeholder for navigating to history
                        debugPrint('View History pressed');
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
                        // Placeholder for navigating back to donation list
                        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
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
            ],
          ),
        ),
      ),
    );
  }
}
