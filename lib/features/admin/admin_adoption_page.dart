import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

class AdminAdoptionPage extends StatelessWidget {
  final bool showDonations;
  const AdminAdoptionPage({super.key, this.showDonations = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Adoption/Donation Listing
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  showDonations ? 'Donation Listing' : 'Adoption Listing',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add,
                      color: AppColors.background, size: 18),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Adoption Process label
            Text('Adoption Process',
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),

            const SizedBox(height: 12),

            // Process steps
            _ProcessSteps(),

            const SizedBox(height: 24),

            // Upcoming Events label
            Text('Upcoming Events',
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),

            const SizedBox(height: 12),

            // Events list
            _EventCard(
              date: '20 February',
              title: 'Adoption Interview | Clarrisa Sta. Cruz',
            ),
            const SizedBox(height: 8),
            _EventCard(
              date: '24 February',
              title: 'Adoption Interview | Mae Santos',
            ),
            const SizedBox(height: 8),
            _EventCard(
              date: '20 February',
              title: 'Adoption Interview | Francis De la Cruz',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessSteps extends ConsumerWidget {
  static const _steps = [
    (label: 'Application\nReview', icon: Icons.description_outlined, tab: AdoptionStatus.pending),
    (label: 'Set\nInterview', icon: Icons.calendar_month_outlined, tab: AdoptionStatus.interview),
    (label: 'Animal\nRelease', icon: Icons.favorite_outline, tab: AdoptionStatus.approved),
    (label: 'Post-\nAdoption', icon: Icons.star_outline, tab: AdoptionStatus.adopted),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: _steps.map((step) {
        // Real, live counts instead of hardcoded numbers — no badge at all
        // while still loading or once the count is zero, a real count once
        // it's known and positive.
        final countAsync = ref.watch(adoptionsByStatusesProvider([step.tab]));
        final count = countAsync.asData?.value.length;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdoptionApplicationReviewPage(initialStatus: step.tab)),
          ),
          child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.slaterspwn,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(step.icon,
                      color: AppColors.textPrimary, size: 26),
                ),
                if (count != null && count > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              step.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
          ),
        );
      }).toList(),
    );
  }
}

class _EventCard extends StatelessWidget {
  final String date;
  final String title;

  const _EventCard({required this.date, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date,
                  style: GoogleFonts.zain(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text(title,
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}
