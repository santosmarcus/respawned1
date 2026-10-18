/*import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';

class SelectUserTypeScreen extends StatefulWidget {
  const SelectUserTypeScreen({super.key});

  @override
  State<SelectUserTypeScreen> createState() => _SelectUserTypeScreenState();
}

class _SelectUserTypeScreenState extends State<SelectUserTypeScreen> {
  String? _selectedRole;

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
      'Registered responder who can take on rescue cases when partner organizations are unavailable. Provide basic care and needs to rescue cases and ensure they are not left unattended.',
      color: AppColors.greenrspwn,
    ),
  ];

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

              // Role cards
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
                                  Text(
                                    option.title,
                                    style: GoogleFonts.tiltWarp(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    option.description,
                                    style: GoogleFonts.zain(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check_circle,
                                    color: AppColors.textPrimary, size: 22),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Next button
              Center(
                child: ElevatedButton(
                  onPressed: _selectedRole == null
                      ? null
                      : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EnterNameScreen(role: _selectedRole!),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.55, 50),
                    disabledBackgroundColor: AppColors.slaterspwn,
                  ),
                  child: Text('Next',
                      style: Theme.of(context).textTheme.headlineLarge),
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
}*/