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
SnackBar appSnackBar(
  String message, {
  AppMessageKind kind = AppMessageKind.info,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  return SnackBar(
    content: Text(message, style: GoogleFonts.zain(fontSize: 14, color: Colors.white)),
    backgroundColor: kind.color,
    action: action,
    duration: duration,
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

/// The one inline error box (a form or screen that failed): a tinted panel
/// with an icon and the message, in the error colour.
class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.zain(fontSize: 13, color: AppColors.error))),
        ],
      ),
    );
  }
}
