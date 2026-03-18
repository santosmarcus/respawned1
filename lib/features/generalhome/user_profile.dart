import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';

class UserProfile extends StatefulWidget {
  const UserProfile({super.key});

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
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
          if (index == 0) {
            Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          }
        }
        ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            Center(
              child: Column(
                children: [
                  const SizedBox(height: 35),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(color: AppColors.slaterspwn, shape: BoxShape.circle,),
                    child: const Icon(Icons.person, size: 44, color: AppColors.textSecondary,),
                  ),
                  const SizedBox(height: 10),
                  Text('User Name', //to be changed
                  style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary,),
                  ),
                  const SizedBox(height: 2,),
                  Text('+63 982320384', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary,),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  _ProfileTile(
                    icon: Icons.favorite_border,
                    label: 'Favorites',
                    onTap: (){},
                  ),
                  _ProfileTile(
                    icon: Icons.history,
                    label: 'History',
                    onTap: (){},
                  ),
                  _ProfileTile(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Certificates',
                    onTap: (){},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(label: 'Settings'),
                      _SectionLabel(label: 'My Account'),
                      _ProfileTile(
                        label: 'Edit account',
                        onTap: () {},
                      ),
                      _ProfileTile(
                        label: 'Payment methods',
                        onTap: () {},
                      ),
                      const SizedBox(height: 10),
                      _SectionLabel(label: 'Privacy'),
                      _ProfileTile(
                        label: 'Location Sharing',
                        onTap: () {},
                      ),
                      _ProfileTile(
                        label: 'Communications',
                        onTap: () {},
                      ),
                    ],
                  ),
            ),

            const SizedBox(height: 32),

            Center(
              child: TextButton(
                  onPressed: () {},//TODO:
                  child: Text('Log Out', style: GoogleFonts.zain(fontSize: 20, color: Colors.redAccent,
                  ),
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

class _SectionLabel extends StatelessWidget{
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

/*class _SubSectionLabel extends StatelessWidget{
  final String label;
  const _SubSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: TextButton(onPressed: onPressed, child: child),
    )
  }
}*/

class _ProfileTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileTile({
    this.icon,
    required this.label,
    required this.onTap,
});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.slaterspwn, width: 1),
          ),
        ),
        child: Row(
          children: [
            if(icon != null) ...[
              Icon(icon, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 12),
            ],
            Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary,),
                ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}