import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// The one way the app asks "why?": reject a report or an adoption, close a
/// case, end a trip, decline a request, reject treatment. Every picker
/// shares the same sheet, the same option list and the same rule: choosing
/// an "Other" option always needs a typed explanation.

/// One choice in a reason list.
class ReasonOption<T> {
  const ReasonOption(this.value, this.label, {this.isOther = false});

  final T value;
  final String label;

  /// Picking this option requires a typed explanation.
  final bool isOther;
}

/// What [showReasonPicker] returns.
class ReasonPickerResult<T> {
  const ReasonPickerResult({required this.values, this.otherText, this.note});

  /// The chosen options (exactly one unless the picker allowed several).
  final List<T> values;

  /// The typed explanation, when an "Other" option was chosen.
  final String? otherText;

  /// The optional or required notes field, when the picker had one.
  final String? note;

  T get value => values.first;
}

/// Bottom sheet with one list of reasons.
///
/// [multiple] allows several reasons (checkboxes) instead of one (radio).
/// [noteLabel] adds a notes field under the list; [noteRequired] makes it
/// mandatory.
Future<ReasonPickerResult<T>?> showReasonPicker<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<ReasonOption<T>> options,
  T? initial,
  bool multiple = false,
  String confirmLabel = 'Confirm',
  bool destructive = true,
  String? noteLabel,
  bool noteRequired = false,
}) {
  return showReasonSheet<ReasonPickerResult<T>>(
    context,
    builder: (_) => _ReasonPickerBody<T>(
      title: title,
      subtitle: subtitle,
      options: options,
      initial: initial,
      multiple: multiple,
      confirmLabel: confirmLabel,
      destructive: destructive,
      noteLabel: noteLabel,
      noteRequired: noteRequired,
    ),
  );
}

/// Opens [builder] in the shared reason sheet. For a form that needs more
/// than [showReasonPicker] offers, build it with [ReasonSheetFrame] and
/// [ReasonChoiceList].
Future<R?> showReasonSheet<R>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: builder,
  );
}

class _ReasonPickerBody<T> extends StatefulWidget {
  const _ReasonPickerBody({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.initial,
    required this.multiple,
    required this.confirmLabel,
    required this.destructive,
    required this.noteLabel,
    required this.noteRequired,
  });

  final String title;
  final String? subtitle;
  final List<ReasonOption<T>> options;
  final T? initial;
  final bool multiple;
  final String confirmLabel;
  final bool destructive;
  final String? noteLabel;
  final bool noteRequired;

  @override
  State<_ReasonPickerBody<T>> createState() => _ReasonPickerBodyState<T>();
}

class _ReasonPickerBodyState<T> extends State<_ReasonPickerBody<T>> {
  late final List<T> _selected = [if (widget.initial != null) widget.initial as T];
  final _other = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _otherChosen => widget.options.any((o) => o.isOther && _selected.contains(o.value));

  bool get _canConfirm =>
      _selected.isNotEmpty &&
      (!_otherChosen || _other.text.trim().isNotEmpty) &&
      (widget.noteLabel == null || !widget.noteRequired || _note.text.trim().isNotEmpty);

  void _confirm() {
    final note = _note.text.trim();
    Navigator.pop(
      context,
      ReasonPickerResult<T>(
        // Keep the options' own order, not the order they were tapped.
        values: [for (final o in widget.options) if (_selected.contains(o.value)) o.value],
        otherText: _otherChosen ? _other.text.trim() : null,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReasonSheetFrame(
      title: widget.title,
      subtitle: widget.subtitle,
      confirmLabel: widget.confirmLabel,
      destructive: widget.destructive,
      onConfirm: _canConfirm ? _confirm : null,
      children: [
        ReasonChoiceList<T>(
          options: widget.options,
          selected: _selected,
          multiple: widget.multiple,
          otherController: _other,
          onChanged: (values) => setState(() => _selected
            ..clear()
            ..addAll(values)),
          onOtherChanged: () => setState(() {}),
        ),
        if (widget.noteLabel != null) ...[
          const SizedBox(height: 12),
          ReasonTextField(
            controller: _note,
            label: widget.noteRequired ? widget.noteLabel! : '${widget.noteLabel!} (optional)',
            maxLines: 3,
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }
}

/// The sheet layout every reason form uses: handle, title, optional
/// subtitle, the form, then Cancel and the confirm button.
class ReasonSheetFrame extends StatelessWidget {
  const ReasonSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    required this.confirmLabel,
    required this.onConfirm,
    this.destructive = true,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String confirmLabel;

  /// Null disables the confirm button (the form is incomplete).
  final VoidCallback? onConfirm;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(title, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      style: AppButtons.outline,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: busy ? null : onConfirm,
                      style: destructive ? AppButtons.danger : AppButtons.primary,
                      child: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(confirmLabel, textAlign: TextAlign.center),
                    ),
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

/// A list of reasons, one (radio) or several (checkboxes), with a
/// "please specify" field under any chosen "Other" option.
class ReasonChoiceList<T> extends StatelessWidget {
  const ReasonChoiceList({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.otherController,
    this.onOtherChanged,
    this.multiple = false,
    this.otherHint = 'Please specify',
  });

  final List<ReasonOption<T>> options;
  final List<T> selected;

  /// Called with the full new selection.
  final ValueChanged<List<T>> onChanged;
  final TextEditingController otherController;
  final VoidCallback? onOtherChanged;
  final bool multiple;
  final String otherHint;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final o in options) {
      final on = selected.contains(o.value);
      final label = Text(o.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary));
      rows.add(multiple
          ? CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.textPrimary,
              value: on,
              title: label,
              onChanged: (v) => onChanged([
                for (final x in options)
                  if (x.value == o.value ? v == true : selected.contains(x.value)) x.value,
              ]),
            )
          : RadioListTile<T>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.textPrimary,
              value: o.value,
              title: label,
            ));
      if (o.isOther && on) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: ReasonTextField(controller: otherController, label: otherHint, onChanged: onOtherChanged),
        ));
      }
    }
    final list = Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
    if (multiple) return list;
    return RadioGroup<T>(
      groupValue: selected.isEmpty ? null : selected.first,
      onChanged: (v) {
        if (v != null) onChanged([v]);
      },
      child: list,
    );
  }
}

/// A heading for a second group of choices inside a reason sheet.
class ReasonSectionLabel extends StatelessWidget {
  const ReasonSectionLabel(this.text, {super.key, this.help});

  final String text;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (help != null)
            Text(help!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// The text field reason sheets use for "please specify" and notes.
class ReasonTextField extends StatelessWidget {
  const ReasonTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final VoidCallback? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => onChanged?.call(),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}
