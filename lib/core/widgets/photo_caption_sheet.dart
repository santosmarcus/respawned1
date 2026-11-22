import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/photo_captions.dart';

/// Bottom sheet for writing one photo's description, with the photo shown
/// above the field. Returns the new text ('' clears it), or null when
/// dismissed without saving.
Future<String?> showPhotoCaptionSheet(
  BuildContext context, {
  required Widget image,
  String initialValue = '',
  String title = 'Photo description',
  String hint = 'e.g. Loves belly rubs after her morning walk',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PhotoCaptionSheet(image: image, initialValue: initialValue, title: title, hint: hint),
  );
}

class _PhotoCaptionSheet extends StatefulWidget {
  const _PhotoCaptionSheet({required this.image, required this.initialValue, required this.title, required this.hint});

  final Widget image;
  final String initialValue;
  final String title;
  final String hint;

  @override
  State<_PhotoCaptionSheet> createState() => _PhotoCaptionSheetState();
}

class _PhotoCaptionSheetState extends State<_PhotoCaptionSheet> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 200, child: widget.image),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                maxLength: kMaxPhotoCaptionLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              Row(
                children: [
                  if (widget.initialValue.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Remove', style: TextStyle(color: AppColors.error)),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: AppButtons.primary,
                    onPressed: () => Navigator.pop(context, _controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
