import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'donation_page.dart';
import 'package:intl/intl.dart';

//Donation Detail Page
class DonationDetail extends StatefulWidget {
  final DonationListing donation;
  final VoidCallback onFavorite;
  final Future<void> Function({
  required DonationListing donation,
  required double amount,
  required String paymentMethod,
  required bool isAnonymous,
  }) onDonate;

  const DonationDetail({
    super.key,
    required this.donation,
    required this.onFavorite,
    required this.onDonate,
  });

  @override
  State<DonationDetail> createState() => _DonationDetailPageState();
}

class _DonationDetailPageState extends State<DonationDetail> {
  bool _showFundTracking = false;

  // Sample fund tracking entries
  final List<Map<String, dynamic>> _fundEntries = [
    {'label': 'Shelter Water Bill', 'category': 'Bills and Utilities', 'amount': 350, 'date': 'March 20, 2026'},
    {'label': 'Shelter Electricity Bill', 'category': 'Bills and Utilities', 'amount': 350, 'date': 'March 20, 2026'},
    {'label': 'Dog Rice Sacks', 'category': 'Food', 'amount': 350, 'date': 'March 20, 2026'},
    {'label': 'Caretaker Salaries', 'category': 'Admin Tasks', 'amount': 350, 'date': 'March 10, 2026'},
    {'label': 'Confinement', 'category': 'Medicine and Treatment', 'amount': 350, 'date': 'March 10, 2026'},
    {'label': 'Wound Cleaning', 'category': 'Medicine and Treatment', 'amount': 350, 'date': 'March 10, 2026'},
  ];

  @override
  Widget build(BuildContext context) {
    final donation = widget.donation;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              donation.favorited ? Icons.favorite : Icons.favorite_border,
              color: donation.favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary,
            ),
            onPressed: () {
              widget.onFavorite();
              setState(() {});
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              donation.title,
              style: GoogleFonts.tiltWarp(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Date & time row
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(donation.date,
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(width: 16),
                Text('${donation.numdonated} people have donated',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time_outlined, size: 14, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(donation.time,
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
              ],
            ),

            const SizedBox(height: 16),

            // About section
            Text('About the Donation',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(donation.description,
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),

            const SizedBox(height: 20),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatBox(label: 'Funds received', value: '${donation.percentage}%'),
                _StatBox(label: 'Target funds', value: '₱${_fmt(donation.target)}'),
                _StatBox(label: 'Days left', value: '${donation.dateleft}'), //need to change
              ],
            ),

            const SizedBox(height: 20),

            // Organizer
            Text('Organizer',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.tearspwn,
                  child: const Icon(Icons.person, color: AppColors.textPrimary, size: 20),
                ),
                const SizedBox(width: 10),
                Text(donation.organizer,
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),

            const SizedBox(height: 16),

            // Fund Tracking toggle
            GestureDetector(
              onTap: () => setState(() => _showFundTracking = !_showFundTracking),
              child: Row(
                children: [
                  Text('Fund Tracking',
                      style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(width: 6),
                  Icon(
                    _showFundTracking ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),

            if (_showFundTracking) ...[
              const SizedBox(height: 8),
              _FundTrackingPanel(entries: _fundEntries, totalCollected: donation.collected),
            ],

            const SizedBox(height: 24),

            // Donate button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: donation.donated
                    ? null
                    : () => _openReviewSheet(context, donation),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: Text(
                  donation.donated ? 'Donated ✓' : 'Donate',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _fmt(num value) {
    return NumberFormat('#,##0').format(value);
  }

  void _openReviewSheet(BuildContext context, DonationListing donation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DonationReviewSheet(
        donation: donation,
        onDonate: widget.onDonate,
      ),
    ).then((_) => setState(() {}));
  }
}

// ─── Stat Box ───────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.tiltWarp(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary)),
      ],
    );
  }
}

// ─── Fund Tracking Panel ────────────────────────────────────────────────────

class _FundTrackingPanel extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final int totalCollected;

  const _FundTrackingPanel({required this.entries, required this.totalCollected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fund Tracking',
                  style: GoogleFonts.tiltWarp(fontSize: 13, color: AppColors.textPrimary)),
              Text('As of March 12, 2026',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 10),
          ...entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e['label'],
                          style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text(e['category'],
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${e['amount']}',
                        style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(e['date'],
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary.withValues(alpha: 0.6))),
                  ],
                ),
              ],
            ),
          )),
          const Divider(color: AppColors.textPrimary, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Allocated',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text('₱$totalCollected',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Donation Review Sheet ───────────────────────────────────────────────────

class DonationReviewSheet extends StatefulWidget {
  final DonationListing donation;
  final Future<void> Function({
  required DonationListing donation,
  required double amount,
  required String paymentMethod,
  required bool isAnonymous,
  }) onDonate;

  const DonationReviewSheet({
    super.key,
    required this.donation,
    required this.onDonate,
  });

  @override
  State<DonationReviewSheet> createState() => _DonationReviewSheetState();
}

class _DonationReviewSheetState extends State<DonationReviewSheet> {
  bool _isAnonymous = false;
  double _selectedAmount = 500;
  String? _selectedPayment;
  bool _submitting = false;

  final List<double> _quickAmounts = [50, 100, 200, 500];
  final List<String> _paymentMethods = ['Credit Card', 'PayPal', 'GCash', 'Maya'];

  @override
  Widget build(BuildContext context) {
    final donation = widget.donation;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Review Donation',
                style: GoogleFonts.tiltWarp(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),

            const SizedBox(height: 16),

            // Donation info row
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.tearspwn,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(donation.title,
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(donation.organizer,
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary.withValues(alpha: 0.7))),
                      Text('Write your wishes...',
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary.withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(thickness: 0.5),

            // Anonymous toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Donate as anonymous',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                Radio<bool>(
                  value: true,
                  groupValue: _isAnonymous ? true : null,
                  activeColor: AppColors.textPrimary,
                  onChanged: (v) => setState(() => _isAnonymous = !_isAnonymous),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(thickness: 0.5),
            // Amount input
            Text('Enter Amount',
                style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('₱',
                        style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: _selectedAmount.toInt().toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => _selectedAmount = double.tryParse(v) ?? _selectedAmount),
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Quick amounts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _quickAmounts.map((amt) => GestureDetector(
                onTap: () => setState(() => _selectedAmount = amt),
                child: Container(
                  width: 68,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _selectedAmount == amt
                        ? AppColors.textPrimary
                        : AppColors.background,
                    border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text('₱${amt.toInt()}',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          color: _selectedAmount == amt
                              ? AppColors.background
                              : AppColors.textPrimary)),
                ),
              )).toList(),
            ),

            const SizedBox(height: 16),
            const Divider(thickness: 0.5),

            // Payment method
            Text('Select Payment Method',
                style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ..._paymentMethods.map((method) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selectedPayment = method),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedPayment == method
                          ? AppColors.textPrimary
                          : AppColors.textPrimary.withValues(alpha: 0.2),
                      width: _selectedPayment == method ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _selectedPayment == method
                        ? AppColors.yellowrspwn.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Radio<String>(
                        value: method,
                        groupValue: _selectedPayment,
                        activeColor: AppColors.textPrimary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => setState(() => _selectedPayment = v),
                      ),
                      Text(method,
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            )),

            const SizedBox(height: 12),
            const Divider(thickness: 0.5),

            // Donation value summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Donation Value',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                Text('₱${_selectedAmount.toInt()}',
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),

            const SizedBox(height: 16),

            // Send Donation button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedPayment == null || _submitting)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textPrimary),
                )
                    : Text('Send Donation',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await widget.onDonate(
        donation: widget.donation,
        amount: _selectedAmount,
        paymentMethod: _selectedPayment!,
        isAnonymous: _isAnonymous,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}