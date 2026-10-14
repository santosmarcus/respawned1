import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import 'models.dart';
import 'donation_summary_inkind.dart';

class DonationReviewInKindScreen extends ConsumerStatefulWidget {
  final InKindDonationReviewParams params;

  const DonationReviewInKindScreen({super.key, required this.params});

  @override
  ConsumerState<DonationReviewInKindScreen> createState() => _DonationReviewInKindScreenState();
}

class _DonationReviewInKindScreenState extends ConsumerState<DonationReviewInKindScreen> {
  bool _isProcessing = false;

  Future<void> _submit() async {
    setState(() => _isProcessing = true);
    
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not authenticated");

      // Fetch user name for admin record
      String donorName = "Anonymous";
      if (!widget.params.isAnonymous) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          if (userDoc.exists) {
            final userData = userDoc.data();
            final firstName = userData?['firstName'] ?? '';
            final lastName = userData?['lastName'] ?? '';
            final fullName = '$firstName $lastName'.trim();
            donorName = fullName.isNotEmpty ? fullName : (userData?['name'] ?? "User");
          }
        } catch (_) {
          donorName = "User";
        }
      }

      final refNumber = 'REF-IK-${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now();
      final formattedDate = DateFormat('MMMM d, yyyy').format(now);

      final donationData = {
        'userId': uid,
        'donorName': widget.params.isAnonymous ? 'Anonymous' : donorName,
        'campaignId': widget.params.fundraiserId, // Using campaignId for consistency with monetary donations
        'organizationName': widget.params.organizationName,
        'organizer': widget.params.organizationName, // Added for compatibility
        'category': widget.params.category,
        'clarification': widget.params.clarification,
        'itemDescription': '${widget.params.category}: ${widget.params.clarification}', // Added for compatibility
        'isAnonymous': widget.params.isAnonymous,
        'address': widget.params.address,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'date': formattedDate,
        'refNumber': refNumber,
        'status': 'inprogress',
        'type': 'inkind',
        'amount': 0, // In-kind has no monetary value initially
        'amountString': 'In-kind: ${widget.params.category}',
      };

      // Record in global collection (donations)
      final docRef = await FirebaseFirestore.instance.collection('donations').add(donationData);

      // Record in user history
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(docRef.id)
          .set(donationData);

      // Update campaign donor count and user donated status
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final campaignRef = FirebaseFirestore.instance.collection('campaigns').doc(widget.params.fundraiserId);
        final campaignSnap = await transaction.get(campaignRef);

        if (campaignSnap.exists) {
          transaction.update(campaignRef, {
            'numdonors': FieldValue.increment(1),
          });
        }

        // Compatibility for legacy 'donated' check
        final donatedRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('donated').doc(widget.params.fundraiserId);
        transaction.set(donatedRef, {
          'donationId': widget.params.fundraiserId,
          'donatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => InKindDonationSummaryScreen(
              params: InKindDonationSummaryParams(
                charityName: widget.params.organizationName,
                category: widget.params.category,
                clarification: widget.params.clarification,
                isAnonymous: widget.params.isAnonymous,
                referenceNumber: refNumber,
                timestamp: now,
                address: widget.params.address,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => _isProcessing ? null : Navigator.of(context).pop(),
        ),
        title: Text(
          'Review Donation',
          style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SectionCard(
                    title: 'Organization',
                    icon: Icons.volunteer_activism_outlined,
                    children: <Widget>[
                      Text(widget.params.organizationName, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Shipping Address',
                    icon: Icons.location_on_outlined,
                    children: <Widget>[
                      Text(widget.params.address, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Donation Details',
                    icon: Icons.inventory_2_outlined,
                    children: <Widget>[
                      Text('Category', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                      Text(widget.params.category, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Text('Clarification / Items', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                      Text(widget.params.clarification, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                      const Divider(height: 24, thickness: 0.5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Anonymous Donation', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                          Text(widget.params.isAnonymous ? 'Yes' : 'No', style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
                        backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, elevation: 0,
                      ),
                      child: _isProcessing 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : Text('Confirm Donation', style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[Icon(icon, color: AppColors.textPrimary, size: 20), const SizedBox(width: 8), Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]),
          const Divider(height: 24, thickness: 0.5),
          ...children,
        ],
      ),
    );
  }
}
