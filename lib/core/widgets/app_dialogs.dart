import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// The app's dialogs. Use these instead of building an [AlertDialog] so every
/// yes/no question, text prompt and notice looks and behaves the same.

AlertDialog _frame({
  required String title,
  Widget? content,
  required List<Widget> actions,
}) {
  return AlertDialog(
    backgroundColor: AppColors.background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
    content: content,
    actions: actions,
  );
}

Widget _message(String text) =>
    Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary));

Widget _cancelButton(BuildContext ctx, String label, Object? result) => TextButton(
      onPressed: () => Navigator.pop(ctx, result),
      child: Text(label, style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
    );

Widget _confirmButton({required VoidCallback? onPressed, required String label, required bool destructive}) =>
    ElevatedButton(
      onPressed: onPressed,
      style: destructive ? AppButtons.danger : AppButtons.primary,
      child: Text(label, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
    );

/// Yes/no question. Returns true only if the confirm button was tapped.
///
/// Give [message] for plain text, or [content] for anything richer (a summary
/// of what will happen). [destructive] makes the confirm button red.
Future<bool> showConfirmActionDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  assert(message != null || content != null, 'Give a message or content.');
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _frame(
      title: title,
      content: content ?? _message(message!),
      actions: [
        _cancelButton(ctx, cancelLabel, false),
        _confirmButton(onPressed: () => Navigator.pop(ctx, true), label: confirmLabel, destructive: destructive),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for one piece of text (a reason, a note, a message). Returns the
/// trimmed text, or null if cancelled. When [required] is true the confirm
/// button stays disabled until something is typed.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String label,
  String? hint,
  String initialValue = '',
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  bool required = false,
  bool destructive = false,
  int maxLines = 3,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      message: message,
      label: label,
      hint: hint,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      required: required,
      destructive: destructive,
      maxLines: maxLines,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.required,
    required this.destructive,
    required this.maxLines,
  });

  final String title;
  final String? message;
  final String label;
  final String? hint;
  final String initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final bool required;
  final bool destructive;
  final int maxLines;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final canConfirm = !widget.required || text.isNotEmpty;
    return _frame(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[_message(widget.message!), const SizedBox(height: 12)],
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: widget.maxLines,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.required ? widget.label : '${widget.label} (optional)',
              hintText: widget.hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        _cancelButton(context, widget.cancelLabel, null),
        _confirmButton(
          onPressed: canConfirm ? () => Navigator.pop(context, text) : null,
          label: widget.confirmLabel,
          destructive: widget.destructive,
        ),
      ],
    );
  }
}

/// A notice with a single close button.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String closeLabel = 'Close',
}) {
  assert(message != null || content != null, 'Give a message or content.');
  return showDialog<void>(
    context: context,
    builder: (ctx) => _frame(
      title: title,
      content: content ?? _message(message!),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(closeLabel, style: GoogleFonts.zain(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
