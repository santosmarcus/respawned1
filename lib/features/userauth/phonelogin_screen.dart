/*import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/theme/app_theme.dart';
import 'package:respawnd1/core/services/auth_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _otpController   = TextEditingController();

  bool _codeSent  = false;
  bool _isLoading = false;
  String? _verificationId;
  String? _errorMessage;

  Future<void> _sendOtp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    await _authService.sendOtp(
      phoneNumber: '+63${_phoneController.text.trim()}', // Philippine format
      onCodeSent: (verificationId) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _isLoading = false;
        });
      },
      onError: (error) {
        setState(() { _errorMessage = error; _isLoading = false; });
      },
    );
  }

  Future<void> _verifyOtp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _authService.verifyOtp(
        verificationId: _verificationId!,
        otp: _otpController.text.trim(),
      );
      // AuthWrapper handles navigation
    } catch (e) {
      setState(() {
        _errorMessage = 'Invalid OTP. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Sign In')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              Text('Enter your phone number',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text('We\'ll send a verification code to your number',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),

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
                  decoration: const InputDecoration(
                    hintText: 'Enter 6-digit OTP',
                    prefixIcon: Icon(Icons.lock_outline),
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
                    : _codeSent ? _verifyOtp : _sendOtp,
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
                    : Text(_codeSent ? 'Verify OTP' : 'Send OTP',
                    style: Theme.of(context).textTheme.headlineLarge),
              ),

              if (_codeSent) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  child: Text('Resend OTP',
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
}*/