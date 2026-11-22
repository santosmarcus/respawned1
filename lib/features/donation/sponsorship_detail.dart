import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app_theme.dart';
import 'models.dart';
import 'donation_payment_service.dart';
import 'donation_review.dart';
import 'fund_tracking_section.dart';
import 'cancel_dialog.dart';
import 'package:respawnd1/features/generalhome/history_provider.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

class SponsorshipDetail extends ConsumerStatefulWidget {
  final DonationListing sponsorship;
  final VoidCallback onFavorite;

  const SponsorshipDetail({
    super.key,
    required this.sponsorship,
    required this.onFavorite,
  });

  @override
  ConsumerState<SponsorshipDetail> createState() => _SponsorshipDetailState();
}

class _SponsorshipDetailState extends ConsumerState<SponsorshipDetail> {
  final TextEditingController _amountController = TextEditingController();
  HistoryItem? _activeSponsorship;
  bool _isLoading = true;

  /// Everything this user has paid for this animal's sponsorship (refunds
  /// left out), across renewals.
  double _myTotal = 0;
  int _myPayments = 0;

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

      var total = 0.0;
      var payments = 0;
      for (final doc in snapshot.docs) {
        final d = doc.data();
        if (d['status'] == 'reversed') continue;
        final amount = d['amount'];
        if (amount is num && amount > 0) {
          total += amount.toDouble();
          payments++;
        }
      }
      if (mounted) {
        setState(() {
          _myTotal = total;
          _myPayments = payments;
        });
      }

      if (snapshot.docs.isNotEmpty) {
        final now = DateTime.now();
        for (var doc in snapshot.docs) {
          final s = HistoryItem.fromFirestore(doc);
          final isActiveStatus = s.sponsorshipStatus == 'active';
          // A refunded sponsorship (refund request flow) never counts.
          final isStillValid = s.sponsorshipStatus != 'refunded' &&
              (isActiveStatus || (s.nextChargeDate != null && s.nextChargeDate!.isAfter(now)));

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
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
            onPressed: () => SharePlus.instance.share(ShareParams(text: sponsorship.shareText)),
          ),
          IconButton(
            icon: Icon(sponsorship.favorited ? Icons.favorite : Icons.favorite_border, color: sponsorship.favorited ? AppColors.error : AppColors.textPrimary),
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
                    color: (sponsorship.isEnded
                            ? Colors.grey
                            : sponsorship.isFullyFunded
                                ? AppColors.lavenderrspwn
                                : AppColors.greenrspwn)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sponsorship.isEnded
                        ? 'Ended'
                        : sponsorship.isFullyFunded
                            ? 'Fully Funded'
                            : 'Open for Sponsorship',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: sponsorship.isEnded || sponsorship.isFullyFunded
                          ? AppColors.textPrimary.withValues(alpha: 0.6)
                          : AppColors.greenrspwn,
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

            // How many people sponsor this animal now (kept on the listing
            // by functions/sponsor_counts.js).
            _SponsorCount(campaignId: sponsorship.id),
            const SizedBox(height: 16),

            if (_activeSponsorship != null) ...[
              _YourSponsorshipCard(
                sponsorship: _activeSponsorship!,
                myTotal: _myTotal,
                myPayments: _myPayments,
                collected: sponsorship.collected,
                onStop: _stopSponsorship,
                onReactivate: _reactivateSponsorship,
              ),
              const SizedBox(height: 24),
            ],

            // Fully funded: new sponsors wait until its funds run low again
            // (people already sponsoring keep their sponsorship).
            if (_activeSponsorship == null && !sponsorship.isEnded && !sponsorship.isFullyFunded) ...[
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

            // Where this pet's sponsorship money went (allocations on this
            // sponsorship listing, which belongs to this animal only).
            FundTrackingSection(listing: sponsorship),
            const SizedBox(height: 24),

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
              // Already sponsoring: everything is in "Your sponsorship"
              // above (the summary opens from History).
                  : _activeSponsorship != null
                  ? const SizedBox.shrink()
                  : sponsorship.isFullyFunded && !sponsorship.isEnded
                  ? Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)),
                child: Text(
                  '${sponsorship.animalName ?? 'This animal'} is fully funded for now. '
                  'Sponsorship reopens if its funds run low.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary.withValues(alpha: 0.6)),
                ),
              )
                  : sponsorship.isEnded
                  ? Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)),
                child: Text('This sponsorship campaign has ended.', textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary.withValues(alpha: 0.6))),
              )
                  : ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(_amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Please enter a valid amount'));
                    return;
                  }
                  _openSponsorshipSheet(context, amount);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0
                ),
                child: Text(
                    'Continue',
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

  /// Stop: the sponsorship still covers the animal until its end date,
  /// then ends (no new payment). Same as History's old Cancel Sponsorship.
  void _stopSponsorship() {
    final s = _activeSponsorship;
    if (s == null) return;
    final until = s.nextChargeDate != null ? _date(s.nextChargeDate!) : 'the end of your current period';
    showCancelDialog(
      context: context,
      title: 'Are You Sure?',
      message: 'You are about to cancel your sponsorship. It will remain active until $until.',
      onConfirm: () {
        ref.read(historyProvider.notifier).cancelSponsorship(s.id);
        setState(() => _activeSponsorship = s.copyWith(sponsorshipStatus: 'cancelled'));
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Sponsorship cancelled successfully.'));
      },
    );
  }

  void _reactivateSponsorship() {
    final s = _activeSponsorship;
    if (s == null) return;
    ref.read(historyProvider.notifier).unCancelSponsorship(s.id);
    setState(() => _activeSponsorship = s.copyWith(sponsorshipStatus: 'active'));
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Sponsorship reactivated successfully.'));
  }

}

String _date(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _peso(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return '₱$whole.${parts[1]}';
}

/// "N people are sponsoring right now".
class _SponsorCount extends StatelessWidget {
  const _SponsorCount({required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('campaigns').doc(campaignId).snapshots(),
      builder: (context, snap) {
        final n = snap.data?.data()?['activeSponsorCount'];
        if (n is! num) return const SizedBox.shrink();
        final count = n.toInt();
        return Row(
          children: [
            const Icon(Icons.groups, size: 20, color: AppColors.greenrspwn),
            const SizedBox(width: 8),
            Text(
              count == 0
                  ? 'No one is sponsoring right now'
                  : '$count ${count == 1 ? 'person is' : 'people are'} sponsoring right now',
              style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ],
        );
      },
    );
  }
}

/// The signed-in sponsor's own sponsorship: status, next charge date and
/// amount, and their share of what this animal's sponsors have given.
class _YourSponsorshipCard extends StatelessWidget {
  const _YourSponsorshipCard({
    required this.sponsorship,
    required this.myTotal,
    required this.myPayments,
    required this.collected,
    required this.onStop,
    required this.onReactivate,
  });

  final VoidCallback onStop;
  final VoidCallback onReactivate;

  final HistoryItem sponsorship;
  final double myTotal;
  final int myPayments;

  /// Everything collected for this animal, from every sponsor.
  final double collected;

  @override
  Widget build(BuildContext context) {
    final s = sponsorship;
    final stopped = s.sponsorshipStatus == 'cancelled';
    final next = s.nextChargeDate;
    final nextAmount = s.nextChargeAmount ?? s.amount;
    final share = collected > 0 ? (myTotal / collected).clamp(0.0, 1.0) : null;

    Widget row(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary))),
          Expanded(
            child: Text(v,
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenrspwn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greenrspwn.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your sponsorship', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          row('Status', stopped ? 'Stopped' : 'Active', color: stopped ? AppColors.error : AppColors.greenrspwn),
          if (next != null) row(stopped ? 'Ends on' : 'Next charge date', _date(next)),
          if (!stopped && nextAmount != null) row('Next amount', _peso(nextAmount)),
          if (myPayments > 0) row('You have given', '${_peso(myTotal)} in ${myPayments == 1 ? '1 payment' : '$myPayments payments'}'),
          if (share != null && myPayments > 0)
            row('Of all funds', '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}% of ${_peso(collected)} collected'),
          const SizedBox(height: 6),
          Text(
            stopped
                ? 'You stopped this sponsorship. It covers the animal until the date above, then ends.'
                : 'You will be notified 3 days before the next charge date to continue or stop. If it is not '
                'renewed by then, the sponsorship ends.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Below: how the funds from you and the other sponsors were used.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: stopped
                ? ElevatedButton(
              onPressed: onReactivate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.greenrspwn,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Reactivate Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold)),
            )
                : OutlinedButton(
              onPressed: onStop,
              style: AppButtons.dangerOutline,
              child: Text('Cancel Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
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
                  RadioGroup<String>(groupValue: _selectedPayment, onChanged: (v) => setState(() => _selectedPayment = v), child: Radio<String>(value: method, activeColor: AppColors.textPrimary)),
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
              style: AppButtons.primary,
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
