import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/date_time_picker_sheet.dart' as picker;

typedef RetrievalSchedule = ({DateTime dateTime, String address, String contact, String? notes});

/// Set/Reschedule Retrieval Schedule sheet (spec §18) — built on the same
/// shared date/time picker used for the adopter pickup flow, plus the
/// address/contact/notes fields the spec adds on top.
Future<RetrievalSchedule?> showRetrievalScheduleSheet(
  BuildContext context, {
  DateTime? initialDateTime,
  String? initialAddress,
  String? initialContact,
  String? initialNotes,
}) {
  return showModalBottomSheet<RetrievalSchedule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RetrievalScheduleSheet(
      initialDateTime: initialDateTime,
      initialAddress: initialAddress,
      initialContact: initialContact,
      initialNotes: initialNotes,
    ),
  );
}

class _RetrievalScheduleSheet extends StatefulWidget {
  final DateTime? initialDateTime;
  final String? initialAddress;
  final String? initialContact;
  final String? initialNotes;

  const _RetrievalScheduleSheet({this.initialDateTime, this.initialAddress, this.initialContact, this.initialNotes});

  @override
  State<_RetrievalScheduleSheet> createState() => _RetrievalScheduleSheetState();
}

class _RetrievalScheduleSheetState extends State<_RetrievalScheduleSheet> {
  DateTime? _date;
  String? _time;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDateTime;
    _time = widget.initialDateTime == null
        ? null
        : '${widget.initialDateTime!.hour.toString().padLeft(2, '0')}:${widget.initialDateTime!.minute.toString().padLeft(2, '0')}';
    _addressCtrl = TextEditingController(text: widget.initialAddress ?? '');
    _contactCtrl = TextEditingController(text: widget.initialContact ?? '');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _contactCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final result = await picker.showDateTimePickerSheet(
      context,
      title: 'Select Retrieval Date & Time',
      initialDate: _date,
      initialTime: _time,
    );
    if (result != null) setState(() {
      _date = result.date;
      _time = result.time;
    });
  }

  DateTime? get _combinedDateTime {
    if (_date == null || _time == null) return null;
    // _time comes either as "9:00 AM"-style slots (shared picker) or
    // "HH:mm" (pre-filled from an existing schedule) — parse both.
    final ampmMatch = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(_time!);
    if (ampmMatch != null) {
      var hour = int.parse(ampmMatch.group(1)!);
      final minute = int.parse(ampmMatch.group(2)!);
      final isPm = ampmMatch.group(3)!.toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(_date!.year, _date!.month, _date!.day, hour, minute);
    }
    final parts = _time!.split(':');
    return DateTime(_date!.year, _date!.month, _date!.day, int.tryParse(parts[0]) ?? 0, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final dt = _combinedDateTime;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Retrieval Schedule', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.event),
              label: Text(dt == null ? 'Choose date & time' : picker.formatScheduleDate(dt) + (_time != null ? '  ·  $_time' : '')),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Pickup address', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contactCtrl,
              decoration: const InputDecoration(labelText: 'Contact person', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (dt == null || _addressCtrl.text.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(context, (
                          dateTime: dt,
                          address: _addressCtrl.text.trim(),
                          contact: _contactCtrl.text.trim(),
                          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
                        )),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                child: const Text('Save Schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
