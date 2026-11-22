import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_filters.dart';
import 'donation_admin_info.dart';
import 'donation_admin_providers.dart';

enum _StatusTab {
  all('All'),
  ongoing('Ongoing'),
  completed('Completed');

  const _StatusTab(this.label);
  final String label;
}

/// View All: every listing, drafts and ended ones included. The tabs split
/// them by lifecycle; the filter sheet narrows by type (Donations /
/// Sponsorships) and can add archived listings.
class DonationAdminSearchPage extends ConsumerStatefulWidget {
  /// 'donation' or 'sponsorship' to open filtered to that type; null lists
  /// both. The admin can change it in the filter sheet.
  final String? initialType;
  const DonationAdminSearchPage({super.key, this.initialType});

  @override
  ConsumerState<DonationAdminSearchPage> createState() => _DonationAdminSearchPageState();
}

class _DonationAdminSearchPageState extends ConsumerState<DonationAdminSearchPage> {
  static const _helpText = 'Every listing, including drafts and ended campaigns. Drafts are only visible here until '
      'you publish them. Use the filter to show only donations or sponsorships, or to include archived listings.';

  _StatusTab _tab = _StatusTab.all;
  late String? _type = widget.initialType;

  /// Archived listings are fully allocated; hidden unless the admin asks.
  bool _showArchived = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectTab(int i) => setState(() => _tab = _StatusTab.values[i]);

  Future<void> _openFilter() async {
    var type = _type;
    var archived = _showArchived;
    final result = await showAdminFormSheet<(String?, bool)>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) => AdminSheetFrame(
          title: 'Filter',
          onDone: () => Navigator.pop(ctx, (type, archived)),
          children: [
            const FieldLabel('Type'),
            for (final (value, label) in const [(null, 'All'), ('donation', 'Donations'), ('sponsorship', 'Sponsorships')])
              CheckRow(label: label, value: type == value, onChanged: (_) => setSheet(() => type = value)),
            const SizedBox(height: 12),
            const FieldLabel('Status'),
            CheckRow(
              label: 'Include archived listings',
              value: archived,
              onChanged: (v) => setSheet(() => archived = v),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _type = result.$1;
        _showArchived = result.$2;
      });
    }
  }

  bool _matches(DonationListing l) {
    final archived = _showArchived ? const {'archived'} : const <String>{};
    return switch (_tab) {
      _StatusTab.all => matchesListingSearch(l, type: _type, statuses: {...defaultSearchStatuses, ...archived}, query: _query),
      _StatusTab.ongoing =>
        isCurrentListing(l) && matchesListingSearch(l, type: _type, statuses: currentListingStatuses, query: _query),
      _StatusTab.completed =>
        matchesListingSearch(l, type: _type, statuses: {...completedListingStatuses, ...archived}, query: _query),
    };
  }

  String get _emptyText {
    if (_query.isNotEmpty) return 'No listings match your search.';
    final noun = switch (_type) {
      'donation' => 'donation campaigns',
      'sponsorship' => 'sponsorships',
      _ => 'listings',
    };
    return switch (_tab) {
      _StatusTab.all => 'No $noun yet.',
      _StatusTab.ongoing => 'No ongoing $noun.',
      _StatusTab.completed => 'No completed $noun.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminCampaignsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AdminAppBar(
        title: 'Donations',
        showDrawerButton: false,
        menuActions: [
          AdminMenuAction(
            label: 'Help',
            icon: Icons.lightbulb_outline,
            onTap: () => showInfoDialog(context, title: 'All listings', message: _helpText, closeLabel: 'Got it'),
          ),
        ],
        bottom: AdminTabBar(
          tabs: [for (final t in _StatusTab.values) AdminTab(t.label)],
          selectedIndex: _tab.index,
          onSelected: _selectTab,
        ),
      ),
      body: Column(
        children: [
          AdminSearchBar(
            controller: _searchController,
            hintText: 'Search title, animal or organizer…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            filterTooltip: 'Filter by type',
            activeFilterCount: (_type != null ? 1 : 0) + (_showArchived ? 1 : 0),
            onFilter: _openFilter,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AdminTabSwipe(
              index: _tab.index,
              count: _StatusTab.values.length,
              onSelected: _selectTab,
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
                error: (e, _) => AdminListMessage('Could not load listings: $e'),
                data: (all) {
                  final items = all.where(_matches).toList();
                  if (items.isEmpty) return AdminListMessage(_emptyText);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final l in items)
                        CampaignCard(
                          listing: l,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: l.id)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
