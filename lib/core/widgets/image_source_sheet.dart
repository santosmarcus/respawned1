import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';

/// Bottom sheet asking where a photo should come from. Null if dismissed.
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
            title: Text('Choose from Gallery', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: AppColors.textPrimary),
            title: Text('Take Photo', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Asks gallery vs camera, then picks a single image.
Future<XFile?> pickImageWithSource(
    BuildContext context,
    ImagePicker picker, {
      int imageQuality = 80,
      double? maxWidth,
    }) async {
  final source = await showImageSourceSheet(context);
  if (source == null) return null;
  return picker.pickImage(source: source, imageQuality: imageQuality, maxWidth: maxWidth);
}

/// Asks gallery vs camera. Gallery allows multi-select; camera returns the
/// one photo taken. Empty if dismissed/cancelled.
Future<List<XFile>> pickImagesWithSource(
    BuildContext context,
    ImagePicker picker, {
      int imageQuality = 80,
      double? maxWidth,
    }) async {
  final source = await showImageSourceSheet(context);
  if (source == null) return const [];
  if (source == ImageSource.gallery) {
    return picker.pickMultiImage(imageQuality: imageQuality, maxWidth: maxWidth);
  }
  final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: imageQuality, maxWidth: maxWidth);
  return photo == null ? const [] : [photo];
}