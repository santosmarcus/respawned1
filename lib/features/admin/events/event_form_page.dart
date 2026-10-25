import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/features/admin/events/state/event_providers.dart';

/// Create a new event for [organizationId], or edit [existing].
class EventFormPage extends ConsumerStatefulWidget {
  final String organizationId;
  final VolunteerEvent? existing;
  const EventFormPage({super.key, required this.organizationId, this.existing});

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _address;
  late final TextEditingController _capacity;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _address = TextEditingController(text: e?.addressFull ?? '');
    _capacity = TextEditingController(text: e?.capacity?.toString() ?? '');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _date = e?.startAt ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _start = e != null ? TimeOfDay.fromDateTime(e.startAt) : const TimeOfDay(hour: 9, minute: 0);
    _end = e != null ? TimeOfDay.fromDateTime(e.endAt) : const TimeOfDay(hour: 11, minute: 0);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _address, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final startAt = _at(_start);
    final endAt = _at(_end);
    if (!endAt.isAfter(startAt)) return _snack('End time must be after the start time.');
    if (!_isEditing && startAt.isBefore(DateTime.now())) return _snack('Choose a start time in the future.');
    final capacityText = _capacity.text.trim();
    final capacity = capacityText.isEmpty ? null : int.parse(capacityText);
    final going = widget.existing?.goingCount ?? 0;
    if (capacity != null && capacity < going) {
      return _snack('$going people have already signed up — capacity can\'t be lower than that.');
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(volunteerEventRepositoryProvider);
      final organizerName = widget.existing?.organizerName ?? await _organizationName();
      final draft = VolunteerEvent(
        id: widget.existing?.id ?? '',
        organizationId: widget.organizationId,
        title: _title.text.trim(),
        description: _description.text.trim(),
        location: _location.text.trim(),
        addressFull: _address.text.trim(),
        organizerName: organizerName,
        startAt: startAt,
        endAt: endAt,
        capacity: capacity,
      );
      if (_isEditing) {
        await repo.updateEvent(eventId: widget.existing!.id, draft: draft);
      } else {
        await repo.createEvent(organizationId: widget.organizationId, draft: draft);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[EventFormPage] save failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save the event.');
      }
    }
  }

  Future<String> _organizationName() async {
    final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
    final name = doc.data()?['name'] as String?;
    return (name == null || name.trim().isEmpty) ? 'Organization' : name.trim();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.background),
        title: Text(_isEditing ? 'Edit Event' : 'New Event',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_title, 'Event title', validator: _required),
            _field(_description, 'Description', maxLines: 5, validator: _required),
            _field(_location, 'Location (shown on cards)', hint: 'e.g. General Trias, Cavite', validator: _required),
            _field(_address, 'Full address', validator: _required),
            const SizedBox(height: 4),
            _pickerTile(Icons.calendar_today_outlined, 'Date', DateFormat('EEEE, MMMM d, y').format(_date), _pickDate),
            Row(
              children: [
                Expanded(
                  child: _pickerTile(Icons.access_time, 'Starts', _start.format(context), () => _pickTime(start: true)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pickerTile(Icons.access_time, 'Ends', _end.format(context), () => _pickTime(start: false)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _field(
              _capacity,
              'Capacity (optional)',
              hint: 'Leave blank for no limit',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => (v != null && v.isNotEmpty && int.parse(v) <= 0) ? 'Must be at least 1' : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Save Changes' : 'Publish Event', style: GoogleFonts.tiltWarp(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _pickerTile(IconData icon, String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(icon, size: 18),
          ),
          child: Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ),
      ),
    );
  }
}
