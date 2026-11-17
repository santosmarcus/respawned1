// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_form_widgets.dart';

/// One required upload as a full-width line: the label with its red *, an
/// optional info tooltip, and a + on the right. Nothing else shows until a
/// file is picked; then its preview box(es) appear under the line.
class _UploadLine extends StatelessWidget {
  final String label;
  final String? tooltip;
  final bool isUploading;

  /// Null hides the + (e.g. nothing more can be added).
  final VoidCallback? onAdd;
  final String addTooltip;
  final List<Widget> previews;

  const _UploadLine({
    required this.label,
    required this.isUploading,
    required this.onAdd,
    required this.addTooltip,
    this.tooltip,
    this.previews = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.12))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Text(' *', style: TextStyle(color: AppColors.error, fontSize: 14)),
              if (tooltip != null) ...[
                const SizedBox(width: 4),
                AdoptionInfoTooltip(message: tooltip!),
              ],
              const Spacer(),
              if (isUploading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (onAdd != null)
                IconButton(
                  tooltip: addTooltip,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 26, color: AppColors.greenrspwn),
                ),
            ],
          ),
          if (previews.isNotEmpty) ...[
            // Room for each box's remove button, which sits on its corner.
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 10, children: previews),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Government ID / Proof of Address: one file each. Before a file is
/// picked only the line with its + shows; after, its preview box appears
/// (tap it to replace the file, x to remove it). A file uploaded in an
/// earlier session ([url]) shows the same way.
class AdoptionUploadRow extends StatelessWidget {
  final String label;
  final File? file;
  final String? url;
  final bool isUploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const AdoptionUploadRow({
    super.key,
    required this.label,
    required this.file,
    required this.onPick,
    required this.onRemove,
    this.url,
    this.isUploading = false,
  });

  bool get _hasFile => file != null || (url ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return _UploadLine(
      label: label,
      isUploading: isUploading,
      onAdd: _hasFile ? null : onPick,
      addTooltip: 'Upload $label',
      previews: [
        if (_hasFile)
          GestureDetector(
            onTap: isUploading ? null : onPick,
            child: AdoptionPhotoThumb(
              onRemove: onRemove,
              child: file != null
                  ? Image.file(file!, fit: BoxFit.cover)
                  : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.insert_drive_file_outlined),
              ),
            ),
          ),
      ],
    );
  }
}

/// Home Photos: several images. The + stays on the right until the limit
/// is reached; the photo boxes appear only once there are photos.
class HomePhotosPicker extends StatelessWidget {
  final List<String> existingUrls;
  final List<File> newFiles;
  final bool isUploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  /// Hides the + once this many photos are picked.
  final int maxPhotos;

  const HomePhotosPicker({
    super.key,
    required this.existingUrls,
    required this.newFiles,
    required this.isUploading,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    this.maxPhotos = 6,
  });

  @override
  Widget build(BuildContext context) {
    final total = existingUrls.length + newFiles.length;
    return _UploadLine(
      label: 'Home Photos',
      tooltip: 'Upload clear photos of where your pet will live and spend most of its time.\n\n'
          'Please include:\n'
          '• The room or area where the pet will sleep/stay\n'
          '• Any yard, balcony, or outdoor space it can access\n'
          '• Fencing, gates, or enclosures (if any)\n'
          '• General home layout so we can check it\'s pet-safe\n\n'
          'This helps us confirm your home is a safe, suitable environment before approving the adoption.',
      isUploading: isUploading,
      onAdd: total >= maxPhotos ? null : onAdd,
      addTooltip: 'Add home photos',
      previews: [
        for (var i = 0; i < existingUrls.length; i++)
          AdoptionPhotoThumb(
            child: Image.network(
              existingUrls[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
            ),
            onRemove: () => onRemoveExisting(i),
          ),
        for (var i = 0; i < newFiles.length; i++)
          AdoptionPhotoThumb(
            child: Image.file(newFiles[i], fit: BoxFit.cover),
            onRemove: () => onRemoveNew(i),
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
                  color: AppColors.error,
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
