import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import 'models.dart';

/// Public "Fund Tracking" for one listing: where its money went, read from
/// `campaigns/{id}/allocations` (written only by the admin backend).
///
/// For a sponsorship the listing *is* the animal's, so these are exactly the
/// funds allocated for the sponsored animal.
class FundTrackingSection extends StatefulWidget {
  final DonationListing listing;
  final bool initiallyExpanded;
  const FundTrackingSection({super.key, required this.listing, this.initiallyExpanded = true});

  @override
  State<FundTrackingSection> createState() => _FundTrackingSectionState();
}

class _FundTrackingSectionState extends State<FundTrackingSection> {
  late bool _expanded = widget.initiallyExpanded;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = FirebaseFirestore.instance
      .collection('campaigns')
      .doc(widget.listing.id)
      .collection('allocations')
      .snapshots();

  static double _amount(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    return 0;
  }

  static String _peso(num v) {
    final cents = (v * 100).round();
    final whole = (cents ~/ 100).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final frac = cents % 100;
    return '₱$whole${frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final title = l.type == 'sponsorship' ? 'Fund Tracking for ${l.animalName ?? 'this pet'}' : 'Fund Tracking';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Expanded(child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary))),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textPrimary),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(color: AppColors.greenrspwn);
              }
              final docs = [...?snapshot.data?.docs]..sort((a, b) {
                final ta = a.data()['createdAt'], tb = b.data()['createdAt'];
                if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                return 0;
              });
              final allocated = docs.fold<double>(0, (s, d) => s + _amount(d.data()['amount']));
              final remaining = l.availableBalance > 0 ? l.availableBalance : 0;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Figure('Received', _peso(l.collected)),
                        _Figure('Allocated', _peso(allocated)),
                        _Figure('Not yet allocated', _peso(remaining)),
                      ],
                    ),
                    if (l.transferredInAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Includes ${_peso(l.transferredInAmount)} of existing funds moved from another campaign (not new donations).',
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                    const Divider(height: 22),
                    if (docs.isEmpty)
                      Text('No allocations recorded yet.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary))
                    else
                      for (final d in docs) _AllocationRow(data: d.data(), amount: _peso(_amount(d.data()['amount']))),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  const _Figure(this.label, this.value);

  @override
  Widget build(BuildContext context) => Flexible(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
}

class _AllocationRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String amount;
  const _AllocationRow({required this.data, required this.amount});

  @override
  Widget build(BuildContext context) {
    final isTransfer = data['kind'] == 'transfer_out';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTransfer)
            const Padding(
              padding: EdgeInsets.only(right: 6, top: 2),
              child: Icon(Icons.call_split, size: 16, color: AppColors.textPrimary),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((data['label'] ?? data['title'] ?? 'Expense').toString(),
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text((data['category'] ?? 'General').toString(),
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              if (data['date'] is String)
                Text(data['date'] as String, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
