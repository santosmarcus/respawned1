// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

// Step tracker widget
class AdoptionStepTracker extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final int? displayIndex;
  final bool rejected;
  final ValueChanged<int>? onStepTap;

  const AdoptionStepTracker({
    super.key,
    required this.labels,
    required this.activeIndex,
    this.displayIndex,
    this.rejected = false,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(labels.length, (index) {
        final isDone = index < activeIndex;
        final isActive = index == activeIndex;
        final isReachable = index <= activeIndex;
        final isBeingViewed = displayIndex != null && index == displayIndex;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isReachable && onStepTap != null
                ? () => onStepTap!(index)
                : null,
            child: Column(
              children: [
                SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      if (index != 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: index == 0
                                ? Colors.transparent
                                : (isReachable
                                      ? AppColors.lavenderrspwn
                                      : AppColors.slaterspwn),
                          ),
                        ),

                      Container(
                        width: isBeingViewed ? 18 : 14,
                        height: isBeingViewed ? 18 : 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone || isActive
                              ? AppColors.lavenderrspwn
                              : Colors.transparent,
                          border: Border.all(
                            color: isBeingViewed
                                ? AppColors.yellowrspwn
                                : (isDone || isActive
                                      ? AppColors.lavenderrspwn
                                      : AppColors.slaterspwn),
                            width: isBeingViewed ? 2.5 : 1,
                          ),
                        ),
                        child: isDone
                            ? const Icon(
                                Icons.check,
                                size: 9,
                                color: AppColors.textPrimary,
                              )
                            : null,
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index == labels.length - 1
                              ? Colors.transparent
                              : (isDone
                                    ? AppColors.lavenderrspwn
                                    : AppColors.slaterspwn),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: 70,
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
