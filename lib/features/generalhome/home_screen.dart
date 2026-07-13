import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';
import 'package:respawnd1/features/donation/donation_page.dart';
import 'package:respawnd1/features/volunteerevent/volunteer_page.dart';
import 'package:respawnd1/features/organization/organization_list_page.dart';
import 'package:respawnd1/features/generalhome/activity_feed.dart';
import 'package:respawnd1/features/rescue/public_rescue_feed.dart';
import 'package:respawnd1/features/rescue/all_explore_page.dart';
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
            Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const UserProfile()),
            );
          }
        },
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Quick action cards
            SizedBox(
              height: 140,
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
                  _QuickActionCard(
                    label: 'Organization',
                    color: AppColors.lavenderrspwn,
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
              child: Text(
                'Activity',
                style: GoogleFonts.tiltWarp(fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 20),

            ActivityFeed(),

            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Explore Reports',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AllExploreReportsPage(),
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

            const PublicRescueFeed(previewCount: 3),

            const _PossibleMatchesSection(),

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
    );
  }
}

class _PossibleMatchesSection extends StatelessWidget {
  const _PossibleMatchesSection();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('possibleMatches')
          .where(
        Filter.or(
          Filter('lostReporterId', isEqualTo: uid),
          Filter('foundReporterId', isEqualTo: uid),
        ),
      )
          .where('status', whereIn: ['pending_review', 'approved'])
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Possible Matches',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _PossibleMatchCard(
                  matchId: docs[i].id,
                  data: docs[i].data(),
                  currentUid: uid,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PossibleMatchCard extends StatelessWidget {
  final String matchId;
  final Map<String, dynamic> data;
  final String currentUid;

  const _PossibleMatchCard({
    required this.matchId,
    required this.data,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending_review';
    final isApproved = status == 'approved';
    final label = isApproved
        ? 'Verified match — tap to view'
        : 'Possible match — awaiting org verification';

    return GestureDetector(
      onTap: () => isApproved ? _showVerifiedMatch(context) : null,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isApproved
              ? AppColors.greenrspwn.withOpacity(0.18)
              : AppColors.tearspwn.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.pets, color: AppColors.textPrimary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (data['species'] as String?) ?? 'Animal',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVerifiedMatch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Match verified',
                style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Our team confirmed this match. You can now reach out to coordinate '
                  'the handover.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: Text('Got it', style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable quick action card widget
class _QuickActionCard extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionCard({required this.label, required this.color, this.onTap,
  });

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