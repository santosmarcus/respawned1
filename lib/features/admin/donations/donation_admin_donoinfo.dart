import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:respawnd1/app_theme.dart';
import 'donation_admin_models.dart';
import 'donation_admin_provider.dart';
import 'package:intl/intl.dart';

class DonationDetailsScreen extends StatefulWidget {
  final DonationHistoryRecord donation;

  const DonationDetailsScreen({super.key, required this.donation});

  @override
  State<DonationDetailsScreen> createState() => _DonationDetailsScreenState();
}

class _DonationDetailsScreenState extends State<DonationDetailsScreen> {
  bool _isProcessing = false;

  Future<void> _markAsComplete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm Completion", style: GoogleFonts.tiltWarp()),
        content: Text("Are you sure you want to mark this in-kind donation as complete?", style: GoogleFonts.zain()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Complete", style: GoogleFonts.zain(color: AppColors.greenrspwn, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await context.read<DonationAdminProvider>().markDonationAsComplete(
          widget.donation.id,
          widget.donation.userId,
          widget.donation.organizer,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Donation marked as complete.")),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e")),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _sendFollowUp() async {
    setState(() => _isProcessing = true);
    try {
      await context.read<DonationAdminProvider>().sendInKindFollowUpNotification(
        widget.donation.id,
        widget.donation.userId,
        context.read<DonationAdminProvider>().getCampaignTitle(widget.donation.campaignId),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Follow-up notification sent to donor.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isInKind = widget.donation.type == 'inkind';
    final bool isSponsorship = widget.donation.type == 'sponsorship';
    final DateFormat formatter = DateFormat('MM/dd/yyyy HH:mm:ss');
    final DateFormat dateOnlyFormatter = DateFormat('MM/dd/yyyy');
    
    final String formattedDate = widget.donation.timestamp != null 
        ? formatter.format(widget.donation.timestamp!.toDate()) 
        : widget.donation.date;

    final String formattedDateOnly = widget.donation.timestamp != null
        ? dateOnlyFormatter.format(widget.donation.timestamp!.toDate())
        : widget.donation.date;

    // Calculate next payment for sponsorship (approx 1 month later)
    String nextPayment = "N/A";
    if (isSponsorship && widget.donation.timestamp != null) {
      final dt = widget.donation.timestamp!.toDate();
      nextPayment = dateOnlyFormatter.format(DateTime(dt.year, dt.month + 1, dt.day));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            color: AppColors.textPrimary,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: AppColors.background, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  isSponsorship ? "Sponsorship Info" : "Donation Info",
                  style: GoogleFonts.tiltWarp(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.background,
                  ),
                ),
                const Icon(Icons.lightbulb_outline, color: AppColors.background),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSponsorship) ...[
                    _buildRow("Pet", context.read<DonationAdminProvider>().getAnimalName(widget.donation.campaignId)),
                    _buildRow("User", widget.donation.title),
                    _buildRow("Time", formattedDateOnly),
                    _buildRow("Total Paid", widget.donation.amount),
                    _buildRow("Last Paid", formattedDateOnly),
                    _buildRow("Next Payment", nextPayment),
                    _buildRow("Status", widget.donation.status.isNotEmpty ? (widget.donation.status[0].toUpperCase() + widget.donation.status.substring(1)) : "Active"),
                    _buildRow("Reference", widget.donation.refNumber),
                  ] else if (isInKind) ...[
                    _buildDescriptionBlock("Campaign", context.read<DonationAdminProvider>().getCampaignTitle(widget.donation.campaignId)),
                    const SizedBox(height: 12),
                    _buildRow("Type", "In-Kind"),
                    _buildRow("User", widget.donation.title),
                    _buildRow("Time", formattedDate),
                    _buildRow("Status", widget.donation.status.isNotEmpty ? (widget.donation.status[0].toUpperCase() + widget.donation.status.substring(1)) : "Pending"),
                    _buildRow("Item Category", widget.donation.category.isEmpty ? widget.donation.amountString.replaceFirst("In-kind: ", "") : widget.donation.category),
                    const SizedBox(height: 12),
                    _buildDescriptionBlock(
                      "Description", 
                      widget.donation.clarification.isEmpty ? (widget.donation.itemDescription.isEmpty ? "No description provided." : widget.donation.itemDescription) : widget.donation.clarification
                    ),
                    const SizedBox(height: 12),
                    _buildRow("Reference", widget.donation.refNumber),
                  ] else ...[
                    _buildDescriptionBlock("Campaign", context.read<DonationAdminProvider>().getCampaignTitle(widget.donation.campaignId)),
                    const SizedBox(height: 12),
                    _buildRow("Type", "Monetary"),
                    _buildRow("User", widget.donation.title),
                    _buildRow("Time", formattedDate),
                    _buildRow("Amount", widget.donation.amount),
                    _buildRow("Reference", widget.donation.refNumber),
                  ],
                ],
              ),
            ),
          ),
          if (isInKind && widget.donation.status != 'complete')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
              child: Column(
                children: [
                  OutlinedButton(
                    onPressed: _isProcessing ? null : _sendFollowUp,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.textPrimary, width: 2),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: AppColors.textPrimary)
                        : Text(
                            "Follow-up",
                            style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _markAsComplete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      minimumSize: const Size(double.infinity, 56),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: AppColors.textPrimary)
                        : Text(
                            "Mark as Complete",
                            style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDescriptionBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.tiltWarp(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.tiltWarp(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value, 
              textAlign: TextAlign.right,
              style: GoogleFonts.zain(
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
