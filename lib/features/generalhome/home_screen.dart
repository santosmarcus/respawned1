import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import '../../app_theme.dart';
import '../rescue/rescue_page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome, User!'),
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
          // TODO: navigation
        },
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Hero banner area
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(20),
              ),
              // Replace with Image.asset or a Lottie animation
            ),

            const SizedBox(height: 24),

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
                  ),
                  _QuickActionCard(
                    label: 'Volunteer',
                    color: AppColors.yellowrspwn,
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

            // Case card placeholder
            Card(
              color: AppColors.bgres,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Animal photo placeholder
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 30),
                    // Case details — fill in when you have real data
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#123ABCD',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('February 12, 2026 11:00 AM ',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text('123 A. B. Street, Pasay, Metro Manila 1234 ',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text('Status: Pending',
                              style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

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