// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_form_widgets.dart';

class HomePhotosPicker extends StatelessWidget {
  final List<String> existingUrls;
  final List<File> newFiles;
  final bool isUploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  const HomePhotosPicker({
    super.key,
    required this.existingUrls,
    required this.newFiles,
    required this.isUploading,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Home Photos',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(width: 4),
            const AdoptionInfoTooltip(
              message:
                  'Upload clear photos of where your pet will live and spend most of its time.\n\n'
                  'Please include:\n'
                  '• The room or area where the pet will sleep/stay\n'
                  '• Any yard, balcony, or outdoor space it can access\n'
                  '• Fencing, gates, or enclosures (if any)\n'
                  '• General home layout so we can check it\'s pet-safe\n\n'
                  'This helps us confirm your home is a safe, suitable environment before approving the adoption.',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < existingUrls.length; i++)
              AdoptionPhotoThumb(
                child: Image.network(
                  existingUrls[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                ),
                onRemove: () => onRemoveExisting(i),
              ),
            for (var i = 0; i < newFiles.length; i++)
              AdoptionPhotoThumb(
                child: Image.file(newFiles[i], fit: BoxFit.cover),
                onRemove: () => onRemoveNew(i),
              ),
            InkWell(
              onTap: isUploading ? null : onAdd,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.greenrspwn.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: isUploading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: AppColors.greenrspwn,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AdoptionPhotoThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const AdoptionPhotoThumb({
    super.key,
    required this.child,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 90, height: 90, child: child),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFFE05353),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdoptionUploadBox extends StatelessWidget {
  final String label;
  final File? file;
  final bool isUploading;
  final VoidCallback onTap;

  const AdoptionUploadBox({
    super.key,
    required this.label,
    required this.file,
    required this.onTap,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: isUploading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 130,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: file != null
                      ? AppColors.greenrspwn
                      : AppColors.greenrspwn.withValues(alpha: 0.6),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : file == null
                  ? const Center(
                      child: Icon(
                        Icons.add,
                        size: 26,
                        color: AppColors.greenrspwn,
                      ),
                    )
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }
}
