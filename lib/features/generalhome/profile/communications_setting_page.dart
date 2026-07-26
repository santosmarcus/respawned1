import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/profile/settings_widget.dart';


class CommunicationsSettingsPage extends StatefulWidget {
  const CommunicationsSettingsPage({super.key});

  @override
  State<CommunicationsSettingsPage> createState() =>
      _CommunicationsSettingsPageState();
}

class _CommunicationsSettingsPageState
    extends State<CommunicationsSettingsPage> {
  bool _loading = true;
  bool _saving = false;

  bool _updatesPush = false;
  bool _updatesEmail = false;
  bool _updatesSms = false;

  bool _partnersPush = false;
  bool _partnersEmail = false;
  bool _partnersSms = false;
  bool _partnersChatApps = false;

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
          (doc.data()?['notificationPrefs'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _updatesPush = prefs['updatesPush'] as bool? ?? false;
        _updatesEmail = prefs['updatesEmail'] as bool? ?? false;
        _updatesSms = prefs['updatesSms'] as bool? ?? false;
        _partnersPush = prefs['partnersPush'] as bool? ?? false;
        _partnersEmail = prefs['partnersEmail'] as bool? ?? false;
        _partnersSms = prefs['partnersSms'] as bool? ?? false;
        _partnersChatApps = prefs['partnersChatApps'] as bool? ?? false;
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
        'notificationPrefs': {
          'updatesPush': _updatesPush,
          'updatesEmail': _updatesEmail,
          'updatesSms': _updatesSms,
          'partnersPush': _partnersPush,
          'partnersEmail': _partnersEmail,
          'partnersSms': _partnersSms,
          'partnersChatApps': _partnersChatApps,
        },
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Communication preferences saved.',
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
        title: Text('Communications',
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
            const SettingsSectionHeader(
              title: 'Updates',
              description:
              'Receive important announcements, report and feature '
                  'updates, and news about the app.',
            ),
            const SizedBox(height: 10),
            TogglePillRow(
              label: 'Push Notification',
              value: _updatesPush,
              onChanged: (v) => setState(() => _updatesPush = v),
            ),
            TogglePillRow(
              label: 'Email',
              value: _updatesEmail,
              onChanged: (v) => setState(() => _updatesEmail = v),
            ),
            TogglePillRow(
              label: 'SMS',
              value: _updatesSms,
              onChanged: (v) => setState(() => _updatesSms = v),
            ),
            const SizedBox(height: 22),
            const SettingsSectionHeader(
              title: 'Connect with our Partners',
              description:
              "We'll connect you with our partners through your "
                  'preferred method.',
            ),
            const SizedBox(height: 10),
            TogglePillRow(
              label: 'Push Notification',
              value: _partnersPush,
              onChanged: (v) => setState(() => _partnersPush = v),
            ),
            TogglePillRow(
              label: 'Email',
              value: _partnersEmail,
              onChanged: (v) => setState(() => _partnersEmail = v),
            ),
            TogglePillRow(
              label: 'SMS',
              value: _partnersSms,
              onChanged: (v) => setState(() => _partnersSms = v),
            ),
            TogglePillRow(
              label: 'Chat apps',
              value: _partnersChatApps,
              onChanged: (v) => setState(() => _partnersChatApps = v),
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