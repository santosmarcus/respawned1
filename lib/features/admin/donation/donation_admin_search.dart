import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_info.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

class DonationAdminSearchPage extends ConsumerStatefulWidget {
  /// 0 All, 1 Donations, 2 Sponsorships.
  final int initialTab;
  /// Statuses shown at first (all when null); "View Past Donations" passes the ended ones.
  final Set<String>? initialStatuses;
  final String title;
  const DonationAdminSearchPage({
    super.key,
    this.initialTab = 0,
    this.initialStatuses,
    this.title = 'Search Donation/Sponsorship',
  });

  @override
  ConsumerState<DonationAdminSearchPage> createState() => _DonationAdminSearchPageState();
}

class _DonationAdminSearchPageState extends ConsumerState<DonationAdminSearchPage> {
  static const _tabs = ['All', 'Donations', 'Sponsorships'];
  late int _tab = widget.initialTab;
  String _query = '';
  // Filter sheet: which lifecycle statuses to show (all but archived by
  // default — archived listings are fully allocated; tick it to audit them).
  late Set<String> _statuses =
  Set.of(widget.initialStatuses ?? const {'draft', 'active', 'paused', 'goal_met', 'goal_not_met', 'closed'});

  Future<void> _openFilter() async {
    final picked = Set<String>.of(_statuses);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AdminSheetFrame(
          title: 'Filter',
          onDone: () => Navigator.pop(ctx, picked),
          children: [
            for (final s in const ['draft', 'active', 'paused', 'goal_met', 'goal_not_met', 'closed', 'archived'])
              CheckRow(
                label: campaignStatusLabel(s),
                value: picked.contains(s),
                onChanged: (v) => setSheet(() => v ? picked.add(s) : picked.remove(s)),
              ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _statuses = result);
  }

  bool _matches(DonationListing l) {
    if (_tab == 1 && l.type != 'donation') return false;
    if (_tab == 2 && l.type != 'sponsorship') return false;
    if (!_statuses.contains(l.status)) return false;
    if (_query.isEmpty) return true;
    return l.title.toLowerCase().contains(_query) ||
        (l.animalName ?? '').toLowerCase().contains(_query) ||
        l.organizer.toLowerCase().contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminCampaignsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          DonationAdminHeader(
            title: widget.title,
            helpText: 'Every listing, including drafts and ended campaigns. Drafts are only visible here until you publish them.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary),
                      filled: true,
                      fillColor: const Color(0xFFFFF1C7),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Filter by status',
                  icon: const Icon(Icons.tune, color: AppColors.textPrimary),
                  onPressed: _openFilter,
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  InkWell(
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: i == _tab ? AppColors.textPrimary : Colors.transparent, width: 2)),
                      ),
                      child: Text(_tabs[i],
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              color: i == _tab ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: i == _tab ? FontWeight.w800 : FontWeight.w500)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
              error: (e, _) => Center(child: Text('Could not load listings: $e', style: GoogleFonts.zain(color: Colors.redAccent))),
              data: (all) {
                final items = all.where(_matches).toList();
                if (items.isEmpty) {
                  return Center(
                      child: Text('No listings found.', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    for (final l in items)
                      CampaignCard(
                        listing: l,
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: l.id))),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
