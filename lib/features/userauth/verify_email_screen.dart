import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';

/// Shown by AuthWrapper while an email/password account hasn't confirmed its
/// address (AuthService.needsEmailVerification). Checks on its own every few
/// seconds so the user doesn't have to come back and tap anything after
/// opening the link; [onVerified] lets the router rebuild into the app.
class VerifyEmailScreen extends StatefulWidget {
  final VoidCallback onVerified;
  const VerifyEmailScreen({super.key, required this.onVerified});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  final _authService = AuthService();
  Timer? _poll;
  Timer? _cooldownTicker;
  int _cooldownLeft = 0;
  bool _checking = false;
  bool _sending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    if (!silent) setState(() { _checking = true; _message = null; });
    try {
      final verified = await _authService.reloadAndCheckVerified();
      if (!mounted) return;
      if (verified) {
        _poll?.cancel();
        widget.onVerified();
      } else if (!silent) {
        setState(() => _message = "We haven't seen the confirmation yet. Open the link in the email, then try again.");
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _message = 'Could not check right now. Please try again.');
    } finally {
      if (mounted && !silent) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _sending = true; _message = null; });
    try {
      await _authService.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _message = 'Verification email sent. Check your inbox and spam folder.';
        _cooldownLeft = _resendCooldown.inSeconds;
      });
      _cooldownTicker?.cancel();
      _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _cooldownLeft--);
        if (_cooldownLeft <= 0) t.cancel();
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'too-many-requests'
            ? 'Too many requests. Please wait a few minutes before resending.'
            : 'Could not send the email. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 64, color: AppColors.textPrimary),
              const SizedBox(height: 16),
              Text('Verify your email', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'We sent a confirmation link to $email. Open it to finish setting up your account.',
                style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!,
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _checking ? null : () => _check(),
                  style: AppButtons.primary,
                  child: _checking
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textPrimary))
                      : Text("I've verified my email", style: Theme.of(context).textTheme.headlineLarge),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _sending || _cooldownLeft > 0 ? null : _resend,
                child: Text(
                  _cooldownLeft > 0 ? 'Resend email ($_cooldownLeft s)' : 'Resend email',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () => _authService.signOut(),
                child: Text('Use a different account',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
