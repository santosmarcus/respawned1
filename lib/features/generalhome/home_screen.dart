import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/constants/feature_flags.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';
import 'package:respawnd1/features/donation/donation_page.dart';
import 'package:respawnd1/features/volunteerevent/volunteer_page.dart';
import 'package:respawnd1/features/organization/organization_list_page.dart';
import 'package:respawnd1/features/generalhome/activity_feed.dart';
import 'package:respawnd1/features/generalhome/all_activity_page.dart';
import 'package:respawnd1/features/rescue/all_explore_page.dart';
import 'explore_reports_map.dart';
import 'nearby_report.dart';
import '../../app_theme.dart';
import '../rescue/rescue_page.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .get(),
          builder: (context, snapshot){
            if(!snapshot.hasData){
              return const Text('Welcome!');
            }
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final firstName = data?['firstName'] ?? 'User';

            return Text('Welcome, $firstName!');
          },),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context, MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context, MaterialPageRoute(builder: (_) => const UserProfile()),
            );
          }
        },
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                ExploreReportsMap(
                  onSeeAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AllExploreReportsPage()),
                  ),
                ),

                const SizedBox(height: 24),

                // Quick action cards
                SizedBox(
                  height: 65,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _QuickActionCard(
                        label: 'Report a\nRescue',
                        color: AppColors.lavenderrspwn,
                        onTap: (){
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RescuePage(),
                            ),
                          );
                        },
                      ),
                      _QuickActionCard(
                        label: 'Adopt a\nRescue',
                        color: AppColors.greenrspwn,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => AdoptionPage(),
                          ),
                          );
                        },
                      ),
                      _QuickActionCard(
                        label: 'Donate or\nSponsor',
                        color: AppColors.pinkrspwn,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => DonationPage(),
                          ),
                          );
                        },
                      ),
                      _QuickActionCard(
                        label: 'Volunteer',
                        color: AppColors.yellowrspwn,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => VolunteerPage(),
                          ),
                          );
                        },
                      ),
                      // Temporarily disabled (FeatureFlags.
                      // organizationsFeatureEnabled) — route, page, models,
                      // and repositories all stay in the codebase; only
                      // this user-facing entry point is hidden/disabled.
                      _QuickActionCard(
                        label: 'Organization',
                        color: AppColors.lavenderrspwn,
                        disabled: !FeatureFlags.organizationsFeatureEnabled,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => OrganizationsListPage(),
                          ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Active Cases section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Activity',
                        style: GoogleFonts.tiltWarp(fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AllActivityPage(),
                          ),
                        ),
                        child: Text(
                          'See All',
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                ActivityFeed(),

                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Post Adoption',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const PostAdoption(),

                const SizedBox(height: 24)
              ],
            ),
          ),

          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NearbyReportBanner(),
          ),
        ],
      ),
    );
  }
}

// Reusable quick action card widget
class _QuickActionCard extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  // Feature-flagged entries (e.g. Organizations) render dimmed with a
  // "Coming soon" line instead of a silently-inert active-looking button —
  // never show a button that looks tappable but does nothing.
  final bool disabled;

  const _QuickActionCard({required this.label, required this.color, this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          width: 111,
          height: 139,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsetsGeometry.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tiltWarp(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (disabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Coming soon',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}