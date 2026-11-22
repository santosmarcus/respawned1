import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/utils/validators.dart';

/// Verifies a PH mobile number by SMS code and adds it to the signed-in
/// account (AuthService.addVerifiedPhone), so one number belongs to one
/// account and signing in with it opens this account. Returns the verified
/// number (+639XXXXXXXXX), or null if cancelled.
///
/// [initialLocal]: the 10 digits after +63 to start with. When
/// [sendImmediately] is true the code goes out as the sheet opens.
Future<String?> showPhoneVerificationSheet(
  BuildContext context, {
  String initialLocal = '',
  bool sendImmediately = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PhoneVerificationSheet(
      initialLocal: initialLocal,
      sendImmediately: sendImmediately,
    ),
  );
}

class _PhoneVerificationSheet extends StatefulWidget {
  final String initialLocal;
  final bool sendImmediately;

  const _PhoneVerificationSheet({required this.initialLocal, required this.sendImmediately});

  @override
  State<_PhoneVerificationSheet> createState() => _PhoneVerificationSheetState();
}

class _PhoneVerificationSheetState extends State<_PhoneVerificationSheet> {
  final _auth = authService.value;
  late final _phoneController = TextEditingController(text: widget.initialLocal);
  final _codeController = TextEditingController();

  String? _verificationId;
  bool _busy = false;
  String? _error;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  String get _number => '+63${_phoneController.text.trim()}';

  @override
  void initState() {
    super.initState();
    if (widget.sendImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendSeconds = _resendSeconds <= 1 ? 0 : _resendSeconds - 1);
      if (_resendSeconds == 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    final invalid = AppValidators.phLocalPhone(_phoneController.text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.sendPhoneCode(
        phoneNumber: _number,
        onCodeSent: (id) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _busy = false;
          });
          _startResendCooldown();
        },
        onError: (message) {
          if (mounted) {
            setState(() {
              _error = message;
              _busy = false;
            });
          }
        },
        // Android read the code itself.
        onAutoVerified: _add,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AuthService.phoneErrorMessage(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final id = _verificationId;
    final code = _codeController.text.trim();
    if (id == null) return;
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    FocusScope.of(context).unfocus();
    await _add(AuthService.phoneCredential(id, code));
  }

  Future<void> _add(PhoneAuthCredential credential) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final number = await _auth.addVerifiedPhone(credential);
      if (mounted) Navigator.pop(context, number.isEmpty ? _number : number);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AuthService.phoneErrorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final codeSent = _verificationId != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(codeSent ? 'Enter the code' : 'Verify your mobile number',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            codeSent
                ? 'We sent a 6-digit code to $_number.'
                : 'We\'ll text you a code. A number can only be used by one ResPAWnd account.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (!codeSent)
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                hintText: '9XXXXXXXXX',
                prefixText: '+63 ',
                prefixIcon: Icon(Icons.phone_outlined),
                counterText: '',
              ),
            )
          else
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 24, letterSpacing: 8, color: AppColors.textPrimary),
              decoration: const InputDecoration(counterText: '', hintText: '------'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : (codeSent ? _verifyCode : _sendCode),
            style: AppButtons.primary.copyWith(fixedSize: const WidgetStatePropertyAll(Size.fromHeight(50))),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textPrimary))
                : Text(codeSent ? 'Verify' : 'Send Code', style: Theme.of(context).textTheme.headlineLarge),
          ),
          if (codeSent) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _resendTimer?.cancel();
                          setState(() {
                            _verificationId = null;
                            _codeController.clear();
                            _error = null;
                            _resendSeconds = 0;
                          });
                        },
                  child: Text('Change number', style: GoogleFonts.zain(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: (_busy || _resendSeconds > 0) ? null : _sendCode,
                  child: Text(_resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend code',
                      style: GoogleFonts.zain(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
