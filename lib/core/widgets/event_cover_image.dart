import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';

/// A volunteer event's cover photo, or a plain colored block when the event
/// has none (events created before covers existed, or saved without one).
class EventCoverImage extends StatelessWidget {
  final String? imageUrl;
  final double? height;
  final double? width;
  final double borderRadius;
  final Color placeholderColor;

  const EventCoverImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width = double.infinity,
    this.borderRadius = 16,
    this.placeholderColor = AppColors.slaterspwn,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: placeholderColor);
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: width,
        child: (url == null || url.isEmpty)
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => Container(
                  color: placeholderColor,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                ),
              ),
      ),
    );
  }
}
