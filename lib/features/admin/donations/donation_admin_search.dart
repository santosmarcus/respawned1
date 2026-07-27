import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'donation_admin_models.dart';
import 'donation_admin_provider.dart';
import 'donation_admin_info.dart';

class DonationAdminSearchPage extends StatefulWidget {
  const DonationAdminSearchPage({super.key});

  @override
  State<DonationAdminSearchPage> createState() => _DonationAdminSearchPageState();
}

class _DonationAdminSearchPageState extends State<DonationAdminSearchPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToInfo(BuildContext context, DonationCampaign campaign) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaign: campaign)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 24),
            color: AppColors.textPrimary,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: AppColors.background),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Icon(Icons.lightbulb_outline, color: AppColors.background),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Search Campaigns',
                    style: GoogleFonts.tiltWarp(
                      color: AppColors.background,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => context.read<DonationAdminProvider>().updateSearch(val),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary),
                      hintText: 'Search',
                      hintStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.tearspwn,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.tune, color: AppColors.textPrimary),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          Consumer<DonationAdminProvider>(builder: (context, provider, _) {
            return Expanded(
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      provider.updateTab(index);
                    },
                    indicatorColor: AppColors.textPrimary,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Donations'),
                      Tab(text: 'Sponsorships'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: provider.filteredCampaigns.isEmpty 
                      ? Center(child: Text("No campaigns found.", style: GoogleFonts.zain(color: AppColors.textSecondary)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: provider.filteredCampaigns.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final item = provider.filteredCampaigns[index];
                            return InkWell(
                              onTap: () => _navigateToInfo(context, item),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: item.backgroundColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: GoogleFonts.tiltWarp(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (item.type != 'sponsorship') ...[
                                            const Text('Target Goal', style: TextStyle(color: AppColors.textSecondary)),
                                            Text(
                                              item.amount,
                                              style: GoogleFonts.tiltWarp(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 22,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Text(item.daysRemaining, style: const TextStyle(color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
