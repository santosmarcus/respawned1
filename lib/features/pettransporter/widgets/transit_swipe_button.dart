// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

// Swipe button
class TransitSwipeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onSwiped;

  const TransitSwipeButton({super.key, required this.label, this.onSwiped});

  @override
  State<TransitSwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<TransitSwipeButton> {
  double _dragX = 0;
  static const double _thumbSize = 52;
  static const double _triggerFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onSwiped == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _thumbSize - 8;
        final fraction = (_dragX / maxDrag).clamp(0.0, 1.0);
        // Track is solid dark the whole way through (matches the mockup —
        // no light-grey base with a small dark "fill" nub), thumb is a
        // plain white circle that slides across it.
        final trackColor = disabled
            ? Colors.grey.shade400
            : AppColors.textPrimary;
        final labelColor = disabled
            ? Colors.grey.shade100
            : AppColors.background;
        final thumbIconColor = disabled
            ? Colors.grey.shade400
            : AppColors.textPrimary;

        return GestureDetector(
          onHorizontalDragUpdate: disabled
              ? null
              : (d) => setState(
                  () => _dragX = (_dragX + d.delta.dx).clamp(0, maxDrag),
                ),
          onHorizontalDragEnd: disabled
              ? null
              : (d) {
                  if (fraction >= _triggerFraction) {
                    widget.onSwiped!();
                  }
                  setState(() => _dragX = 0);
                },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Label
                Center(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.tiltWarp(
                      fontSize: 13,
                      color: labelColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Thumb
                Positioned(
                  left: 4 + _dragX,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: thumbIconColor,
                      size: 25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
