import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'models.dart';
import 'donation_payment_service.dart';
import 'donation_review.dart';
import 'sponsorship_summary.dart';

class SponsorshipDetail extends StatefulWidget {
  final DonationListing sponsorship;
  final VoidCallback onFavorite;

  const SponsorshipDetail({
    super.key,
    required this.sponsorship,
    required this.onFavorite,
  });

  @override
  State<SponsorshipDetail> createState() => _SponsorshipDetailState();
}

class _SponsorshipDetailState extends State<SponsorshipDetail> {
  final TextEditingController _amountController = TextEditingController();
  String? _selectedPayment;
  HistoryItem? _activeSponsorship;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkActiveSponsorship();
  }

  Future<void> _checkActiveSponsorship() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance.collection('donations')
          .where('userId', isEqualTo: uid)
          .where('campaignId', isEqualTo: widget.sponsorship.id)
          .where('type', isEqualTo: 'sponsorship')
          .get();

      if (snapshot.docs.isNotEmpty) {
        final now = DateTime.now();
        for (var doc in snapshot.docs) {
          final s = HistoryItem.fromFirestore(doc);
          final isActiveStatus = s.sponsorshipStatus == 'active';
          final isStillValid = isActiveStatus || (s.nextChargeDate != null && s.nextChargeDate!.isAfter(now));
          
          if (isStillValid) {
            if (mounted) {
              setState(() {
                _activeSponsorship = s;
                _isLoading = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking sponsorship: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sponsorship = widget.sponsorship;

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
          IconButton(icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary), onPressed: () {}),
          IconButton(
            icon: Icon(sponsorship.favorited ? Icons.favorite : Icons.favorite_border, color: sponsorship.favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary),
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
              height: 220, width: double.infinity,
              decoration: BoxDecoration(color: sponsorship.backgroundColor, borderRadius: BorderRadius.circular(20)),
              child: sponsorship.imageUrl != null 
                  ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(sponsorship.imageUrl!, fit: BoxFit.cover))
                  : const Icon(Icons.pets, size: 60, color: AppColors.textPrimary),
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
                      Text(sponsorship.animalName ?? 'Rescue Pet', style: GoogleFonts.tiltWarp(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('Rescue Pet • Young • Short Coat',
                        style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (sponsorship.isEnded ? Colors.grey : AppColors.greenrspwn).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sponsorship.isEnded ? 'Ended' : 'Available',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: sponsorship.isEnded ? AppColors.textPrimary.withValues(alpha: 0.6) : AppColors.greenrspwn,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tags
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                if (sponsorship.isDog)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.yellowrspwn.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                    child: Text('Dog', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // About Section
            Text('About ${sponsorship.animalName ?? "this pet"}', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(sponsorship.description, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary.withValues(alpha: 0.8), height: 1.4)),

            const SizedBox(height: 24),

            // Pet Health/Activity Stats
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCard(label: 'Health', value: 'Good', icon: Icons.favorite),
                _StatCard(label: 'Weight', value: 'Healthy', icon: Icons.monitor_weight),
                _StatCard(label: 'Activity', value: 'High', icon: Icons.bolt),
              ],
            ),

            const SizedBox(height: 24),

            if (_activeSponsorship == null && !sponsorship.isEnded) ...[
              Text('Monthly Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController, keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  prefixText: '₱ ', hintText: 'Enter amount...', filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greenrspwn, width: 2)),
                ),
                style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 24),
            ],

            // Recent Updates
            Text('Recent Updates', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildUpdatesList(sponsorship.id),

            const SizedBox(height: 32),

            // Sponsor Button
            SizedBox(
              width: double.infinity,
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
                : (sponsorship.isEnded && _activeSponsorship == null)
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)),
                      child: Text('This sponsorship campaign has ended.', textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary.withValues(alpha: 0.6))),
                    )
                  : ElevatedButton(
                      onPressed: _activeSponsorship != null 
                        ? _redirectToSummary
                        : () {
                          final amount = double.tryParse(_amountController.text);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
                            return;
                          }
                          _openSponsorshipSheet(context, amount);
                        },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _activeSponsorship != null ? AppColors.greenrspwn : AppColors.yellowrspwn, 
                        foregroundColor: _activeSponsorship != null ? Colors.white : AppColors.textPrimary, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), 
                        padding: const EdgeInsets.symmetric(vertical: 16), 
                        elevation: 0
                      ),
                      child: Text(
                        _activeSponsorship != null ? 'View Current Sponsorship' : 'Continue', 
                        style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesList(String campaignId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('campaigns').doc(campaignId).collection('updates').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Text('No updates yet.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary));
        }
        final updates = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        return Column(children: updates.map((u) => _UpdateTile(update: u)).toList());
      },
    );
  }

  void _openSponsorshipSheet(BuildContext context, double amount) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SponsorshipReviewSheet(sponsorship: widget.sponsorship, amount: amount));
  }

  void _redirectToSummary() {
    if (_activeSponsorship == null) return;
    
    final s = _activeSponsorship!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DonationSummaryScreen(
          params: DonationSummaryParams(
            charityName: s.organizer,
            donationMethod: s.donationMethod ?? 'Unknown',
            item: DonationItem(
              description: s.itemDescription ?? 'Monthly Sponsorship',
              amount: s.amount ?? 0,
            ),
            referenceNumber: s.refNumber,
            timestamp: s.dateTime,
            historyItem: s,
          ),
        ),
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
      decoration: BoxDecoration(color: AppColors.background, border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, size: 20, color: AppColors.greenrspwn),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
      ]),
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
            decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.5), shape: BoxShape.circle),
            child: Icon(_getIcon(update['type']), size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(update['title'] ?? 'Update', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    Text(update['date'] ?? '', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(update['description'] ?? '', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'health': return Icons.health_and_safety_outlined;
      case 'toy': return Icons.toys_outlined;
      case 'vaccine': return Icons.vaccines_outlined;
      default: return Icons.info_outline;
    }
  }
}

class SponsorshipReviewSheet extends StatefulWidget {
  final DonationListing sponsorship;
  final double amount;
  const SponsorshipReviewSheet({super.key, required this.sponsorship, required this.amount});
  @override
  State<SponsorshipReviewSheet> createState() => _SponsorshipReviewSheetState();
}

class _SponsorshipReviewSheetState extends State<SponsorshipReviewSheet> {
  String? _selectedPayment;
  final List<String> _paymentMethods = kDonationPaymentMethods.map((m) => m.label).toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Review Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('This payment covers 30 days of sponsorship. It does not renew automatically.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(color: widget.sponsorship.backgroundColor, borderRadius: BorderRadius.circular(10)),
                child: widget.sponsorship.imageUrl != null ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(widget.sponsorship.imageUrl!, fit: BoxFit.cover)) : const Icon(Icons.pets, size: 30, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.sponsorship.animalName ?? 'Rescue Pet', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                Text('Recurring Sponsorship - Every 30 days', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              ])),
              Text('₱${widget.amount.toInt()}', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.greenrspwn)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Select Payment Method', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ..._paymentMethods.map((method) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedPayment = method),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: _selectedPayment == method ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(12), color: _selectedPayment == method ? AppColors.yellowrspwn.withValues(alpha: 0.1) : Colors.transparent),
                child: Row(children: [
                  Radio<String>(value: method, groupValue: _selectedPayment, activeColor: AppColors.textPrimary, onChanged: (v) => setState(() => _selectedPayment = v)),
                  Text(method, style: GoogleFonts.zain(fontSize: 16)),
                ]),
              ),
            ),
          )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedPayment == null ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              child: Text('Confirm Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final nav = Navigator.of(context);
    final sponsorship = widget.sponsorship;
    final amount = widget.amount;
    final payment = _selectedPayment!;
    nav.pop(); // Close sheet
    nav.push(MaterialPageRoute(builder: (context) => DonationReviewScreen(params: DonationReviewParams(fundraiserId: sponsorship.id, organizationName: sponsorship.organizer, donationMethod: payment, item: DonationItem(description: 'Monthly Sponsorship: ${sponsorship.animalName ?? "Pet"}', amount: amount), isAnonymous: false, sponsorship: sponsorship, isSponsorship: true))));
  }
}
