import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';

/// Proof that has to be taken now, on the spot: camera only (never the
/// gallery), plus where the phone is. Used for the reporter's live proof and
/// the rider's verification visit.

/// Asks for a photo or a short video and opens the camera. Null if
/// dismissed.
Future<PickedMedia?> captureWithCamera(BuildContext context, {String title = 'Take it now', bool allowVideo = true}) async {
  var video = false;
  if (allowVideo) {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget tile(IconData icon, String label, bool value) => ListTile(
              leading: Icon(icon, color: AppColors.textPrimary),
              title: Text(label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, value),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              ),
              tile(Icons.camera_alt_outlined, 'Take a photo', false),
              tile(Icons.videocam_outlined, 'Record a short video', true),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice == null) return null;
    video = choice;
  }
  final picker = ImagePicker();
  final file = video
      ? await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30))
      : await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
  return file == null ? null : PickedMedia(file, isVideo: video);
}

/// Where the phone is right now, or null when location is off, denied or
/// too slow. Never throws: proof is still accepted without a location, and
/// staff are told it has none.
Future<Position?> currentPositionOrNull({Duration timeout = const Duration(seconds: 10)}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(timeout);
  } catch (_) {
    return null;
  }
}
