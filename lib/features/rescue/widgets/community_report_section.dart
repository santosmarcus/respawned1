import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/constants/maps_config.dart';

/// Community sighting-update section — "Animal still here" / "Animal
/// moved" / "Animal rescued" / "No animal present", with an optional photo,
/// comment, and (for "moved") a new location. Writes to the existing
/// `cases/{caseId}/communityReports` subcollection and appends a matching
/// `activityLogs` entry — the single shared implementation for every
/// screen that needs this (reporter Track Case, Community Adoption
/// tracking), replacing what used to be a private class copied wholesale
/// between them.
///
/// Deliberately never touches the case's own `status` — submitting a
/// sighting report is purely additive information, never an automatic
/// close/complete of the case (a Community-Adoption-eligible case in
/// particular must stay open until its own completion rule is met, not
/// because someone reported "still here"/"moved").
class CommunityReportSection extends StatefulWidget {
  final String caseId;
  const CommunityReportSection({super.key, required this.caseId});

  @override
  State<CommunityReportSection> createState() => _CommunityReportSectionState();
}

class _CommunityReportSectionState extends State<CommunityReportSection> {
  bool _expanded = false;
  String? _selectedType;
  XFile? _pickedImage;
  bool _submitting = false;
  bool _detectingLocation = false;
  final _commentController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _commentController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      FirebaseFirestore.instance.collection('cases').doc(widget.caseId).collection('communityReports');

  String _typeLabel(String? t) => switch (t) {
        'still_here' => 'Animal still here',
        'moved' => 'Animal moved',
        'rescued' => 'Animal rescued',
        'no_animal' => 'No animal present',
        _ => 'Update',
      };

  String _typeIconAsset(String? t) => switch (t) {
        'still_here' => 'assets/icons/animalstillhere.png',
        'moved' => 'assets/icons/animalmoved.png',
        'rescued' => 'assets/icons/animalrescued.png',
        'no_animal' => 'assets/icons/noanimal.png',
        _ => 'assets/icons/info.png',
      };

  String _typeDescription(String? t) => switch (t) {
        'still_here' => 'Upload a recent photo to confirm the animal is still at the reported location.',
        'moved' =>
          'The animal is no longer at the original location. Upload a recent photo and share the new location so rescuers can keep monitoring safely.',
        'rescued' =>
          'This animal has already been rescued by a rescuer, bystander, or partner organization. Add a photo or other proof to help verify the report.',
        'no_animal' =>
          'No animal was found at the reported location. Add a recent photo of the area to confirm the report may no longer be accurate.',
        _ => '',
      };

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null && mounted) {
      setState(() => _pickedImage = file);
    }
  }

  Future<void> _autoDetectLocation() async {
    if (_detectingLocation) return;
    setState(() {
      _detectingLocation = true;
      _locationController.text = 'Detecting your location…';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _locationController.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please enable location services to auto-detect.'),
              action: SnackBarAction(label: 'Settings', onPressed: () => Geolocator.openLocationSettings()),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationController.clear());
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(
        const Duration(seconds: 12),
        onTimeout: () => Geolocator.getLastKnownPosition().then(
          (p) =>
              p ??
              Position(
                latitude: 14.5416,
                longitude: 121.0644,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              ),
        ),
      );

      String resolvedAddress = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${pos.latitude},${pos.longitude}'
          '&key=${MapsConfig.placesApiKey}',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
          resolvedAddress = data['results'][0]['formatted_address'];
        }
      } catch (_) {}

      if (mounted) setState(() => _locationController.text = resolvedAddress);
    } catch (e) {
      if (mounted) {
        setState(() => _locationController.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect your location — please type it in.')),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null || _submitting) return;
    if (_selectedType == 'moved' && _locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the new location.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'.trim();

      final reportRef = _reportsRef.doc();

      String? photoUrl;
      if (_pickedImage != null) {
        final ref =
            FirebaseStorage.instance.ref().child('cases/${widget.caseId}/communityReports/${reportRef.id}.jpg');
        await ref.putFile(File(_pickedImage!.path), SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      // Deliberately never touches the parent case's own `status` — a
      // sighting update is purely additive, never an automatic close.
      await reportRef.set({
        'reporterId': uid,
        'reporterName': name.isEmpty ? 'A community member' : name,
        'type': _selectedType,
        'comment': _commentController.text.trim(),
        'newAddress': _selectedType == 'moved' ? _locationController.text.trim() : null,
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('cases').doc(widget.caseId).collection('activityLogs').add({
        'action': 'community_report_submitted',
        'actorUid': uid,
        'actorName': name.isEmpty ? 'A community member' : name,
        'actorRole': null,
        'details': {'type': _selectedType},
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _selectedType = null;
          _pickedImage = null;
          _expanded = false;
        });
        _commentController.clear();
        _locationController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your report has been submitted.'), backgroundColor: AppColors.greenrspwn),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _optionButton(String type, String iconAsset, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedType = type);
          if (type == 'moved') _autoDetectLocation();
        },
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
              child: Image.asset(iconAsset, width: 10, height: 10),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 4),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset(_typeIconAsset(_selectedType), fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            Text(_typeLabel(_selectedType),
                style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(_typeDescription(_selectedType),
                textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn),
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.background,
                ),
                child: _pickedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(_pickedImage!.path), fit: BoxFit.cover),
                      )
                    : const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary, size: 26),
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedType == 'moved') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Location Found',
                          style:
                              GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const TextSpan(text: ' *', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _locationController,
                enabled: !_detectingLocation,
                style: GoogleFonts.zain(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter the new location',
                  hintStyle: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  suffixIcon: _detectingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.my_location, size: 18, color: AppColors.textSecondary),
                          tooltip: 'Use current location',
                          onPressed: _autoDetectLocation,
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.slaterspwn),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('Auto-detected from your current location — you can edit it if needed.',
                  style: GoogleFonts.zain(fontSize: 10.5, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _commentController,
              maxLines: 2,
              style: GoogleFonts.zain(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Comment',
                hintStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Report', style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _selectedType = null),
            child: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _formatDate(DateTime d) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final ts = r['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final newAddress = r['newAddress'] as String?;
    final comment = r['comment'] as String?;
    final photoUrl = r['photoUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.textPrimary,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Image.asset(_typeIconAsset(r['type'] as String?), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${r['reporterName'] ?? 'Someone'} · ${_typeLabel(r['type'] as String?)}',
                        style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    if (date != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatTime(date), style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                          Text(_formatDate(date), style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                        ],
                      ),
                  ],
                ),
                if (newAddress != null && newAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(child: Text(newAddress, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary))),
                      ],
                    ),
                  ),
                if (comment != null && comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(comment, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          if (photoUrl != null && photoUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                photoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 36, height: 36, color: AppColors.slaterspwn),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Community Report',
                      style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      textAlign: TextAlign.center),
                ),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(_expanded ? Icons.expand_less : Icons.add_circle_outline, color: AppColors.textPrimary),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (_selectedType == null) ...[
                Text('What is happening?',
                    style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Help keep rescue reports accurate by sharing timely updates on the animal\'s location, condition, and safety.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _optionButton('still_here', 'assets/icons/animalstillhere.png', 'Animal still here'),
                    _optionButton('moved', 'assets/icons/animalmoved.png', 'Animal moved'),
                    _optionButton('rescued', 'assets/icons/animalrescued.png', 'Animal rescued'),
                    _optionButton('no_animal', 'assets/icons/noanimal.png', 'No Animal Present'),
                  ],
                ),
              ] else
                _buildForm(),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppColors.slaterspwn),
            const SizedBox(height: 4),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _reportsRef.orderBy('timestamp', descending: true).limit(20).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Could not load community reports.',
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No community reports yet.',
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  );
                }
                return Column(children: docs.map((d) => _reportTile(d.data())).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}
