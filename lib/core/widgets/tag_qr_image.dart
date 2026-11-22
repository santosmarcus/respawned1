import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:respawnd1/app_theme.dart';

/// The one QR renderer for collar tags: shelter animal tags (Management
/// tab), owner collar tags (admin Collar Tags, the owner's ID card). Draws
/// nothing scannable for an empty value: it shows a message instead, so a
/// tag without a usable code can't be printed.
///
/// Sized explicitly: AlertDialog asks its content for an intrinsic width,
/// which QrImageView (a LayoutBuilder) can't report.
class TagQrImage extends StatelessWidget {
  const TagQrImage({super.key, required this.data, this.size = 160});

  /// The machine-readable value (an animal tag payload or a tag link).
  final String? data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = data?.trim() ?? '';
    Widget message(String text) => Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ),
        );
    return SizedBox.square(
      dimension: size,
      child: value.isEmpty
          ? message('This tag has no code yet, so there is no QR code to show.')
          : QrImageView(
              data: value,
              version: QrVersions.auto,
              size: size,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
              errorStateBuilder: (_, _) => message('Couldn’t draw this QR code.'),
            ),
    );
  }
}
