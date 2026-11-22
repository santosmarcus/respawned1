import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';
import 'package:respawnd1/core/utils/user_autofill.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'volunteer_page.dart';
import 'volunteer_signup_success.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

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
  void initState() {
    super.initState();
    _prefill();
  }

  /// Fills in what the profile already has, so joining is one tap for most
  /// people; nothing they've typed is overwritten.
  Future<void> _prefill() async {
    final me = await UserAutofill.load();
    if (me == null || !mounted) return;
    setState(() {
      fillIfEmpty(_nameController, me.fullName);
      fillIfEmpty(_emailController, me.email);
      fillIfEmpty(_mobileController, me.phone);
    });
  }

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

    final problem = AppValidators.required(name, fieldName: 'Full name') ??
        AppValidators.email(email) ??
        AppValidators.phFlexiblePhone(mobile);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(problem, kind: AppMessageKind.error));
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
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Registration failed: $e', kind: AppMessageKind.error));
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(widget.event.title,
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('${widget.event.date} · ${widget.event.time}',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 24),

            _fieldLabel('Full Name'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _nameController,
                keyboardType: TextInputType.name),

            const SizedBox(height: 20),

            _fieldLabel('Email'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress),

            const SizedBox(height: 20),

            _fieldLabel('Mobile Number'),
            const SizedBox(height: 6),
            _buildTextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone),

          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignUp,
                style: AppButtons.primary,
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
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text,
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