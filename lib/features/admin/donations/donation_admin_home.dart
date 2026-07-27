import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'donation_admin_models.dart';
import 'donation_admin_provider.dart';
import 'donation_admin_create.dart';
import 'donation_admin_search.dart';
import 'donation_admin_donosearch.dart';
import 'donation_admin_donoinfo.dart';

class DonationAdminHomeScreen extends StatefulWidget {
  const DonationAdminHomeScreen({super.key});

  @override
  State<DonationAdminHomeScreen> createState() => _DonationAdminHomeScreenState();
}

class _DonationAdminHomeScreenState extends State<DonationAdminHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AdminDrawer(),
      body: Column(
        children: [
          Container(
            height: 120,
            color: AppColors.textPrimary,
            padding: const EdgeInsets.only(top: 40, left: 20, right: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: const Icon(Icons.menu, color: AppColors.background, size: 28),
                ),
                Text('Donation',
                    style: GoogleFonts.tiltWarp(
                        color: AppColors.background,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const Icon(Icons.lightbulb_outline,
                    color: AppColors.background, size: 28),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ProcessItem(
                        icon: Icons.campaign,
                        label: 'Create a\nCampaign',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DonationAdminCreatePage()),
                          );
                        },
                      ),
                      _ProcessItem(
                        icon: Icons.receipt_long,
                        label: 'View\nCampaigns',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DonationAdminSearchPage()),
                          );
                        },
                      ),
                      _ProcessItem(
                        icon: Icons.search,
                        label: 'Search\nDonations',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DonationSearchPage()),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Recent Donations',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 20,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Consumer<DonationAdminProvider>(
                    builder: (context, data, child) => Column(
                      children: data.recentDonations
                          .map<Widget>((item) => _DonationCard(item: item))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Icon(icon, size: 36, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _DonationCard extends StatelessWidget {
  final DonationHistoryRecord item;
  const _DonationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DonationDetailsScreen(donation: item)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.title,
                    style: GoogleFonts.zain(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(item.date,
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            Text(item.amount,
                style: GoogleFonts.zain(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
