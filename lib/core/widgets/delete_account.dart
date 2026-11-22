import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/services/known_accounts.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/main.dart' show AuthWrapper, appNavigatorKey;

/// "Delete account": confirms (typing DELETE), then the deleteMyAccount
/// callable removes the profile from Firestore and the Firebase Auth
/// account. Rescue reports the user filed stay, without their name.
Future<void> showDeleteAccountFlow(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call<Object?>({'confirm': 'DELETE'});
    if (uid != null) await KnownAccounts.forget(uid);
    // The Auth account is gone server-side; clear the local session.
    try {
      await AuthService().signOut();
    } catch (_) {}
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
    final messenger = appNavigatorKey.currentContext == null
        ? null
        : ScaffoldMessenger.maybeOf(appNavigatorKey.currentContext!);
    messenger?.showSnackBar(appSnackBar('Your account was deleted.'));
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // progress
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(e.message ?? 'Could not delete your account.', kind: AppMessageKind.error),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Could not delete your account: $e', kind: AppMessageKind.error),
      );
    }
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _controller.text.trim() == 'DELETE';
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Delete your account?', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes your login and your profile, and removes you from your organization. '
            'It can\'t be undone.\n\n'
            'Rescue reports you filed stay so the animals\' records are complete, but your name is removed from them.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Text('Type DELETE to confirm', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
