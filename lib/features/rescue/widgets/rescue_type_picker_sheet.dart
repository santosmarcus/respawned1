// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// Rescue Type picker; resolves to the chosen label, or null if dismissed.
Future<String?> showRescueTypePickerSheet(
  BuildContext context, {
  required String? selectedType,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
              'Rescue Type',
              style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: kRescueTypeOptions.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: AppColors.slaterspwn.withValues(alpha: 0.4),
                ),
                itemBuilder: (context, index) {
                  final option = kRescueTypeOptions[index];
                  final isSelected = option['label'] == selectedType;
                  final urgency = option['urgency'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            option['label']!,
                            style: GoogleFonts.zain(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (urgency != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: urgencyColorFor(
                                urgency,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: urgencyColorFor(urgency),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              urgency,
                              style: GoogleFonts.zain(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      option['description']!,
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.textPrimary,
                            size: 20,
                          )
                        : null,
                    onTap: () => Navigator.pop(context, option['label']),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
