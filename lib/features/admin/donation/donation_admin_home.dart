import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/stock/stock_page.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_create.dart';
import 'donation_admin_filters.dart';
import 'donation_admin_info.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_records.dart';
import 'donation_admin_search.dart';
import 'donation_admin_sheets.dart';
import 'expense_oversight_page.dart';
import 'general_expenses_page.dart';
import 'refund_request_page.dart';

/// Ongoing listings shown per section on the Campaigns tab; the rest are in
/// View all.
const _homeListLimit = 3;

enum _HomeTab {
  campaigns('Campaigns'),
  inKind('In Kind'),
  approvals('Approvals'),
  refunds('Refunds');

  const _HomeTab(this.label);
  final String label;
}

/// Admin Donations & Sponsorships: campaigns, in-kind stock, expense
/// approvals and refund requests, one tab each.
class DonationAdminHomeScreen extends ConsumerStatefulWidget {
  const DonationAdminHomeScreen({super.key, this.openOnRefunds = false});

  /// Opens on the Refunds tab (the dashboard's refund requests card).
  final bool openOnRefunds;

  @override
  ConsumerState<DonationAdminHomeScreen> createState() => _DonationAdminHomeScreenState();
}

class _DonationAdminHomeScreenState extends ConsumerState<DonationAdminHomeScreen> {
  static const _helpText = 'Campaigns: create a donation campaign or a sponsorship with New Campaign, then open a '
      'listing to track funds, record offline donations, confirm in-kind items and review its history. Up to three '
      'ongoing listings show per section; View all lists every current and past one.\n\n'
      'In Kind: stock on hand. Received in-kind donations are added automatically.\n'
      'Approvals: expenses waiting for a second financial admin, and overdue receipts.\n'
      'Refunds: donors\' refund requests to approve or decline.';

  late _HomeTab _tab = widget.openOnRefunds ? _HomeTab.refunds : _HomeTab.campaigns;

  void _selectTab(int i) => setState(() => _tab = _HomeTab.values[i]);

  Future<void> _newCampaign() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _NewCampaignSheet(),
    );
    if (type == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminCreatePage(initialType: type)));
  }

  Widget? _fab() => switch (_tab) {
        _HomeTab.campaigns => _YellowFab(label: 'New Campaign', onPressed: _newCampaign),
        _HomeTab.inKind => _YellowFab(label: 'Add item', onPressed: () => addStockItem(context, ref)),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final openRefunds = (ref.watch(allDonationsProvider).asData?.value ?? const [])
        .where((d) => d.refundRequest?.isOpen ?? false)
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.donations),
      appBar: AdminAppBar(
        title: 'Donations & Sponsorships',
        menuActions: [
          // A payment that isn't for a particular campaign goes to the
          // organization's General fund.
          if (canFinance)
            AdminMenuAction(
              label: 'Record donation (General fund)',
              icon: Icons.add_card_outlined,
              onTap: () => showAdminSheet(context, const OfflineDonationSheet()),
            ),
          if (canFinance)
            AdminMenuAction(
              label: 'General expenses',
              icon: Icons.receipt_long_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GeneralExpensesPage())),
            ),
          AdminMenuAction(
            label: 'Help',
            icon: Icons.lightbulb_outline,
            onTap: () =>
                showInfoDialog(context, title: 'Donations & Sponsorships', message: _helpText, closeLabel: 'Got it'),
          ),
        ],
        bottom: AdminTabBar(
          tabs: [
            for (final t in _HomeTab.values) AdminTab(t.label, count: t == _HomeTab.refunds ? openRefunds : null),
          ],
          selectedIndex: _tab.index,
          onSelected: _selectTab,
        ),
      ),
      floatingActionButton: _fab(),
      body: AdminTabSwipe(
        index: _tab.index,
        count: _HomeTab.values.length,
        onSelected: _selectTab,
        child: switch (_tab) {
          _HomeTab.campaigns => const _CampaignsTab(),
          _HomeTab.inKind => const StockTab(),
          _HomeTab.approvals => const ExpenseOversightTab(),
          _HomeTab.refunds => const RefundRequestsTab(),
        },
      ),
    );
  }
}

class _YellowFab extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _YellowFab({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        backgroundColor: AppColors.yellowrspwn,
        foregroundColor: AppColors.textPrimary,
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: Text(label, style: GoogleFonts.tiltWarp(fontSize: 14)),
      );
}

/// New Campaign: donation campaign or sponsorship. Pops the listing type.
class _NewCampaignSheet extends StatelessWidget {
  const _NewCampaignSheet();

  @override
  Widget build(BuildContext context) {
    Widget option(String type, String title, String subtitle) => InkWell(
          onTap: () => Navigator.pop(context, type),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel(title),
                      Text(subtitle, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textPrimary),
              ],
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New Campaign',
                textAlign: TextAlign.center, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            option('donation', 'Campaign', 'Raise funds toward a goal, like a surgery or supplies.'),
            option('sponsorship', 'Sponsorship', 'Monthly support for one animal. Choose the animal in the form.'),
          ],
        ),
      ),
    );
  }
}

class _CampaignsTab extends ConsumerWidget {
  const _CampaignsTab();

  void _openListing(BuildContext context, DonationListing l) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: l.id)));

  void _openAll(BuildContext context, {String? type}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminSearchPage(initialType: type)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(adminCampaignsProvider);
    final recent = ref.watch(recentDonationsProvider);
    final needsDecision = ref.watch(campaignsNeedingDecisionProvider).asData?.value ?? const <DonationListing>[];

    Widget current(String type, String empty) => campaigns.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
          ),
          error: (e, _) =>
              Text('Could not load listings: $e', style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
          data: (all) {
            final items = currentListings(all, type);
            if (items.isEmpty) return _Muted(empty);
            return Column(children: [
              for (final l in items.take(_homeListLimit)) CampaignCard(listing: l, onTap: () => _openListing(context, l)),
            ]);
          },
        );

    return ListView(
      // Bottom padding keeps the last row clear of the FAB.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Deadline decisions only appear while one is pending.
        if (needsDecision.isNotEmpty) ...[
          const DonationSectionHeader(
            'Needs your decision',
            help: 'These campaigns ended below their goal. Decide whether to extend them.',
          ),
          for (final c in needsDecision) CampaignCard(listing: c, onTap: () => _openListing(context, c)),
          const SizedBox(height: 16),
        ],
        DonationSectionHeader('Donations', action: 'View all', onAction: () => _openAll(context, type: 'donation')),
        current('donation', 'No ongoing donation campaigns.'),
        const SizedBox(height: 16),
        DonationSectionHeader('Sponsorships',
            action: 'View all', onAction: () => _openAll(context, type: 'sponsorship')),
        current('sponsorship', 'No ongoing sponsorships.'),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(
            style: AppButtons.outline,
            onPressed: () => _openAll(context),
            child: const Text('View all campaigns'),
          ),
        ),
        const SizedBox(height: 24),
        DonationSectionHeader(
          'Recent Donations',
          action: 'View all',
          onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationRecordsPage())),
        ),
        recent.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
          ),
          error: (e, _) =>
              Text('Could not load donations: $e', style: GoogleFonts.zain(fontSize: 14, color: AppColors.error)),
          data: (items) => items.isEmpty
              ? const _Muted('No donations yet.')
              : Column(children: [for (final d in items) DonationRecordCard(record: d)]),
        ),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  final String text;
  const _Muted(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
      );
}
