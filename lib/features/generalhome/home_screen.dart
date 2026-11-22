import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/community_adoption_checkins.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';
import 'package:respawnd1/features/adoption/sponsored_animals_section.dart';
import 'package:respawnd1/features/donation/donation_page.dart';
import 'package:respawnd1/features/volunteerevent/volunteer_page.dart';
import 'package:respawnd1/features/generalhome/activity_feed.dart';
import 'package:respawnd1/features/generalhome/all_activity_page.dart';
import 'package:respawnd1/features/rescue/all_explore_page.dart';
import 'explore_reports_map.dart';
import 'nearby_report.dart';
import '../../app_theme.dart';
import '../rescue/rescue_page.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/core/widgets/welcome_greeting.dart';


/// The signed-in user's app shell: Home, Notifications and My Profile as
/// tabs under one bottom bar that stays put. Each tab is built the first
/// time it is opened and then kept alive in an IndexedStack, so switching
/// tabs is instant and keeps scroll position — the bar used to be rebuilt
/// (and slide in with a new route) on every page.
///
/// Task pages (Report a Rescue, Adoption, Donations, Events, ...) are
/// pushed on top of the shell without the bar, with a back button, so an
/// unfinished form can't be left by an accidental tab tap.
class HomeScreen extends StatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _index = widget.initialTab;
  late final Set<int> _opened = {widget.initialTab};

  static const _tabs = <Widget>[HomeTab(), NotificationsScreen(), UserProfile()];

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _opened.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from Notifications/Profile goes to Home before leaving the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _opened.contains(i) ? _tabs[i] : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: _select,
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
        ),
      ),
    );
  }
}

/// The Home tab's content.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: const WelcomeGreeting(exclaim: true),
        automaticallyImplyLeading: false,
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

                // Adoption gap 10: a Community Adoption check-in is due.
                const CommunityCheckInBanner(),

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
                        label: 'Donations &\nSponsorships',
                        color: AppColors.pinkrspwn,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => DonationPage(),
                          ),
                          );
                        },
                      ),
                      _QuickActionCard(
                        label: 'Events',
                        color: AppColors.lavenderrspwn,
                        onTap: (){
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => const VolunteerPage(),
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

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Sponsored Animals',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const SponsoredAnimalsSection(),

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
  const _QuickActionCard({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                  ]),
            ),
          ),
        ),
    );
  }
}