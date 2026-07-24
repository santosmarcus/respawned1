import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/animal_image_gallery.dart' show FullscreenImageGallery;

/// A small horizontally-scrollable row of square photo thumbnails — tapping
/// any one opens the same full-screen, swipeable, page-indicated preview
/// AnimalImageGallery uses (FullscreenImageGallery), reused rather than
/// building a second fullscreen viewer. For photo sets that are just a
/// handful of documents/uploads (e.g. adoption application Home Photos)
/// rather than a single hero gallery.
class PhotoThumbnailStrip extends StatelessWidget {
  final List<String> photoUrls;
  final double size;

  const PhotoThumbnailStrip({super.key, required this.photoUrls, this.size = 72});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photoUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => FullscreenImageGallery(photoUrls: photoUrls, initialIndex: i),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              photoUrls[i],
              width: size,
              height: size,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: AppColors.tearspwn,
                child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
