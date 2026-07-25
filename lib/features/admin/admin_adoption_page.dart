import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

/// Donations/Sponsorship landing page. Adoptions itself no longer routes
/// here — the admin drawer's Adoptions item opens the tabbed Adoption
/// Applications page directly (AdoptionApplicationReviewPage) — so this
/// page's own body no longer needs the adoption-pipeline "Adoption
/// Process" steps or the hardcoded "Upcoming Events" list it used to show
/// (literal fake names/dates shown regardless of what data actually
/// existed). There's no real donations data model in this codebase yet, so
/// this is an honest empty state rather than fabricated content.
class AdminAdoptionPage extends StatelessWidget {
  final bool showDonations;
  const AdminAdoptionPage({super.key, this.showDonations = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: AdminDrawer(active: showDonations ? AdminModule.donations : AdminModule.adoptions),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          showDonations ? 'Donation/Sponsorship' : 'Adoption',
          style: GoogleFonts.tiltWarp(
              fontSize: 18, color: AppColors.background),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              showDonations ? 'Donation Listing' : 'Adoption Listing',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 40),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volunteer_activism_outlined, size: 40, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      showDonations ? 'No donations yet.' : 'Nothing here yet.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
