import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/home/home_screen.dart';

class OnboardingRoleScreen extends StatefulWidget {
  const OnboardingRoleScreen({super.key});

  @override
  State<OnboardingRoleScreen> createState() => _OnboardingRoleScreenState();
}

class _OnboardingRoleScreenState extends State<OnboardingRoleScreen> {
  String? _selectedRole;
  bool _isLoading = false;

  final List<_RoleOption> _roles = [
    _RoleOption(
      role: 'general',
      title: 'General Public',
      description: 'Report strays, browse adoptions, donate',
      icon: Icons.people_outline,
      color: AppColors.lavenderrspwn,
    ),
    _RoleOption(
      role: 'volunteer',
      title: 'Volunteer',
      description: 'Help rescue animals and join events',
      icon: Icons.volunteer_activism_outlined,
      color: AppColors.pinkrspwn,
    ),
    _RoleOption(
      role: 'ngo_staff',
      title: 'NGO Staff',
      description: 'Manage rescues, animals, and adoptions',
      icon: Icons.business_outlined,
      color: AppColors.yellowrspwn,
    ),
  ];

  Future<void> _saveRole() async {
    if (_selectedRole == null) return;

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'role': _selectedRole}, SetOptions(merge: true));

      // AuthWrapper will detect role is now set and navigate to HomeScreen
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      print('Error saving role: $e'); // ← add this so you can see errors
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to ResPAWnd')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              Text(
                'How will you\nuse the app?',
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your role to get the right experience.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              const SizedBox(height: 32),

              // Role selection cards
              Expanded(
                child: ListView.separated(
                  itemCount: _roles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = _roles[index];
                    final isSelected = _selectedRole == option.role;

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedRole = option.role),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? option.color
                              : AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.textPrimary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(option.icon,
                                  color: AppColors.textPrimary, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.title,
                                    style: GoogleFonts.tiltWarp(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.description,
                                    style: GoogleFonts.zain(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle,
                                  color: AppColors.textPrimary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Continue button
              ElevatedButton(
                onPressed: _selectedRole == null || _isLoading
                    ? null
                    : _saveRole,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  fixedSize:
                  Size(MediaQuery.of(context).size.width * 0.85, 50),
                  disabledBackgroundColor:
                  AppColors.slaterspwn,
                ),
                child: _isLoading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.textPrimary,
                  ),
                )
                    : Text(
                  'Continue',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleOption {
  final String role;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _RoleOption({
    required this.role,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
