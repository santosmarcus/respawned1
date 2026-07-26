import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/profile/settings_widget.dart';


class LocationSharingPage extends StatefulWidget {
  const LocationSharingPage({super.key});

  @override
  State<LocationSharingPage> createState() => _LocationSharingPageState();
}

class _LocationSharingPageState extends State<LocationSharingPage> {
  bool _loading = true;
  bool _saving = false;
  bool _transportSharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final prefs =
          (doc.data()?['locationSharingPrefs'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _transportSharing = prefs['transport'] as bool? ?? false;
      });
    } catch (_) {

    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'locationSharingPrefs': {
          'transport': _transportSharing,
        },
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location sharing preferences saved.',
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
        title: Text('Location Sharing',
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
            Text(
              'Share your location to help with rescue requests, pet '
                  'transport, and nearby animal services.',
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            TogglePillRow(
              label: 'Transport',
              value: _transportSharing,
              onChanged: (v) => setState(() => _transportSharing = v),
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