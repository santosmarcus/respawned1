import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';
import 'volunteer_page.dart';
import 'volunteer_signup_success.dart';

class VolunteerSignUpPage extends StatefulWidget {
  final VolunteerEvent event;

  const VolunteerSignUpPage({
    super.key,
    required this.event,
  });

  @override
  State<VolunteerSignUpPage> createState() => _VolunteerSignUpPageState();
}

class _VolunteerSignUpPageState extends State<VolunteerSignUpPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String _generateParticipantNumber() {
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    final eventCode = widget.event.id.length > 6
        ? widget.event.id.substring(0, 6).toUpperCase()
        : widget.event.id.toUpperCase();
    return 'VOL-$eventCode-$ts';
  }

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final mobile = _mobileController.text.trim();

    if (name.isEmpty || email.isEmpty || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please fill in all fields.'),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    final participantNumber = _generateParticipantNumber();

    try {
      await VolunteerEventRepository().register(
        event: widget.event,
        participantName: name,
        participantEmail: email,
        participantMobileNumber: mobile,
        participantNumber: participantNumber,
      );
      widget.event.joined = true;
    } on EventRegistrationException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Registration failed: $e'),
          backgroundColor: Colors.redAccent));
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VolunteerSignUpSuccessPage(
          event: widget.event,
          participantName: name,
          participantEmail: email,
          participantMobileNumber: mobile,
          participantNumber: participantNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text('Event Sign Up',
            style: GoogleFonts.tiltWarp(
                fontSize: 20, color: AppColors.textPrimary)),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Notifications'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'My Profile'),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
          else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),

            _FieldLabel('Full Name'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _nameController,
                keyboardType: TextInputType.name),

            const SizedBox(height: 20),

            _FieldLabel('Email'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress),

            const SizedBox(height: 20),

            _FieldLabel('Mobile Number'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor:
                  AppColors.yellowrspwn.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Sign up',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _FieldLabel(String text) => Text(text,
      style: GoogleFonts.zain(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary));

  Widget _buildTextField({
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintStyle:
        GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
          const BorderSide(color: AppColors.textPrimary, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
          const BorderSide(color: AppColors.textPrimary, width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        isDense: true,
      ),
    );
  }
}