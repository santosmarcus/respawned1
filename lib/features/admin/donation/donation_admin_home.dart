import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_create.dart';
import 'donation_admin_info.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_records.dart';
import 'donation_admin_search.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

/// Lifecycle statuses still "being tracked" (drafts included so admins can
/// find and publish them). Ended listings are reached through View All.
const _currentStatuses = {'draft', 'active', 'paused'};

/// Ongoing listings shown per section on the home screen; the rest are in View All.
const _homeListLimit = 3;

class DonationAdminHomeScreen extends ConsumerWidget {
  const DonationAdminHomeScreen({super.key});

  void _openListing(BuildContext context, DonationListing l) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: l.id)));

  /// Current and past listings of one type (search page, all statuses).
  void _openAll(BuildContext context, {required bool sponsorships}) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DonationAdminSearchPage(
        initialTab: sponsorships ? 2 : 1,
        title: sponsorships ? 'All Sponsorships' : 'All Donations',
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(adminCampaignsProvider);
    final recent = ref.watch(recentDonationsProvider);
    final needsDecision = ref.watch(campaignsNeedingDecisionProvider).asData?.value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.donations),
      body: Builder(
        builder: (context) => Column(
          children: [
            DonationAdminHeader(
              title: 'Donation/Sponsorship',
              onMenu: () => Scaffold.of(context).openDrawer(),
              helpText: 'Create a campaign or sponsorship, then open a listing to track funds, record offline '
                  'donations, confirm in-kind items and review its history. The home screen shows up to three '
                  'ongoing listings per section; "View All" lists every current and past one.',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                children: [
                  Center(
                    child: _ProcessItem(
                      icon: Icons.assignment_outlined,
                      label: 'Create a\nCampaign',
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationAdminCreatePage())),
                    ),
                  ),

                  // Not in the Figma frame: deadline decisions must stay
                  // visible somewhere, so they only appear when one is pending.
                  if (needsDecision.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Needs your decision', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('These campaigns ended below their goal. Decide whether to extend them.',
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    for (final c in needsDecision) CampaignCard(listing: c, onTap: () => _openListing(context, c)),
                  ],

                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'Donation Tracking',
                    action: 'View All Donations',
                    onAction: () => _openAll(context, sponsorships: false),
                  ),
                  const SizedBox(height: 6),
                  _trackingList(context, campaigns, type: 'donation', empty: 'No active donation campaigns.'),

                  const SizedBox(height: 16),
                  _SectionHeader(
                    title: 'Sponsorship Tracking',
                    action: 'View All Sponsorships',
                    onAction: () => _openAll(context, sponsorships: true),
                  ),
                  const SizedBox(height: 6),
                  _trackingList(context, campaigns, type: 'sponsorship', empty: 'No active sponsorships.'),

                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Recent Donations',
                            style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary)),
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
                        Text('Could not load donations: $e', style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent)),
                    data: (items) => items.isEmpty
                        ? Text('No donations yet.', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary))
                        : Column(children: [for (final d in items) DonationRecordCard(record: d)]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackingList(BuildContext context, AsyncValue<List<DonationListing>> campaigns,
      {required String type, required String empty}) {
    return campaigns.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      ),
      error: (e, _) => Text('Could not load listings: $e', style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent)),
      data: (all) {
        // Ended-by-date listings the hourly job hasn't processed yet still
        // read as "active"; isEnded keeps them out of the current list.
        final items = all
            .where((l) => l.type == type && _currentStatuses.contains(l.status) && (l.isDraft || l.status == 'paused' || !l.isEnded))
            .toList();
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(empty, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
          );
        }
        return Column(children: [
          for (final l in items.take(_homeListLimit)) CampaignCard(listing: l, onTap: () => _openListing(context, l)),
        ]);
      },
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

class _ProcessItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProcessItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.textPrimary),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, height: 1.1, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
