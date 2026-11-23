import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// "Add password" for accounts that sign in with Google or a mobile number
/// (links an email-and-password sign-in using [email], the address already
/// on the account), or "Change password" when [hasPassword]. Returns true
/// when the password was saved.
Future<bool> showPasswordDialog(
  BuildContext context, {
  required bool hasPassword,
  required String email,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PasswordDialog(hasPassword: hasPassword, email: email),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(hasPassword
        ? 'Password changed.'
        : 'Password added. You can now log in with $email and your password.'));
  }
  return saved == true;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.hasPassword, required this.email});

  final bool hasPassword;
  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _password.text;
    final problem = (widget.hasPassword && _current.text.isEmpty)
        ? 'Enter your current password.'
        : AppValidators.password(password) ??
            (password != _confirm.text ? 'The passwords don\'t match.' : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.hasPassword) {
        await AuthService().changePassword(currentPassword: _current.text, newPassword: password);
      } else {
        await AuthService().setPassword(email: widget.email, password: password);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AuthService.passwordErrorMessage(e);
        });
      }
    }
  }

  Widget _field(TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          obscureText: _obscure,
          enabled: !_busy,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.hasPassword ? 'Change password' : 'Add a password',
          style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.hasPassword)
              Text(
                'You\'ll be able to log in with your email and this password, '
                'as well as the way you sign in now.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              ),
            const SizedBox(height: 6),
            Text('Email: ${widget.email}',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (widget.hasPassword) _field(_current, 'Current password'),
            _field(_password, 'New password (at least 8 characters)'),
            _field(_confirm, 'Confirm new password'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                label: Text(_obscure ? 'Show passwords' : 'Hide passwords'),
              ),
            ),
            if (_error != null)
              Text(_error!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          style: AppButtons.primary,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.hasPassword ? 'Change' : 'Add password'),
        ),
      ],
    );
  }
}
