import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/features/rescue/rescue_page.dart'
    show QRScannerPage, RescuePage;
import '../../../app_theme.dart';
import 'pet_found_chat.dart';

const String _geocodingApiKey = 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0';


class TagScanOutcome {
  final bool tagExists;
  final String? tagId;
  final String? sessionId;
  final String? petName;

  const TagScanOutcome.notFound()
      : tagExists = false,
        tagId = null,
        sessionId = null,
        petName = null;

  const TagScanOutcome.found({
    required this.tagId,
    required this.sessionId,
    required this.petName,
  }) : tagExists = true;
}

class ScanLocation {
  final double lat;
  final double lng;
  final String? address;
  const ScanLocation({required this.lat, required this.lng, this.address});
}


Future<TagScanOutcome> resolveScannedTagId(
    String tagId, {
      ScanLocation? location,
    }) async {
  final tagRef =
  FirebaseFirestore.instance.collection('collarTags').doc(tagId);
  final tagSnap = await tagRef.get();
  if (!tagSnap.exists) return const TagScanOutcome.notFound();

  final tagData = tagSnap.data() as Map<String, dynamic>;
  final petName = tagData['name'] as String? ?? '';
  final existingSessionId = tagData['activeRescueSessionId'] as String?;

  String? sessionId;
  if (existingSessionId != null && existingSessionId.isNotEmpty) {
    final existingSnap = await FirebaseFirestore.instance
        .collection('rescueSessions')
        .doc(existingSessionId)
        .get();
    final existingStatus = existingSnap.data()?['status'] as String?;
    if (existingSnap.exists && existingStatus == 'active') {
      sessionId = existingSessionId;
    }
  }
  sessionId ??= await _createRescueSession(tagId, location: location);

  return TagScanOutcome.found(
    tagId: tagId,
    sessionId: sessionId,
    petName: petName,
  );
}

Future<ScanLocation?> fetchBestEffortScanLocation() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    ).then<Position?>((p) => p).timeout(
      const Duration(seconds: 8),
      onTimeout: () => Geolocator.getLastKnownPosition(),
    );
    if (pos == null) return null;
    final address = await _reverseGeocode(pos.latitude, pos.longitude);
    return ScanLocation(lat: pos.latitude, lng: pos.longitude, address: address);
  } catch (_) {
    return null;
  }
}

Future<void> startTagScan(BuildContext context) async {
  final rawResult = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const QRScannerPage()),
  );
  if (rawResult == null || !context.mounted) return;

  final tagId = AppLinks.tagIdFromScan(rawResult);
  if (tagId == null) {
    _openNoPetFound(context);
    return;
  }

  bool spinnerShowing = true;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ResolvingScanDialog(),
  );

  try {
    final location = await fetchBestEffortScanLocation();
    final outcome = await resolveScannedTagId(tagId, location: location);

    if (!context.mounted) return;
    Navigator.pop(context); // dismiss the spinner
    spinnerShowing = false;

    if (!outcome.tagExists) {
      _openNoPetFound(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PetFoundChatScreen(
          tagId: outcome.tagId!,
          sessionId: outcome.sessionId!,
          petName: outcome.petName!,
          isOwner: false,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      if (spinnerShowing) Navigator.pop(context); // dismiss spinner if still up
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not process this scan: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

Future<String> _createRescueSession(
    String tagId, {
      ScanLocation? location,
    }) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;

  final sessionRef =
  FirebaseFirestore.instance.collection('rescueSessions').doc();
  await sessionRef.set({
    'tagId': tagId,
    'finderId': uid,
    'status': 'active',
    'chatEnabledByOwner': false,
    if (location != null) 'lat': location.lat,
    if (location != null) 'lng': location.lng,
    if (location?.address != null) 'address': location!.address,
    'createdAt': FieldValue.serverTimestamp(),
  });

  await FirebaseFirestore.instance
      .collection('collarTags')
      .doc(tagId)
      .set({'activeRescueSessionId': sessionRef.id}, SetOptions(merge: true));

  return sessionRef.id;
}

Future<String?> _reverseGeocode(double lat, double lng) async {
  try {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng&key=$_geocodingApiKey',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 8));
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 &&
        data['status'] == 'OK' &&
        (data['results'] as List).isNotEmpty) {
      return data['results'][0]['formatted_address'] as String?;
    }
  } catch (_) {}
  return null;
}

void _openNoPetFound(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NoPetFoundScreen()),
  );
}

class _ResolvingScanDialog extends StatelessWidget {
  const _ResolvingScanDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Text('Looking up this tag…',
                style:
                GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

// Shown when a scanned QR/NFC code doesn't match any registered collar tag.
class NoPetFoundScreen extends StatelessWidget {
  const NoPetFoundScreen({super.key});

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
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(Icons.search_off,
                  size: 52, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            Text(
              'No Pet Found',
              style: GoogleFonts.tiltWarp(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              "This code isn't linked to a registered collar tag. It may be "
                  "damaged, unregistered, or from outside ResPAWnd.",
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const RescuePage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: Text('Report as a Stray Instead',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Scan Again',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}