
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/pettransporter/transporter_verification_screen.dart';

class OnboardingRoleScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String phone;
  // final String? address;

  const OnboardingRoleScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.phone,
    // this.address,
  });

  @override
  State<OnboardingRoleScreen> createState() => _OnboardingRoleScreenState();
}

class _OnboardingRoleScreenState extends State<OnboardingRoleScreen> {
  String? _selectedRole;
  bool _isLoading = false;

  final List<_UserTypeOption> _options = [
    _UserTypeOption(
      role: 'general',
      title: 'General User',
      description:
      'Report rescue cases, adopt animals, volunteer in events, donate or sponsor',
      color: AppColors.lavenderrspwn,
    ),
    _UserTypeOption(
      role: 'pet_transporter',
      title: 'Pet Transporter',
      description:
      'Safe transports of rescued animals to shelters or clinics, provides progress updates, and ensures comfort during travel.',
      color: AppColors.pinkrspwn,
    ),
    _UserTypeOption(
      role: 'rescue_volunteer',
      title: 'Rescue Volunteer',
      description:
      'Registered responder who can take on rescue cases when partner organizations are unavailable.',
      color: AppColors.greenrspwn,
    ),
  ];

  Future<void> _handleNext() async {
    if (_selectedRole == null) return;
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final fullName = '${widget.firstName} ${widget.lastName}';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'uid': uid,
        'firstName': widget.firstName,
        'lastName': widget.lastName,
        'name': fullName,
        'phone': widget.phone,
        'role': _selectedRole,
        // 'address': widget.address ?? '',
        'isVerified': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Widget nextPage;

        if(_selectedRole == 'general'){
          nextPage = const HomeScreen();
        } else if (_selectedRole == 'pet_transporter'){
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransporterVerificationScreen(
                firstName: widget.firstName,
                lastName: widget.lastName,
                phone: widget.phone,
              ),
            ),
          );
          return;
        } else {
          nextPage = const HomeScreen();
        }
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => nextPage),
              (route) => false,
        );
      }
    } catch (e) {
      print('Error saving user details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select User Type')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              Text('Select user\ntype',
                  style: Theme.of(context).textTheme.displayLarge),

              const SizedBox(height: 24),

              Expanded(
                child: ListView.separated(
                  itemCount: _options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = _options[index];
                    final isSelected = _selectedRole == option.role;

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedRole = option.role),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 140,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: option.color,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.textPrimary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(option.title,
                                      style: GoogleFonts.tiltWarp(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      )),
                                  const SizedBox(height: 6),
                                  Text(option.description,
                                      style: GoogleFonts.zain(
                                        fontSize: 13,
                                        color: AppColors.textPrimary
                                            .withValues(alpha: 0.75),
                                      )),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check_circle,
                                    color: AppColors.textPrimary,
                                    size: 22),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              Center(
                child: ElevatedButton(
                  onPressed: _selectedRole == null || _isLoading
                      ? null
                      : _handleNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.55, 50),
                    disabledBackgroundColor: AppColors.slaterspwn,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.textPrimary))
                      : Text('Next',
                      style:
                      Theme.of(context).textTheme.headlineLarge),
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

class _UserTypeOption {
  final String role;
  final String title;
  final String description;
  final Color color;

  const _UserTypeOption({
    required this.role,
    required this.title,
    required this.description,
    required this.color,
  });
}