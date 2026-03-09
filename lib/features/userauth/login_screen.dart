import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/home/home_screen.dart';
import 'package:respawnd1/features/userauth/signup_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService        = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Login logic
  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields.';
        _isLoading = false;
      });
      return;
    }

    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // Success — AuthWrapper handles navigation, don't setState here

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':        // ← new Firebase error code
        case 'INVALID_LOGIN_CREDENTIALS': // ← another variant
          message = 'Incorrect email or password.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        default:
          message = 'Login failed (${e.code})'; // show code so you can debug
      }
      // Only setState on error
      if (mounted) {
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      }

    } catch (e) {
      // Catch any non-Firebase errors
      if (mounted) {
        setState(() {
          _errorMessage = 'Unexpected error: $e';
          _isLoading = false;
        });
      }
    }
    // ← NO finally block — it was causing setState after successful login
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ResPAWnd')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Logo placeholder
              Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  color: AppColors.slaterspwn,
                  shape: BoxShape.circle,
                ),
                // Replace with your actual logo:
                // child: Image.asset('assets/images/logo.png'),
              ),

              const SizedBox(height: 48),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Enter Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 16),

              // Password field
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

              const SizedBox(height: 8),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Login button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  fixedSize: Size(MediaQuery.of(context).size.width * 0.60, 50),
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
                    : Text('Login', style: Theme.of(context).textTheme.headlineLarge),
              ),

              // Sign up link
              RichText(
                text: TextSpan(
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textSecondary),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    TextSpan(
                      text: 'Sign up',
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SignUpScreen()),
                          );
                        },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.textSecondary)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  const Expanded(child: Divider(color: AppColors.textSecondary)),
                ],
              ),

              const SizedBox(height: 16),

// Google button
              _SocialButton(
                label: 'Continue with Google',
                icon: 'assets/icons/Google__G__logo.svg', // add a google icon to assets
                onTap: () async {
                  try {
                    await _authService.signInWithGoogle();
                    // AuthWrapper handles navigation automatically
                  } catch (e) {
                    setState(() => _errorMessage = 'Google sign-in failed.');
                  }
                },
              ),

              const SizedBox(height: 12),

// Facebook button
              /*_SocialButton(
                label: 'Continue with Facebook',
                icon: 'assets/icons/facebook.png',
                onTap: () async {
                  try {
                    await _authService.signInWithFacebook();
                  } catch (e) {
                    setState(() => _errorMessage = 'Facebook sign-in failed.');
                  }
                },
              ),

              const SizedBox(height: 12),*/

// Phone button — uncomment when PhoneLoginScreen is ready
// _SocialButton(
//   label: 'Continue with Phone',
//   iconData: Icons.phone_outlined,
//   onTap: () {
//     Navigator.push(context,
//       MaterialPageRoute(builder: (_) => const PhoneLoginScreen()));
//   },
// ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final String? icon;
  //final IconData? iconData;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.onTap,
    this.icon,
    //this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        //fixedSize: Size(MediaQuery.of(context).size.width * 0.85, 50),
        fixedSize: const Size(double.infinity, 50),
        side: const BorderSide(color: AppColors.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        backgroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null)
            Image.asset(icon!, width: 22, height: 22),
          //else if (iconData != null)
            //Icon(iconData, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
