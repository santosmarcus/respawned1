import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'package:intl/intl.dart';
import 'donation_cards.dart';
import 'donation_review.dart';
import 'donation_review_inkind.dart';
import 'models.dart';

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
  bool _showFundTracking = true;
  SponsorPet? _linkedAnimal;
  bool _animalLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.donation.animalId != null) {
      _loadLinkedAnimal();
    }
  }

  Future<void> _loadLinkedAnimal() async {
    setState(() => _animalLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('animals').doc(widget.donation.animalId).get();
      if (doc.exists && mounted) {
        setState(() {
          _linkedAnimal = SponsorPet.fromFirestore(doc);
          _animalLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _animalLoading = false);
    }
  }

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
          IconButton(icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary), onPressed: () {}),
          IconButton(
            icon: Icon(donation.favorited ? Icons.favorite : Icons.favorite_border, color: donation.favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary),
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
            // Image area
            _buildHeroImage(donation),
            const SizedBox(height: 16),

            // Title
            Text(donation.title, style: GoogleFonts.tiltWarp(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),

            // Animal Link Row if available
            if (_linkedAnimal != null) _buildAnimalQuickInfo(_linkedAnimal!),

            const SizedBox(height: 8),

            // Date & Stats row
            _buildInfoRow(donation),
            const SizedBox(height: 16),

            // About section
            Text('About the Donation', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(donation.description, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),

            const SizedBox(height: 20),

            // Progress row
            _buildProgressBar(donation),
            const SizedBox(height: 20),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatBox(label: 'Funds received', value: '${donation.percentage}%'),
                _StatBox(label: 'Target funds', value: '₱${_fmt(donation.target)}'),
                _StatBox(label: 'Days left', value: '${donation.daysRemaining}'),
              ],
            ),

            const SizedBox(height: 20),

            // In-Kind Donations Accepted
            _buildInKindSection(),

            const SizedBox(height: 24),

            // Organizer
            Text('Organizer', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: AppColors.tearspwn, child: const Icon(Icons.person, color: AppColors.textPrimary, size: 20)),
                const SizedBox(width: 10),
                Text(donation.organizer, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),

            const SizedBox(height: 24),

            // Fund Tracking toggle
            _buildFundTrackingSection(donation),

            const SizedBox(height: 24),

            // Buttons
            _buildActionButtons(context, donation),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImage(DonationListing donation) {
    return Container(
      height: 200, width: double.infinity,
      decoration: BoxDecoration(color: donation.backgroundColor, borderRadius: BorderRadius.circular(16)),
      child: donation.imageUrl != null 
          ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(donation.imageUrl!, fit: BoxFit.cover))
          : (_linkedAnimal != null && _linkedAnimal!.photoUrls.isNotEmpty)
              ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(_linkedAnimal!.photoUrls.first, fit: BoxFit.cover))
              : const Center(child: Icon(Icons.pets, size: 50, color: AppColors.textPrimary)),
    );
  }

  Widget _buildAnimalQuickInfo(SponsorPet pet) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.pets, size: 20, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Supporting ${pet.name} (${pet.breed}, ${pet.age} yrs)',
              style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ),
          if (pet.health.isNotEmpty)
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
               decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
               child: Text(pet.health.first, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.greenrspwn)),
             ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(DonationListing donation) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(donation.endDate != null ? DateFormat('MMMM dd, yyyy').format(donation.endDate!) : 'N/A',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('donations')
                  .where('campaignId', isEqualTo: donation.id)
                  .snapshots(),
              builder: (context, snapshot) {
                int uniqueDonors = 0;
                if (snapshot.hasData) {
                  final eligibleDocs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] as String?;
                    final status = data['status'] as String?;
                    if (type == 'inkind') {
                      return status == 'complete';
                    }
                    return true; // Monetary donations always count
                  });
                  uniqueDonors = eligibleDocs.map((doc) => (doc.data() as Map<String, dynamic>)['userId'] ?? doc.id).toSet().length;
                }
                return Text('$uniqueDonors people have donated', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary));
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.access_time_outlined, size: 14, color: AppColors.textPrimary),
            const SizedBox(width: 4),
            Text(donation.time, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(DonationListing donation) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: donation.percentage / 100,
              backgroundColor: AppColors.tearspwn.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.tearspwn),
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('₱${_fmt(donation.collected)}', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildInKindSection() {
    final donation = widget.donation;
    if (donation.inKindItems.isEmpty) return const SizedBox.shrink();

    // Group items by category
    final Map<String, List<String>> groupedItems = {};
    for (var item in donation.inKindItems) {
      groupedItems.putIfAbsent(item.category, () => []).add(item.description);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('In-Kind Donations Accepted:', style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        ...groupedItems.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InKindSection(title: entry.key, items: entry.value),
            )),
      ],
    );
  }

  Widget _buildFundTrackingSection(DonationListing donation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showFundTracking = !_showFundTracking),
          child: Row(
            children: [
              Text('Fund Tracking', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              Icon(_showFundTracking ? Icons.expand_less : Icons.expand_more, color: AppColors.textPrimary),
            ],
          ),
        ),
        if (_showFundTracking) ...[
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('campaigns').doc(donation.id).collection('allocations').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Text('No allocations recorded yet.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary));
              }
              final entries = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
              return _FundTrackingPanel(entries: entries, totalCollected: donation.collected.toInt());
            },
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, DonationListing donation) {
    if (donation.isEnded) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text('This campaign has ended.', textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary.withValues(alpha: 0.6))),
      );
    }
    final isStrictlyInKind = donation.type == 'inkind';
    final hasInKindItems = donation.inKindItems.isNotEmpty;
    
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: donation.donated ? null : () => _openReviewSheet(context, donation),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary,
              disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 16), elevation: 0,
            ),
            child: Text(donation.donated ? 'Donated ✓' : 'Donate', style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
        ),
        if (hasInKindItems && !isStrictlyInKind) ...[
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _openInKindReviewSheet(context, donation),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.yellowrspwn, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text('In-Kind', style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ],
    );
  }

  String _fmt(num value) => NumberFormat('#,##0').format(value);

  void _openReviewSheet(BuildContext context, DonationListing donation) {
    if (donation.type == 'inkind') {
      _openInKindReviewSheet(context, donation);
      return;
    }
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => DonationReviewSheet(donation: donation, onDonate: widget.onDonate)).then((_) => setState(() {}));
  }

  void _openInKindReviewSheet(BuildContext context, DonationListing donation) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => InKindDonationReviewSheet(donation: donation)).then((_) => setState(() {}));
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.tiltWarp(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _FundTrackingPanel extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final int totalCollected;
  const _FundTrackingPanel({required this.entries, required this.totalCollected});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Fund Tracking', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            Text('Recent updates', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.6))),
          ],
        ),
        const SizedBox(height: 16),
        ...entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e['label'] ?? 'Expense', style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Text(e['category'] ?? 'General', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₱${e['amount']}', style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  if (e['date'] != null) Text(e['date'], style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.6))),
                ],
              ),
            ],
          ),
        )),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Collected', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            Text('₱$totalCollected', style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}

class _InKindSection extends StatelessWidget {
  final String title;
  final List<String> items;
  const _InKindSection({required this.title, required this.items});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 4.0, top: 2.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              Expanded(child: Text(item, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
            ],
          ),
        )),
      ],
    );
  }
}

// ... DonationReviewSheet and InKindDonationReviewSheet remain mostly same but handle String IDs ...

class DonationReviewSheet extends StatefulWidget {
  final DonationListing donation;
  final Future<void> Function({
  required DonationListing donation,
  required double amount,
  required String paymentMethod,
  required bool isAnonymous,
  }) onDonate;

  const DonationReviewSheet({super.key, required this.donation, required this.onDonate});

  @override
  State<DonationReviewSheet> createState() => _DonationReviewSheetState();
}

class _DonationReviewSheetState extends State<DonationReviewSheet> {
  bool _isAnonymous = false;
  double _selectedAmount = 500;
  String? _selectedPayment;

  final List<double> _quickAmounts = [50, 100, 200, 500];
  final List<String> _paymentMethods = ['Credit Card', 'GCash', 'Maya'];

  @override
  Widget build(BuildContext context) {
    final donation = widget.donation;
    return Container(
      decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Monetary Donation', style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: donation.backgroundColor, borderRadius: BorderRadius.circular(10)),
                  child: donation.imageUrl != null ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(donation.imageUrl!, fit: BoxFit.cover)) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(donation.title, style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(donation.organizer, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withValues(alpha: 0.7))),
                ])),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 0.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Donate as anonymous', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                Switch(value: _isAnonymous, activeThumbColor: AppColors.yellowrspwn, onChanged: (v) => setState(() => _isAnonymous = v)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(thickness: 0.5),
            Text('Enter Amount', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _selectedAmount.toInt().toString(),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => _selectedAmount = double.tryParse(v) ?? _selectedAmount),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                prefixText: '₱ ', prefixStyle: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.yellowrspwn, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _quickAmounts.map((amt) => ChoiceChip(
                label: Text('₱${amt.toInt()}', style: GoogleFonts.zain(fontSize: 13)),
                selected: _selectedAmount == amt,
                onSelected: (selected) { if (selected) setState(() => _selectedAmount = amt); },
                selectedColor: AppColors.yellowrspwn, backgroundColor: AppColors.background,
                labelStyle: const TextStyle(color: AppColors.textPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _selectedAmount == amt ? AppColors.yellowrspwn : AppColors.textPrimary.withValues(alpha: 0.2))),
              )).toList(),
            ),
            const SizedBox(height: 24),
            Text('Select Payment Method', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ..._paymentMethods.map((method) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedPayment = method),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: _selectedPayment == method ? AppColors.yellowrspwn : AppColors.textPrimary.withValues(alpha: 0.2), width: _selectedPayment == method ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(12), color: _selectedPayment == method ? AppColors.yellowrspwn.withValues(alpha: 0.1) : Colors.transparent,
                  ),
                  child: Row(children: [
                    Radio<String>(value: method, groupValue: _selectedPayment, activeColor: AppColors.yellowrspwn, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onChanged: (v) => setState(() => _selectedPayment = v)),
                    const SizedBox(width: 8),
                    Text(method, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  ]),
                ),
              ),
            )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedPayment == null ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), padding: const EdgeInsets.symmetric(vertical: 16), elevation: 0),
                child: Text('Continue', style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final nav = Navigator.of(context);
    final donation = widget.donation;
    final amount = _selectedAmount;
    final payment = _selectedPayment;
    nav.pop(); // Dismiss sheet
    if (payment == 'Credit Card') {
      nav.push(MaterialPageRoute(builder: (context) => DonationCreditCardScreen(fundraiserId: donation.id, organizationName: donation.organizer, campaignName: donation.title, amount: amount, isAnonymous: _isAnonymous)));
    } else {
      nav.push(MaterialPageRoute(builder: (context) => DonationReviewScreen(params: DonationReviewParams(fundraiserId: donation.id, organizationName: donation.organizer, donationMethod: payment!, item: DonationItem(description: donation.title, amount: amount), isAnonymous: _isAnonymous))));
    }
  }
}

class InKindDonationReviewSheet extends StatefulWidget {
  final DonationListing donation;
  const InKindDonationReviewSheet({super.key, required this.donation});
  @override
  State<InKindDonationReviewSheet> createState() => _InKindDonationReviewSheetState();
}

class _InKindDonationReviewSheetState extends State<InKindDonationReviewSheet> {
  bool _isAnonymous = false;
  String? _selectedCategory;
  final TextEditingController _clarificationController = TextEditingController();
  final List<String> _categories = ['Food & Water', 'Medicine & Treatment', 'Supplies & Equipment', 'Hygiene & Cleaning', 'Others'];

  @override
  void dispose() { _clarificationController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final donation = widget.donation;
    return Container(
      decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('In-Kind Donation', style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: donation.backgroundColor, borderRadius: BorderRadius.circular(10)),
                  child: donation.imageUrl != null ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(donation.imageUrl!, fit: BoxFit.cover)) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(donation.title, style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(donation.organizer, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withValues(alpha: 0.7))),
                ])),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 0.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Donate as anonymous', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                Switch(value: _isAnonymous, activeThumbColor: AppColors.yellowrspwn, onChanged: (v) => setState(() => _isAnonymous = v)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(thickness: 0.5),
            Text('Select Item Category', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _categories.map((cat) => ChoiceChip(
                label: Text(cat, style: GoogleFonts.zain(fontSize: 13)),
                selected: _selectedCategory == cat,
                onSelected: (selected) { setState(() { _selectedCategory = selected ? cat : null; }); },
                selectedColor: AppColors.yellowrspwn, backgroundColor: AppColors.background,
                labelStyle: TextStyle(color: _selectedCategory == cat ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.7)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _selectedCategory == cat ? AppColors.yellowrspwn : AppColors.textPrimary.withValues(alpha: 0.2))),
              )).toList(),
            ),
            const SizedBox(height: 20),
            Text('Clarification / Details', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            TextField(
              controller: _clarificationController, maxLines: 3,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. 5kg Dog Food, 10 bottles of Alcohol...', hintStyle: GoogleFonts.zain(color: AppColors.textPrimary.withValues(alpha: 0.4)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.yellowrspwn, width: 2)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedCategory == null || _clarificationController.text.isEmpty
                    ? null
                    : () {
                        final nav = Navigator.of(context);
                        nav.pop(); // Dismiss sheet
                        nav.push(MaterialPageRoute(builder: (context) => DonationReviewInKindScreen(params: InKindDonationReviewParams(fundraiserId: donation.id, organizationName: donation.organizer, category: _selectedCategory!, clarification: _clarificationController.text, isAnonymous: _isAnonymous, address: donation.address))));
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), padding: const EdgeInsets.symmetric(vertical: 16), elevation: 0),
                child: Text('Continue', style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
