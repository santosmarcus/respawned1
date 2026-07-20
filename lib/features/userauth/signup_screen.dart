import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';
import 'package:respawnd1/features/userauth/login_screen.dart';
import 'package:respawnd1/features/userauth/phonelogin_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  //final _nameController     = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService        = AuthService();

  bool _obscurePassword = true;
  bool _isLoading       = false;
  String? _errorMessage;

  @override
  void dispose() {
    //_nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    setState(() { _errorMessage = null; _isLoading = true; });

    if (/*_nameController.text.trim().isEmpty ||*/
    _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields.';
        _isLoading = false;
      });
      return;
    }

    if (_passwordController.text.trim().length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters long.';
        _isLoading = false;
      });
      return;
    }

    try {
      await _authService.createAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        //name: _nameController.text.trim(),
      );

      if (mounted) {
        // Go to user type selection after account created
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EnterDetailsScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // This can happen if an earlier attempt created the Auth account
        // but something after it (e.g. a Firestore write) failed, or the
        // person tapped Sign Up twice. Instead of dead-ending, try signing
        // them into the account that already exists with these credentials.
        try {
          await _authService.signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const EnterDetailsScreen()),
            );
          }
          return;
        } catch (_) {
          // Wrong password, or it's genuinely someone else's account.
          if (mounted) {
            setState(() {
              _errorMessage = 'An account already exists with this email.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      setState(() {
        switch (e.code) {
          case 'invalid-email':
            _errorMessage = 'Please enter a valid email address.';
            break;
          case 'weak-password':
            _errorMessage = 'Password is too weak.';
            break;
          default:
            _errorMessage = 'Sign up failed. Please try again.';
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Something went wrong creating your profile. '
              'Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await _authService.signInWithGoogle();
      if (result?.user != null && mounted) {
        await _routeAfterSocialSignIn(result!.user!.uid);
      } else if (mounted) {
        setState(() => _isLoading = false); // user cancelled the picker
      }
    } catch (e) {
      // Was a generic "Google sign-in failed." with no detail — on an
      // emulator this is almost always PlatformException(sign_in_failed,
      // ..., 10, ...) = DEVELOPER_ERROR (debug SHA-1 not registered with
      // the Firebase/OAuth client) or missing Google Play Services on the
      // emulator image. Surfacing the real message makes that diagnosable.
      if (mounted) {
        setState(() {
          _errorMessage = 'Google sign-in failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleFacebookSignUp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await _authService.signInWithFacebook();
      if (result?.user != null && mounted) {
        await _routeAfterSocialSignIn(result!.user!.uid);
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Facebook sign-in failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Both social sign-in paths used to unconditionally push EnterDetailsScreen
  // — including for a returning user who already finished onboarding (e.g.
  // they tapped "Sign Up" instead of "Log In", or re-authenticated). That
  // forced them back through the whole details+role flow every time.
  //
  // Note: AuthService._createUserDoc gives every new social sign-in
  // `role: 'general'` immediately, so AuthService.isNewUser (which checks
  // for an EMPTY role) is always false here and can't be used to detect
  // "first time" for Google/Facebook — only for the email/password path,
  // which explicitly starts with role: ''. `firstName` is never set by
  // _createUserDoc, so its absence is the real "still needs the details
  // form" signal for social sign-in.
  Future<void> _routeAfterSocialSignIn(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final firstName = (doc.data()?['firstName'] as String?)?.trim() ?? '';
    if (!mounted) return;
    if (firstName.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EnterDetailsScreen()),
      );
    } else {
      // Already onboarded — let AuthWrapper (main.dart) route based on
      // their existing role instead of re-forcing onboarding.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              Text('Create Account',
                  style: Theme.of(context).textTheme.displayLarge),

              const SizedBox(height: 32),

              // Full name
              /*TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Enter Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),*/

              //const SizedBox(height: 16),

              // Email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Enter Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Enter Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Password must be at least 8 characters long',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // OR divider
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.textSecondary)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR',
                        style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                  ),
                  const Expanded(child: Divider(color: AppColors.textSecondary)),
                ],
              ),

              const SizedBox(height: 16),

              // Social / phone sign up
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _isLoading ? null : _handleGoogleSignUp,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.textSecondary),
                        ),
                        child: const Center(
                          // Replace with Image.asset('assets/icons/google.png')
                          child: Text('G',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _isLoading ? null : _handleFacebookSignUp,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.textSecondary),
                        ),
                        child: const Center(
                          child: Icon(Icons.facebook,
                              size: 26, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PhoneLoginScreen()),
                        );
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.textSecondary),
                        ),
                        child: const Center(
                          child: Icon(Icons.phone_outlined,
                              size: 22, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Sign up button
              Center(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.60, 50),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.textPrimary))
                      : Text('Sign Up',
                      style: Theme.of(context).textTheme.headlineLarge),
                ),
              ),

              const SizedBox(height: 16),

              // Log in link
              Center(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textSecondary),
                    children: [
                      const TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Log in',
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                          ),
                      ),
                    ],
                  ),
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