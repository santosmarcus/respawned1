import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/profile/settings_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:respawnd1/core/geofence/geofence_config.dart';
import 'package:respawnd1/core/services/geofence_service.dart';

class LocationSharingPage extends StatefulWidget {
  const LocationSharingPage({super.key});

  @override
  State<LocationSharingPage> createState() => _LocationSharingPageState();
}

class _LocationSharingPageState extends State<LocationSharingPage> {
  bool _loading = true;
  bool _saving = false;
  bool _transportSharing = false;
  GeofencePrefs _geofence = const GeofencePrefs();
  bool _backgroundGranted = false;

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
      final permission = await Geolocator.checkPermission();
      setState(() {
        _transportSharing = prefs['transport'] as bool? ?? false;
        _geofence = GeofencePrefs.fromUserData(doc.data());
        _backgroundGranted = permission == LocationPermission.always;
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
    'geofencePrefs': _geofence.toMap(),
    }, SetOptions(merge: true));
    // Re-register (or remove) this device's geofences with the new prefs.
    GeofenceService.sync(force: true);
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

  Future<void> _requestBackground() async {
    final granted = await GeofenceService.requestBackgroundPermission();
    if (!mounted) return;
    setState(() => _backgroundGranted = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose "Allow all the time" under Location, then come back.'),
        ),
      );
    }
  }

  Widget _buildGeofenceSection() {
    final titleStyle = GoogleFonts.tiltWarp(
        fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary);
    final smallStyle = GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nearby alerts (geofencing)', style: titleStyle),
        const SizedBox(height: 4),
        Text(
          'Get notified about rescues, lost pets and completed rescues inside '
              'your alert radius, even when the app is closed.',
          style: smallStyle,
        ),
        const SizedBox(height: 12),
        TogglePillRow(
          label: 'Nearby alerts',
          value: _geofence.enabled,
          onChanged: (v) => setState(() => _geofence = _geofence.copyWith(enabled: v)),
        ),
        if (_geofence.enabled) ...[
          const SizedBox(height: 12),
          Text('Alert radius: ${_geofence.radiusKm.toStringAsFixed(0)} km',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
          Slider(
            value: _geofence.radiusKm,
            min: 1,
            max: GeofenceConfig.maxAlertRadiusKm,
            divisions: (GeofenceConfig.maxAlertRadiusKm - 1).round(),
            activeColor: AppColors.greenrspwn,
            label: '${_geofence.radiusKm.toStringAsFixed(0)} km',
            onChanged: (v) => setState(() => _geofence = _geofence.copyWith(radiusKm: v)),
          ),
          const SizedBox(height: 4),
          for (final entry in GeofenceCategory.labels.entries) ...[
            TogglePillRow(
              label: entry.value,
              value: !_geofence.mutedCategories.contains(entry.key),
              onChanged: (on) {
                final muted = {..._geofence.mutedCategories};
                on ? muted.remove(entry.key) : muted.add(entry.key);
                setState(() => _geofence = _geofence.copyWith(mutedCategories: muted));
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _backgroundGranted ? Icons.check_circle : Icons.info_outline,
                size: 18,
                color: _backgroundGranted ? AppColors.greenrspwn : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _backgroundGranted
                      ? 'Background location is on — alerts work while the app is closed.'
                      : 'Background location is off — you only get alerts based on where you last opened the app.',
                  style: smallStyle,
                ),
              ),
            ],
          ),
          if (!_backgroundGranted)
            TextButton(
              onPressed: _requestBackground,
              child: const Text('Allow background location'),
            ),
        ],
      ],
    );
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

            const SizedBox(height: 28),
            _buildGeofenceSection(),

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