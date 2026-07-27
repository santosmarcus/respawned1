import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';


class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _picker = ImagePicker();

  final _usernameCtrl = TextEditingController();
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
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      setState(() {
        _usernameCtrl.text = data['username'] as String? ?? '';
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
    final picked =
    await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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

  Future<void> _updateEmail() async {
    await _updateField(
      title: 'Update Email Address',
      currentValue: _email,
      keyboardType: TextInputType.emailAddress,
      onConfirm: (newValue) async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'email': newValue}, SetOptions(merge: true));
        if (mounted) setState(() => _email = newValue);
      },
    );
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
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'username': _usernameCtrl.text.trim(),
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
            _EditableField(label: 'Username', controller: _usernameCtrl),
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