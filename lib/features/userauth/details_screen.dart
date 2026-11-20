import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/userauth/onboard_screen.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/phone_verification_sheet.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/userauth/verify_email_screen.dart';

class EnterDetailsScreen extends StatefulWidget {
  //final String role;
  const EnterDetailsScreen({super.key});

  @override
  State<EnterDetailsScreen> createState() => _EnterDetailsScreenState();
}

class _EnterDetailsScreenState extends State<EnterDetailsScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _phoneController     = TextEditingController();
  final _emailController     = TextEditingController();
  final _passwordController  = TextEditingController();

  // ── TEMPLATE: Add extra fields here ──────────────────────────
  // final _addressController   = TextEditingController();
  // final _birthdateController = TextEditingController();
  // String? _selectedGender;
  // ─────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _errorMessage;
  bool _noticeOpen = false;
  bool _obscurePassword = true;

  /// Signed up with this number (phone sign-in): it's already verified on
  /// the account, so the field is fixed.
  bool _phoneFromSignIn = false;

  /// Phone sign-up with no email yet: asks for an email and password so the
  /// account can also sign in by email (and the email is this account's).
  bool _askEmail = false;

  @override
  void initState() {
    super.initState();
    final signedInPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    if (RegExp(r'^\+639\d{9}$').hasMatch(signedInPhone)) {
      _phoneController.text = signedInPhone.substring(3);
      _phoneFromSignIn = true;
    }
    final providers = FirebaseAuth.instance.currentUser?.providerData.map((p) => p.providerId).toSet() ?? {};
    _askEmail = _phoneFromSignIn && !providers.contains('google.com') &&
        (!providers.contains('password') || !(FirebaseAuth.instance.currentUser?.emailVerified ?? false));
    if (_askEmail) _emailController.text = FirebaseAuth.instance.currentUser?.email ?? '';
    AuthService.noAccountNotice.addListener(_maybeShowNoAccount);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowNoAccount());
  }

  /// Google sign-in from the login screen found no account: say so, then
  /// this screen is where one gets created (or log out to switch account).
  Future<void> _maybeShowNoAccount() async {
    final email = AuthService.noAccountNotice.value;
    if (email == null || _noticeOpen || !mounted) return;
    _noticeOpen = true;
    AuthService.noAccountNotice.value = null;
    final create = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('No account yet'),
        content: Text("There's no ResPAWnd account for $email yet. "
            'Fill in your details to create one, or log out to sign in with a different account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Log out')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create account')),
        ],
      ),
    );
    _noticeOpen = false;
    if (create == false) await authService.value.signOut();
  }

  @override
  void dispose() {
    AuthService.noAccountNotice.removeListener(_maybeShowNoAccount);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    // _addressController.dispose();
    // _birthdateController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    setState(() => _errorMessage = null);

    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    final phoneError = AppValidators.phLocalPhone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }

    if (_askEmail) {
      final emailError = AppValidators.email(_emailController.text.trim()) ??
          AppValidators.password(_passwordController.text);
      if (emailError != null) {
        setState(() => _errorMessage = emailError);
        return;
      }
    }

    // One number, one account: the number must be verified by SMS and added
    // to this account (it fails if another account already has it).
    var phone = '+63${_phoneController.text.trim()}';
    if (FirebaseAuth.instance.currentUser?.phoneNumber != phone) {
      final verified = await showPhoneVerificationSheet(
        context,
        initialLocal: _phoneController.text.trim(),
        sendImmediately: true,
      );
      if (verified == null || !mounted) return;
      phone = verified;
      _phoneController.text = phone.startsWith('+63') ? phone.substring(3) : phone;
    }
    if (!mounted) return;

    // Phone sign-ups add an email and password, confirmed by link before
    // going on (the same check email sign-ups get).
    if (_askEmail && !await _addEmail()) return;
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingRoleScreen(
          firstName: _firstNameController.text.trim(),
          lastName:  _lastNameController.text.trim(),
          phone:     phone,
          // pass extra fields here when added:
          // address: _addressController.text.trim(),
        ),
      ),
    );
  }

  /// Adds the email and password to this account, then waits for the
  /// address to be confirmed. False when it failed or was left unconfirmed.
  Future<bool> _addEmail() async {
    setState(() => _isLoading = true);
    try {
      await authService.value.addEmailSignIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthService.emailErrorMessage(e);
          _isLoading = false;
        });
      }
      return false;
    }
    if (!mounted) return false;
    setState(() => _isLoading = false);
    if (FirebaseAuth.instance.currentUser?.emailVerified ?? false) return true;
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => VerifyEmailScreen(onVerified: () => Navigator.pop(ctx, true)),
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Details'),
        actions: [
          // Root screen with no Back: lets the user return to login.
          TextButton(
            onPressed: () => authService.value.signOut(),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              Text('Tell us about\nyourself',
                  style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 8),
              Text('This helps us personalize your experience.',
                  style: Theme.of(context).textTheme.bodyMedium),

              const SizedBox(height: 32),

              // First name
              _DetailField(
                controller: _firstNameController,
                hint: 'First Name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 16),

              // Last name
              _DetailField(
                controller: _lastNameController,
                hint: 'Last Name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 16),

              // Phone number
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.greenrspwn,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text('+63',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      readOnly: _phoneFromSignIn,
                      decoration: InputDecoration(
                        hintText: '9XXXXXXXXX',
                        counterText: '',
                        suffixIcon: _phoneFromSignIn
                            ? const Tooltip(message: 'Verified', child: Icon(Icons.verified_outlined))
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (!_phoneFromSignIn) ...[
                const SizedBox(height: 6),
                Text("We'll text a code to confirm it. One number can only be used by one account.",
                    style: Theme.of(context).textTheme.bodySmall),
              ],

              if (_askEmail) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text("Lets you sign in with your email too. We'll send a link to confirm it. "
                    'One email can only be used by one account.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],

              // ── TEMPLATE: Extra fields ──────────────────────────────
              // Uncomment and add as needed:
              //
              // const SizedBox(height: 16),
              //
              // Address field:
              // _DetailField(
              //   controller: _addressController,
              //   hint: 'Home Address',
              //   icon: Icons.home_outlined,
              // ),
              //
              // Birthdate picker:
              // const SizedBox(height: 16),
              // GestureDetector(
              //   onTap: () async {
              //     final picked = await showDatePicker(
              //       context: context,
              //       initialDate: DateTime(2000),
              //       firstDate: DateTime(1900),
              //       lastDate: DateTime.now(),
              //     );
              //     if (picked != null) {
              //       _birthdateController.text =
              //           '${picked.day}/${picked.month}/${picked.year}';
              //     }
              //   },
              //   child: AbsorbPointer(
              //     child: _DetailField(
              //       controller: _birthdateController,
              //       hint: 'Date of Birth',
              //       icon: Icons.calendar_today_outlined,
              //     ),
              //   ),
              // ),
              //
              // Gender dropdown:
              // const SizedBox(height: 16),
              // DropdownButtonFormField<String>(
              //   value: _selectedGender,
              //   decoration: const InputDecoration(
              //     hintText: 'Gender',
              //     prefixIcon: Icon(Icons.wc_outlined),
              //   ),
              //   items: ['Male', 'Female', 'Prefer not to say']
              //       .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              //       .toList(),
              //   onChanged: (val) => setState(() => _selectedGender = val),
              // ),
              // ───────────────────────────────────────────────────────

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                AppErrorBanner(_errorMessage!),
              ],

              const SizedBox(height: 40),

              Center(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleNext,
                  style: AppButtons.primary.copyWith(fixedSize: WidgetStatePropertyAll(Size(MediaQuery.of(context).size.width * 0.55, 50))),
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

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// Reusable field widget for this screen
class _DetailField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _DetailField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}