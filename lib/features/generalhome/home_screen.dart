import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/donation/donation_page.dart';
import 'package:respawnd1/features/volunteerevent/volunteer_page.dart';
import 'package:respawnd1/features/generalhome/activity_feed.dart';
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
                        builder: (context) => VolunteerPage(),
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

            const SizedBox(height: 24),
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
              fontSize: 14,
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