import 'dart:io';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/utils/validators.dart';


class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _picker = ImagePicker();

  final _displayNameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  String _email = '';
  String _mobile = '';
  String? _photoUrl;
  File? _pickedPhoto;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (user == null || uid == null) return;
      // Picks up an email change confirmed through the link since the last
      // visit (emailVerified/email only refresh after a reload).
      await user.reload().catchError((_) {});
      final authEmail = FirebaseAuth.instance.currentUser?.email;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await docRef.get();
      final data = doc.data() ?? {};
      if (authEmail != null && authEmail.isNotEmpty && data['email'] != authEmail) {
        await docRef.set({'email': authEmail}, SetOptions(merge: true));
        data['email'] = authEmail;
      }
      setState(() {
        _displayNameCtrl.text = data['displayName'] as String? ??
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        _locationCtrl.text = data['locationText'] as String? ?? '';
        _email = data['email'] as String? ??
            FirebaseAuth.instance.currentUser?.email ??
            '';
        _mobile = data['phone'] as String? ?? '';
        _photoUrl = data['photoUrl'] as String?;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await pickImageWithSource(context, _picker);
    if (picked == null) return;
    setState(() => _pickedPhoto = File(picked.path));

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final ref =
      FirebaseStorage.instance.ref('users/$uid/profile.jpg');
      await ref.putFile(_pickedPhoto!);
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'photoUrl': url}, SetOptions(merge: true));
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not upload photo: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _updateField({
    required String title,
    required String currentValue,
    required TextInputType keyboardType,
    required Future<void> Function(String newValue) onConfirm,
  }) async {
    final ctrl = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(title,
            style: GoogleFonts.tiltWarp(
                fontSize: 16, color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          autofocus: true,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Update',
                style: GoogleFonts.zain(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == currentValue) return;
    await onConfirm(result);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.zain(color: AppColors.background)),
        backgroundColor: error ? Colors.redAccent : AppColors.textPrimary,
      ),
    );
  }

  /// The sign-in email lives in Firebase Auth, so a change goes through a
  /// confirmation link to the new address; users/{uid}.email is synced from
  /// Auth in [_load] once it's confirmed. Google accounts keep their Google
  /// address.
  Future<void> _updateEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.providerData.any((p) => p.providerId == 'google.com')) {
      _snack('This account signs in with Google, so its email is managed by Google.');
      return;
    }
    await _updateField(
      title: 'Update Email Address',
      currentValue: _email,
      keyboardType: TextInputType.emailAddress,
      onConfirm: (newValue) async {
        final error = AppValidators.email(newValue);
        if (error != null) {
          _snack(error, error: true);
          return;
        }
        await _sendEmailChange(newValue);
      },
    );
  }

  Future<void> _sendEmailChange(String newEmail, {bool reauthenticated = false}) async {
    try {
      await AuthService().requestEmailChange(newEmail);
      _snack('We sent a link to $newEmail. Your email changes once you open it.');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login' && !reauthenticated) {
        final ok = await _reauthenticate();
        if (ok) await _sendEmailChange(newEmail, reauthenticated: true);
        return;
      }
      _snack(
        switch (e.code) {
          'email-already-in-use' => 'Another account already uses that email.',
          'invalid-email' => 'Please enter a valid email address.',
          'requires-recent-login' => 'Please sign out and sign in again, then retry.',
          _ => 'Could not change your email. Please try again.',
        },
        error: true,
      );
    }
  }

  /// Asks for the current password when Firebase needs a fresh sign-in
  /// before a sensitive change. Returns false if cancelled or wrong.
  Future<bool> _reauthenticate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.providerData.any((p) => p.providerId == 'password')) {
      _snack('Please sign out and sign in again, then retry.', error: true);
      return false;
    }
    final ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Confirm your password',
            style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Current password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('Continue',
                style: GoogleFonts.zain(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (password == null || password.isEmpty) return false;
    try {
      await AuthService().reauthenticateWithPassword(password);
      return true;
    } on FirebaseAuthException {
      _snack('That password is incorrect.', error: true);
      return false;
    }
  }

  Future<void> _updateMobile() async {
    await _updateField(
      title: 'Update Mobile Number',
      currentValue: _mobile,
      keyboardType: TextInputType.phone,
      onConfirm: (newValue) async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'phone': newValue}, SetOptions(merge: true));
        if (mounted) setState(() => _mobile = newValue);
      },
    );
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      // No longer writes 'username' — the field stays untouched on existing
      // documents (never deleted) but is no longer editable here (spec:
      // remove the visible Username field/display from the profile).
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': _displayNameCtrl.text.trim(),
        'locationText': _locationCtrl.text.trim(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved.',
                style: GoogleFonts.zain(color: AppColors.background)),
            backgroundColor: AppColors.textPrimary,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not save: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        title: Text('User Profile',
            style: GoogleFonts.tiltWarp(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickPhoto,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: AppColors.slaterspwn,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _uploadingPhoto
                          ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.textPrimary,
                            strokeWidth: 2),
                      )
                          : (_pickedPhoto != null
                          ? Image.file(_pickedPhoto!,
                          fit: BoxFit.cover)
                          : (_photoUrl != null
                          ? Image.network(_photoUrl!,
                          fit: BoxFit.cover)
                          : const Icon(Icons.person,
                          size: 44,
                          color: AppColors.textSecondary))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickPhoto,
                    child: Text('Change Profile Photo',
                        style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('Profile Details',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            _EditableField(
                label: 'Display name', controller: _displayNameCtrl),
            const SizedBox(height: 14),
            _EditableField(label: 'Location', controller: _locationCtrl),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Contact Details',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.textPrimary),
              ],
            ),
            const SizedBox(height: 14),
            _ContactDetailRow(
              label: 'Email Address',
              value: _email.isEmpty ? 'Not set' : _email,
              onUpdate: _updateEmail,
            ),
            const SizedBox(height: 14),
            _ContactDetailRow(
              label: 'Mobile Number',
              value: _mobile.isEmpty ? 'Not set' : _mobile,
              onUpdate: _updateMobile,
            ),
            const SizedBox(height: 36),
            Center(
              child: SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: _saving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary),
                  )
                      : Text('Save',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _EditableField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
            GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.slaterspwn),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onUpdate;
  const _ContactDetailRow({
    required this.label,
    required this.value,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        TextButton(
          onPressed: onUpdate,
          child: Text('Update',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}