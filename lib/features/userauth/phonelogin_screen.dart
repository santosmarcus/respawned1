import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  String? _verificationId;
  String? _errorMessage;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    final rawNumber = _phoneController.text.trim();
    if (rawNumber.isEmpty) {
      setState(() => _errorMessage = 'Please enter your mobile number.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendOtp(
        phoneNumber: '+63$rawNumber', // Philippine format
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _isLoading = false;
          });
          _startResendCooldown();
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _errorMessage = error;
            _isLoading = false;
          });
        },
        onAutoVerified: (_) {
          // Some Android devices auto-verify without the user typing an OTP.
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not send the code. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null) return;
    if (_otpController.text.trim().length < 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.verifyOtp(
        verificationId: _verificationId!,
        otp: _otpController.text.trim(),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid code. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              Text(
                _codeSent ? 'Enter the code' : 'Enter your phone number',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'We sent a 6-digit code to +63${_phoneController.text.trim()}'
                    : 'We\'ll send a verification code to your number',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Phone field
              if (!_codeSent)
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '9XXXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+63 ',
                  ),
                ),

              // OTP field
              if (_codeSent)
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 24, letterSpacing: 8, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '------',
                  ),
                ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!,
                    style: GoogleFonts.zain(
                        fontSize: 13, color: Colors.red.shade700)),
              ],

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _codeSent
                    ? _verifyOtp
                    : _sendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  fixedSize: Size(MediaQuery.of(context).size.width * 0.60, 50),
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.textPrimary))
                    : Text(_codeSent ? 'Verify Code' : 'Send Code',
                    style: Theme.of(context).textTheme.headlineLarge),
              ),

              if (_codeSent) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: (_isLoading || _resendSeconds > 0) ? null : _sendOtp,
                  child: Text(
                    _resendSeconds > 0
                        ? 'Resend code in ${_resendSeconds}s'
                        : 'Resend code',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                    setState(() {
                      _codeSent = false;
                      _verificationId = null;
                      _otpController.clear();
                      _errorMessage = null;
                    });
                    _resendTimer?.cancel();
                  },
                  child: Text('Use a different number',
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}