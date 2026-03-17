import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'cards.dart';
import 'review.dart';
import 'models.dart';

class DonationMethodSelectionScreen extends StatefulWidget {
  const DonationMethodSelectionScreen({
    super.key,
    required this.organizationName,
    required this.campaignName,
    required this.amount,
  });

  final String organizationName;
  final String campaignName;
  final double amount;

  @override
  State<DonationMethodSelectionScreen> createState() => _DonationMethodSelectionScreenState();
}

class _DonationMethodSelectionScreenState extends State<DonationMethodSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EADC),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(top: 20.0, left: 24.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  'How will you be donating?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tiltWarp(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DonationCreditCardScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    backgroundColor: const Color(0xFFFFD95E),
                    foregroundColor: Colors.black,
                    textStyle: GoogleFonts.tiltWarp(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('Credit Card'),
                ),
              ),
              const SizedBox(height: 15),
              _buildMethodButton(context, 'GCash'),
              const SizedBox(height: 15),
              _buildMethodButton(context, 'PayMaya'),
              const SizedBox(height: 15),
              _buildMethodButton(context, 'PayPal'),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodButton(BuildContext context, String methodName) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DonationReviewScreen(
                params: DonationReviewParams(
                  organizationName: widget.organizationName,
                  donationMethod: methodName,
                  item: DonationItem(
                    description: widget.campaignName,
                    amount: widget.amount,
                  ),
                ),
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          backgroundColor: const Color(0xFFFFD95E),
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.tiltWarp(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Text(methodName),
      ),
    );
  }
}
