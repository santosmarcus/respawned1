import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// What a pop-up message is telling the user.
enum AppMessageKind {
  info,
  success,
  error;

  Color get color => switch (this) {
        AppMessageKind.info => AppColors.textPrimary,
        AppMessageKind.success => AppColors.success,
        AppMessageKind.error => AppColors.error,
      };
}

/// The one snackbar look. Use with a messenger captured before an `await`:
/// `messenger.showSnackBar(appSnackBar('Saved.', kind: AppMessageKind.success))`.
SnackBar appSnackBar(String message, {AppMessageKind kind = AppMessageKind.info, SnackBarAction? action}) {
  return SnackBar(
    content: Text(message, style: GoogleFonts.zain(fontSize: 14, color: Colors.white)),
    backgroundColor: kind.color,
    action: action,
  );
}

/// Shows [message] on the nearest scaffold.
void showAppMessage(BuildContext context, String message, {AppMessageKind kind = AppMessageKind.info}) {
  ScaffoldMessenger.of(context).showSnackBar(appSnackBar(message, kind: kind));
}

void showAppError(BuildContext context, String message) =>
    showAppMessage(context, message, kind: AppMessageKind.error);

void showAppSuccess(BuildContext context, String message) =>
    showAppMessage(context, message, kind: AppMessageKind.success);
