import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'models.dart';
import 'donation_cards.dart';
import 'donation_review.dart';

class SponsorshipDetail extends StatefulWidget {
  final SponsorPet pet;
  final VoidCallback onFavorite;

  const SponsorshipDetail({
    super.key,
    required this.pet,
    required this.onFavorite,
  });

  @override
  State<SponsorshipDetail> createState() => _SponsorshipDetailState();
}

class _SponsorshipDetailState extends State<SponsorshipDetail> {
  final TextEditingController _amountController = TextEditingController();
  String? _selectedPayment;

  final List<String> _paymentMethods = ['Credit Card', 'PayPal', 'GCash', 'Maya'];

  final List<Map<String, dynamic>> _petUpdates = [
    {
      'title': 'Monthly Checkup',
      'date': 'March 15, 2026',
      'description': 'Regular checkup completed. Overall health is excellent and weight is stable.',
      'icon': Icons.health_and_safety_outlined,
    },
    {
      'title': 'New Toy Day',
      'date': 'March 10, 2026',
      'description': 'Thanks to our sponsors, a new enrichment toy was provided today!',
      'icon': Icons.toys_outlined,
    },
    {
      'title': 'Vaccination Update',
      'date': 'February 28, 2026',
      'description': 'Annual booster administered successfully.',
      'icon': Icons.vaccines_outlined,
    },
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;

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
              pet.favorited ? Icons.favorite : Icons.favorite_border,
              color: pet.favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary,
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
            // Pet Image
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.pets, size: 60, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 20),

            // Name and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pet.name,
                        style: GoogleFonts.tiltWarp(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${pet.breed} • ${pet.age} years old',
                        style: GoogleFonts.zain(
                          fontSize: 18,
                          color: AppColors.textPrimary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.greenrspwn.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Available',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.greenrspwn,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tags
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pet.tags.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )).toList(),
            ),

            const SizedBox(height: 24),

            // About Section
            Text(
              'About ${pet.name}',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              pet.description,
              style: GoogleFonts.zain(
                fontSize: 16,
                color: AppColors.textPrimary.withOpacity(0.8),
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),

            // Pet Health/Activity Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCard(label: 'Health', value: 'Excellent', icon: Icons.favorite),
                _StatCard(label: 'Weight', value: 'Healthy', icon: Icons.monitor_weight),
                _StatCard(label: 'Activity', value: 'High', icon: Icons.bolt),
              ],
            ),

            const SizedBox(height: 24),

            Text(
              'Monthly Sponsorship',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: 'Enter amount...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.greenrspwn, width: 2),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 24),

            // Recent Updates
            Text(
              'Recent Updates',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            ..._petUpdates.map((update) => _UpdateTile(update: update)),

            const SizedBox(height: 32),

            // Sponsor Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(_amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount')),
                    );
                    return;
                  }
                  _openSponsorshipSheet(context, amount);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openSponsorshipSheet(BuildContext context, double amount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SponsorshipReviewSheet(
        pet: widget.pet,
        amount: amount,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 60) / 3,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.greenrspwn),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _UpdateTile extends StatelessWidget {
  final Map<String, dynamic> update;
  const _UpdateTile({required this.update});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.tearspwn.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(update['icon'], size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(update['title'],
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    Text(update['date'],
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(update['description'],
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SponsorshipReviewSheet extends StatefulWidget {
  final SponsorPet pet;
  final double amount;

  const SponsorshipReviewSheet({
    super.key,
    required this.pet,
    required this.amount,
  });

  @override
  State<SponsorshipReviewSheet> createState() => _SponsorshipReviewSheetState();
}

class _SponsorshipReviewSheetState extends State<SponsorshipReviewSheet> {
  String? _selectedPayment;
  final List<String> _paymentMethods = ['Credit Card', 'PayPal', 'GCash', 'Maya'];

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Review Sponsorship',
              style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Your will be charged every 30 days, but you can cancel at any time.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          // Pet Summary
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pets, size: 30, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.pet.name,
                        style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                    Text('Recurring Sponsorship - Every 30 days',
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('₱${widget.amount.toInt()}',
                  style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.greenrspwn)),
            ],
          ),

          const SizedBox(height: 24),
          Text('Select Payment Method',
              style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          ..._paymentMethods.map((method) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedPayment = method),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedPayment == method
                        ? AppColors.textPrimary
                        : AppColors.textPrimary.withOpacity(0.2),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _selectedPayment == method
                      ? AppColors.yellowrspwn.withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Radio<String>(
                      value: method,
                      groupValue: _selectedPayment,
                      activeColor: AppColors.textPrimary,
                      onChanged: (v) => setState(() => _selectedPayment = v),
                    ),
                    Text(method, style: GoogleFonts.zain(fontSize: 16)),
                  ],
                ),
              ),
            ),
          )),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedPayment == null ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Confirm Sponsorship',
                  style: GoogleFonts.tiltWarp(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final nav = Navigator.of(context);
    final pet = widget.pet;
    final amount = widget.amount;
    final payment = _selectedPayment!;

    nav.pop(); // Close sheet

    if (payment == 'Credit Card') {
      nav.push(
        MaterialPageRoute(
          builder: (context) => DonationCreditCardScreen(
            fundraiserId: 'pet_${pet.id}',
            organizationName: 'Rescue Shelter',
            campaignName: 'Monthly Sponsorship: ${pet.name}',
            amount: amount,
            isAnonymous: false,
            pet: pet,
            isSponsorship: true,
          ),
        ),
      );
    } else {
      nav.push(
        MaterialPageRoute(
          builder: (context) => DonationReviewScreen(
            params: DonationReviewParams(
              fundraiserId: 'pet_${pet.id}',
              organizationName: 'Rescue Shelter',
              donationMethod: payment,
              item: DonationItem(
                description: 'Monthly Sponsorship: ${pet.name}',
                amount: amount,
              ),
              isAnonymous: false,
              pet: pet,
              isSponsorship: true,
            ),
          ),
        ),
      );
    }
  }
}
