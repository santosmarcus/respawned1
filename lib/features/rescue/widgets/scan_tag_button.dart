// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// "Scan for NFC or QR" on the report form: a subsection header saying
/// why to scan (the same style as the form's other headers), then the
/// button.
class ScanTagButton extends StatelessWidget {
  const ScanTagButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RescueSubsectionHeader(
          'Scan for NFC or QR code',
          subtitle: 'This animal may have an ID tag. Scan the NFC or QR code '
              'to help identify the owner.',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(
                color: AppColors.textPrimary,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              backgroundColor: AppColors.yellowrspwn,
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(
              'Scan for NFC or QR',
              style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet offering QR or NFC scanning.
void showScanOptionsSheet(
    BuildContext context, {
      required VoidCallback onScanQr,
      required VoidCallback onScanNfc,
    }) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan Animal Tag',
            style: GoogleFonts.zain(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onScanQr();
                  },
                  icon: const Icon(Icons.qr_code),
                  label: Text('Scan QR', style: GoogleFonts.zain(fontSize: 14)),
                  style: AppButtons.outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onScanNfc();
                  },
                  icon: const Icon(Icons.nfc),
                  label: Text(
                    'Scan NFC',
                    style: GoogleFonts.zain(fontSize: 14),
                  ),
                  style: AppButtons.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
