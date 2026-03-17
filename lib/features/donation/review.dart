import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'models.dart';

final donationReviewProvider = ChangeNotifierProvider.autoDispose.family<DonationReviewNotifier, DonationReviewParams>((ref, params) {
  return DonationReviewNotifier(
    organizationName: params.organizationName,
    donationMethod: params.donationMethod,
    item: params.item,
  );
});

class DonationReviewParams {
  final String organizationName;
  final String donationMethod;
  final DonationItem item;

  DonationReviewParams({
    required this.organizationName,
    required this.donationMethod,
    required this.item,
  });
}

class DonationReviewNotifier extends ChangeNotifier {
  final String organizationName;
  final String donationMethod;
  final DonationItem item;
  final double totalAmount;

  DonationReviewNotifier({
    required this.organizationName,
    required this.donationMethod,
    required this.item,
  }) : totalAmount = item.amount;
}

class DonationReviewSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const DonationReviewSectionCard({
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

class DonationReviewScreen extends ConsumerWidget {
  const DonationReviewScreen({super.key, required this.params});

  final DonationReviewParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donation = ref.watch(donationReviewProvider(params));

    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
          color: Colors.black,
        ),
        title: Text(
          'Donation Review',
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
              DonationReviewSectionCard(
                title: 'Organization',
                icon: Icons.volunteer_activism_outlined,
                children: <Widget>[
                  Text(
                    donation.organizationName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DonationReviewSectionCard(
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
              DonationReviewSectionCard(
                title: 'Payment Info',
                icon: Icons.payment_outlined,
                children: <Widget>[
                  Text(
                    donation.donationMethod,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Placeholder for donation processing logic
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
                  child: const Text('Pay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
