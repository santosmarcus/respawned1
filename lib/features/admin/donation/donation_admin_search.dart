import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_filters.dart';
import 'donation_admin_info.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

class DonationAdminSearchPage extends ConsumerStatefulWidget {
  /// 0 All, 1 Donations, 2 Sponsorships. Ignored when [fixedType] is set.
  final int initialTab;

  /// 'donation' or 'sponsorship': only that type is listed and the type tab
  /// row is hidden (the home screen's tab already picked it).
  final String? fixedType;

  /// Statuses shown at first (all but archived when null).
  final Set<String>? initialStatuses;
  final String title;
  const DonationAdminSearchPage({
    super.key,
    this.initialTab = 0,
    this.fixedType,
    this.initialStatuses,
    this.title = 'Search Donation/Sponsorship',
  });

  @override
  ConsumerState<DonationAdminSearchPage> createState() => _DonationAdminSearchPageState();
}

class _DonationAdminSearchPageState extends ConsumerState<DonationAdminSearchPage> {
  static const _tabs = ['All', 'Donations', 'Sponsorships'];
  late int _tab = widget.initialTab;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  // Filter sheet: which lifecycle statuses to show (all but archived by
  // default — archived listings are fully allocated; tick it to audit them).
  late Set<String> _statuses = Set.of(widget.initialStatuses ?? defaultSearchStatuses);

  String? get _type =>
      widget.fixedType ??
      switch (_tab) {
        1 => 'donation',
        2 => 'sponsorship',
        _ => null,
      };

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

  bool _matches(DonationListing l) => matchesListingSearch(l, type: _type, statuses: _statuses, query: _query);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminCampaignsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          DonationAdminHeader(
            title: widget.title,
            helpText:
                'Every listing, including drafts and ended campaigns. Drafts are only visible here until you '
                'publish them. Use the filter to change which statuses are shown, including archived ones.',
          ),
          AdminSearchBar(
            controller: _searchController,
            hintText: 'Search listings…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            filterTooltip: 'Filter by status',
            filterActive: !(_statuses.length == defaultSearchStatuses.length && _statuses.containsAll(defaultSearchStatuses)),
            onFilter: _openFilter,
          ),
          if (widget.fixedType == null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.slaterspwn)),
              ),
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
                            bottom: BorderSide(color: i == _tab ? AppColors.textPrimary : Colors.transparent, width: 2),
                          ),
                        ),
                        child: Text(
                          _tabs[i],
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: i == _tab ? AppColors.textPrimary : AppColors.textSecondary,
                            fontWeight: i == _tab ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
              error: (e, _) => Center(
                child: Text('Could not load listings: $e', style: GoogleFonts.zain(color: AppColors.error)),
              ),
              data: (all) {
                final items = all.where(_matches).toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No listings found.',
                      style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
        ],
      ),
    );
  }
}
