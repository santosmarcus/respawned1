import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/features/rescue/rescue_page.dart'
    show QRScannerPage, RescuePage;
import '../../../app_theme.dart';
import 'collar_id_tag_screen.dart';
import 'collar_tag_data_model.dart';
import 'pet_found_chat.dart';

const String _geocodingApiKey = 'AIzaSyCh•••••••••••••••••••••••••••••••';


class TagScanOutcome {
  final bool tagExists;
  final String? tagId;
  final String? sessionId;
  final String? petName;
  final bool isOwner;
  // Only a tag whose status is 'lost' gets a rescue session (finder
  // tracking + owner-enabled chat). For any other status sessionId is null
  // and the scan opens the regular collar ID tag screen instead.
  final bool isLost;
  final CollarTagData? tagData;

  const TagScanOutcome.notFound()
      : tagExists = false,
        tagId = null,
        sessionId = null,
        petName = null,
        isOwner = false,
        isLost = false,
        tagData = null;

  const TagScanOutcome.found({
    required this.tagId,
    required this.sessionId,
    required this.petName,
    required this.isOwner,
    required this.isLost,
    required this.tagData,
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
  final tag = CollarTagData.fromFirestore(tagData, tagSnap.id);
  final petName = tag.name;

  // Whoever is scanning gets the owner-side experience (the "tap to
  // enable live chat" control) only if they're actually signed in as this
  // tag's owner — otherwise they're a finder and just wait for the owner
  // to enable chat. Previously this was never checked at all: every scan
  // was treated as a finder, so an owner scanning their own tag (e.g. to
  // test the flow, or because they're checking it themselves) would never
  // see the enable-chat prompt, only ever "Waiting for the owner…".
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  final isOwner = currentUid != null && currentUid == tagData['ownerId'];

  // Previously a rescue session was started for every scan regardless of
  // the tag's status, so a pet that wasn't lost still sent the scanner to
  // the lost-pet chat and recorded their location. Only a tag the owner has
  // explicitly marked 'lost' starts (or reuses) a session now.
  final isLost = tag.status == 'lost';

  final sessionId = isLost
      ? await _getOrCreateRescueSession(tagId, location: location)
      : null;

  return TagScanOutcome.found(
    tagId: tagId,
    sessionId: sessionId,
    petName: petName,
    isOwner: isOwner,
    isLost: isLost,
    tagData: tag,
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

    if (!outcome.isLost) {
      // Not lost: show the pet's regular collar ID tag. Finders get the
      // read-only card (no edit / mark-as-lost controls); the owner
      // scanning their own tag gets their normal card.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollarIdTagCardScreen(
            tagData: outcome.tagData!,
            readOnly: !outcome.isOwner,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PetFoundChatScreen(
          tagId: outcome.tagId!,
          sessionId: outcome.sessionId!,
          petName: outcome.petName!,
          isOwner: outcome.isOwner,
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

// Session creation happens server-side via the getOrCreateRescueSession
// Cloud Function (functions/index.js) instead of a direct client write to
// rescueSessions/collarTags. The finder scanning a tag is essentially never
// its owner, so that write previously depended on Firestore rules allowing
// an authenticated-but-non-owner user to create a rescueSessions doc and
// merge activeRescueSessionId onto someone else's collarTags document — the
// exact same category of problem that blocked the fully-anonymous web
// fallback (index.html) from working at all. Routing both through the same
// admin-privileged callable removes that dependency entirely, so neither
// path needs special-cased Firestore rules for this one operation.
Future<String> _getOrCreateRescueSession(
    String tagId, {
      ScanLocation? location,
    }) async {
  final callable =
  FirebaseFunctions.instance.httpsCallable('getOrCreateRescueSession');
  final result = await callable.call(<String, dynamic>{
    'tagId': tagId,
    if (location != null)
      'location': {
        'lat': location.lat,
        'lng': location.lng,
        if (location.address != null) 'address': location.address,
      },
  });
  final data = Map<String, dynamic>.from(result.data as Map);
  final sessionId = data['sessionId'] as String?;
  if (sessionId == null) {
    throw Exception('Could not start a rescue session for this tag.');
  }
  return sessionId;
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