import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_create.dart';
import 'donation_admin_filters.dart';
import 'donation_admin_info.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_records.dart';
import 'donation_admin_search.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/donation/general_expenses_page.dart';

/// Listings shown per section before "Show more".
const _homeListLimit = 3;

enum _ListingTab {
  donations('Donations', 'donation', 'New Campaign'),
  sponsorships('Sponsorships', 'sponsorship', 'New Sponsorship');

  const _ListingTab(this.label, this.type, this.createLabel);
  final String label;
  /// DonationListing.type
  final String type;
  final String createLabel;
}

/// Admin Donations & Sponsorships: one tab per listing type, each with its
/// current and completed listings; Recent Donations stays at the bottom.
class DonationAdminHomeScreen extends ConsumerStatefulWidget {
  const DonationAdminHomeScreen({super.key});

  @override
  ConsumerState<DonationAdminHomeScreen> createState() => _DonationAdminHomeScreenState();
}

class _DonationAdminHomeScreenState extends ConsumerState<DonationAdminHomeScreen> {
  static const _helpText = 'Create a campaign or sponsorship with the button at the bottom, then open a listing to '
      'track funds, record offline donations, confirm in-kind items and review its history. Each tab shows up to '
      'three listings per section; "View All" lists every current and completed one of that type. Searching looks '
      'through every current and completed listing in the tab.';

  _ListingTab _tab = _ListingTab.donations;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectTab(int index) => setState(() => _tab = _ListingTab.values[index]);

  void _openListing(DonationListing l) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: l.id)));

  /// Current and completed listings of the active tab's type.
  void _openAll() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DonationAdminSearchPage(fixedType: _tab.type, title: 'All Listings')),
      );

  void _openCompleted() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DonationAdminSearchPage(
            fixedType: _tab.type,
            initialStatuses: completedListingStatuses,
            title: 'Completed',
          ),
        ),
      );

  void _openCreate() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DonationAdminCreatePage(initialType: _tab.type)),
      );

  void _showHelp() => showInfoDialog(context, title: 'Donations & Sponsorships', message: _helpText, closeLabel: 'Got it');

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(adminCampaignsProvider);
    final recent = ref.watch(recentDonationsProvider);
    final needsDecision = (ref.watch(campaignsNeedingDecisionProvider).asData?.value ?? const <DonationListing>[])
        .where((l) => l.type == _tab.type)
        .toList();
    final isDonations = _tab == _ListingTab.donations;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.donations),
      appBar: AdminAppBar(
        title: 'Donations & Sponsorships',
        menuActions: [
          if (ref.watch(canManageFinancesProvider).asData?.value ?? false)
            AdminMenuAction(
              label: 'General Expenses',
              icon: Icons.receipt_long_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GeneralExpensesPage())),
            ),
          AdminMenuAction(label: 'Help', icon: Icons.lightbulb_outline, onTap: _showHelp),
        ],
        bottom: AdminTabBar(
          tabs: [for (final t in _ListingTab.values) AdminTab(t.label)],
          selectedIndex: _tab.index,
          onSelected: _selectTab,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.yellowrspwn,
        foregroundColor: AppColors.textPrimary,
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: Text(_tab.createLabel, style: GoogleFonts.tiltWarp(fontSize: 14)),
      ),
      body: Column(
        children: [
          AdminSearchBar(
            controller: _searchController,
            hintText: isDonations ? 'Search campaigns…' : 'Search sponsorships…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AdminTabSwipe(
              index: _tab.index,
              count: _ListingTab.values.length,
              onSelected: _selectTab,
              child: _query.isNotEmpty ? _searchResults(campaigns) : ListView(
              // Bottom padding keeps the last card clear of the FAB.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                // Deadline decisions must stay visible, so they only appear
                // when one is pending (donation campaigns only).
                if (needsDecision.isNotEmpty) ...[
                  Text('Needs your decision', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('These campaigns ended below their goal. Decide whether to extend them.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  for (final c in needsDecision) CampaignCard(listing: c, onTap: () => _openListing(c)),
                  const SizedBox(height: 16),
                ],

                _SectionHeader(title: 'Current', action: 'View All', onAction: _openAll),
                const SizedBox(height: 6),
                _listingSection(
                  campaigns,
                  (all) => currentListings(all, _tab.type),
                  empty: isDonations ? 'No current donation campaigns.' : 'No current sponsorships.',
                ),

                const SizedBox(height: 16),
                _SectionHeader(title: 'Completed', action: 'View All', onAction: _openCompleted),
                Text('Stays here until every peso is allocated, then it can be archived.',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _listingSection(
                  campaigns,
                  (all) => completedListings(all, _tab.type),
                  empty: isDonations ? 'No completed campaigns.' : 'No completed sponsorships.',
                ),

                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text('Recent Donations', style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary)),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationRecordsPage())),
                      child: Text('View all', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
                recent.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
                  ),
                  error: (e, _) =>
                      Text('Could not load donations: $e', style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
                  data: (items) => items.isEmpty
                      ? Text('No donations yet.', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary))
                      : Column(children: [for (final d in items) DonationRecordCard(record: d)]),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// Every current and completed listing of the active tab that matches the
  /// search text, in place of the sectioned home view.
  Widget _searchResults(AsyncValue<List<DonationListing>> campaigns) {
    return campaigns.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      error: (e, _) => const AdminListMessage('Could not load listings.'),
      data: (all) {
        final items = all
            .where((l) => matchesListingSearch(l, type: _tab.type, statuses: defaultSearchStatuses, query: _query))
            .toList();
        if (items.isEmpty) return const AdminListMessage('No listings match your search.');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [for (final l in items) CampaignCard(listing: l, onTap: () => _openListing(l))],
        );
      },
    );
  }

  Widget _listingSection(
    AsyncValue<List<DonationListing>> campaigns,
    List<DonationListing> Function(List<DonationListing> all) select, {
    required String empty,
  }) {
    return campaigns.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      ),
      error: (e, _) => Text('Could not load listings: $e', style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
      data: (all) {
        final items = select(all);
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(empty, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
          );
        }
        // Keyed by tab + section so switching tabs starts collapsed.
        return _ExpandableCards(key: ValueKey('${_tab.name}-$empty'), items: items, onTap: _openListing);
      },
    );
  }
}

/// Up to [_homeListLimit] cards with an inline Show more / Show less.
class _ExpandableCards extends StatefulWidget {
  final List<DonationListing> items;
  final ValueChanged<DonationListing> onTap;
  const _ExpandableCards({super.key, required this.items, required this.onTap});

  @override
  State<_ExpandableCards> createState() => _ExpandableCardsState();
}

class _ExpandableCardsState extends State<_ExpandableCards> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final overflow = items.length > _homeListLimit;
    final shown = _expanded || !overflow ? items : items.take(_homeListLimit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in shown) CampaignCard(listing: l, onTap: () => widget.onTap(l)),
        if (overflow)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textPrimary),
              label: Text(
                _expanded ? 'Show less' : 'Show more (${items.length - _homeListLimit})',
                style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionHeader({required this.title, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 19, color: AppColors.textPrimary))),
        InkWell(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Text(action, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}
