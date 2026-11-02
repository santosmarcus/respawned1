// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';

/// One 80×80 photo/video slot in the report's media grid.
class RescueMediaBox extends StatelessWidget {
  const RescueMediaBox({
    super.key,
    required this.item,
    required this.progress,
    required this.onTap,
  });

  /// The picked media for this slot, or null when empty.
  final RescueMediaItem? item;

  /// Upload progress 0..1 while submitting, otherwise null.
  final double? progress;

  /// Null while the form is submitting (slot not tappable).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final progress = this.progress;
    return GestureDetector(
      onTap: onTap,

      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(
            color: item != null ? AppColors.greenrspwn : AppColors.textPrimary,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
          color: item != null
              ? AppColors.greenrspwn.withValues(alpha: 0.05)
              : Colors.transparent,
        ),

        clipBehavior: Clip.hardEdge,
        child: item != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  item.isVideo
                      ? Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_outline,
                              size: 28,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        )
                      : Image.file(File(item.file.path), fit: BoxFit.cover),
                  if (progress != null)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3,
                                color: AppColors.yellowrspwn,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : const Center(
                child: Icon(Icons.add, size: 28, color: AppColors.textPrimary),
              ),
      ),
    );
  }
}
