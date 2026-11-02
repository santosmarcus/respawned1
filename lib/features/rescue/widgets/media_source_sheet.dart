// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';

/// "Add Photo or Video" sheet for one media slot. Resolves to the chosen
/// action: 'photo_camera', 'photo_gallery_multi', 'video_camera',
/// 'video_gallery', 'preview', 'remove', or null if dismissed. [onPreview]
/// and [onRemove] run from inside the sheet, exactly as before.
Future<String?> showMediaSourceSheet(
  BuildContext context, {
  required int maxSlots,
  required RescueMediaItem? current,
  required VoidCallback onPreview,
  required VoidCallback onRemove,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Add Photo or Video',
            style: GoogleFonts.tiltWarp(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(
              'Take a photo',
              style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            onTap: () => Navigator.pop(context, 'photo_camera'),
          ),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(
              'Choose photos from gallery',
              style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Select up to $maxSlots at once',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            onTap: () => Navigator.pop(context, 'photo_gallery_multi'),
          ),
          ListTile(
            leading: const Icon(
              Icons.videocam_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(
              'Record a video',
              style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            onTap: () => Navigator.pop(context, 'video_camera'),
          ),
          ListTile(
            leading: const Icon(
              Icons.video_library_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(
              'Choose video from gallery',
              style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            onTap: () => Navigator.pop(context, 'video_gallery'),
          ),
          if (current != null && current.isVideo)
            ListTile(
              leading: const Icon(
                Icons.play_circle_outline,
                color: AppColors.textPrimary,
              ),
              title: Text(
                'Preview video',
                style: GoogleFonts.zain(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(context, 'preview');
                onPreview();
              },
            ),
          if (current != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: Text(
                'Remove',
                style: GoogleFonts.zain(fontSize: 15, color: Colors.redAccent),
              ),
              onTap: () {
                onRemove();
                Navigator.pop(context, 'remove');
              },
            ),
        ],
      ),
    ),
  );
}
