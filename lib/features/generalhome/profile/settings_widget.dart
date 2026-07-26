import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';


class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String description;
  const SettingsSectionHeader(
      {super.key, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.tiltWarp(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(description,
            style: GoogleFonts.zain(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}


class TogglePillRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const TogglePillRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
          TogglePill(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}


class TogglePill extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const TogglePill({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.textPrimary, width: 1.3),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: value ? Colors.white : AppColors.textPrimary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}