// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

class AdoptionSectionTitle extends StatelessWidget {
  final String title;
  const AdoptionSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.tiltWarp(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}

// Reusable form field
class AdoptionFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;

  const AdoptionFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'This field is required' : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.zain(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            filled: true,
            fillColor: readOnly
                ? AppColors.slaterspwn.withValues(alpha: 0.3)
                : AppColors.yellowrspwn.withValues(alpha: 0.3),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.slaterspwn, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.greenrspwn,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class AdoptionDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const AdoptionDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          value: value,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.yellowrspwn.withValues(alpha: 0.3),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.slaterspwn, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class AdoptionRadioGroup<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> options;
  final ValueChanged<T?> onChanged;

  const AdoptionRadioGroup({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 2),
        ...options.map((o) {
          return InkWell(
            onTap: () => onChanged(o),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Radio<T>(
                    value: o,
                    groupValue: value,
                    onChanged: onChanged,
                    activeColor: AppColors.greenrspwn,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      o.toString(),
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class AdoptionCounterField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const AdoptionCounterField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          AdoptionCounterButton(
            icon: Icons.remove,
            onTap: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          AdoptionCounterButton(
            icon: Icons.add,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class AdoptionCounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const AdoptionCounterButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap == null
                ? AppColors.slaterspwn.withValues(alpha: 0.5)
                : AppColors.slaterspwn,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null
              ? AppColors.textPrimary.withValues(alpha: 0.5)
              : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class AdoptionInfoTooltip extends StatefulWidget {
  final String message;

  const AdoptionInfoTooltip({super.key, required this.message});

  @override
  State<AdoptionInfoTooltip> createState() => _InfoTooltipState();
}

class _InfoTooltipState extends State<AdoptionInfoTooltip> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final dynamic tooltip = _tooltipKey.currentState;
        tooltip?.ensureTooltipVisible();
      },
      child: Tooltip(
        key: _tooltipKey,
        message: widget.message,
        preferBelow: true,
        triggerMode: TooltipTriggerMode.manual,
        showDuration: const Duration(seconds: 10),
        textStyle: GoogleFonts.zain(fontSize: 14, color: Colors.white),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(Icons.info_outline, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}
