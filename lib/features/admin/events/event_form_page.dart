import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/features/admin/events/state/event_providers.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';

/// Create a new event for [organizationId], or edit [existing]. Laid out like
/// Create Campaign / Create Animal Record: centered heading, required-field
/// note, then labelled sections with underline fields and a yellow pill
/// button. The location comes from the same map/address picker as the
/// Organization Profile (in its pick-only mode).
class EventFormPage extends ConsumerStatefulWidget {
  final String organizationId;
  final VolunteerEvent? existing;
  const EventFormPage({super.key, required this.organizationId, this.existing});

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _picker = ImagePicker();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;

  // Location from the map picker. On a legacy event (text address only)
  // these start null and _addressFull holds the old typed address.
  String _addressFull = '';
  String? _placeName;
  String? _placeId;
  double? _lat;
  double? _lng;

  // Cover image: a newly picked file wins over the saved URL.
  XFile? _image;
  String? _imageUrl;

  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _hasPin => _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _capacity = TextEditingController(text: e?.capacity?.toString() ?? '');
    _addressFull = e?.addressFull ?? '';
    _placeName = e?.location;
    _placeId = e?.placeId;
    _lat = e?.lat;
    _lng = e?.lng;
    _imageUrl = e?.imageUrl;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _date = e?.startAt ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _start = e != null ? TimeOfDay.fromDateTime(e.startAt) : const TimeOfDay(hour: 9, minute: 0);
    _end = e != null ? TimeOfDay.fromDateTime(e.endAt) : const TimeOfDay(hour: 11, minute: 0);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  // ---- Pickers ----------------------------------------------------------------

  Future<void> _pickImage() async {
    final picked = await pickImageWithSource(context, _picker, imageQuality: 85, maxWidth: 1600);
    if (picked != null) setState(() => _image = picked);
  }

  void _removeImage() => setState(() {
        _image = null;
        _imageUrl = null;
      });

  Future<void> _pickLocation() async {
    final result = await Navigator.push<ClinicSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage.pick(
          title: 'Event Location',
          initialName: _placeName,
          initialAddress: _addressFull,
          initialPlaceId: _placeId,
          initialLat: _lat,
          initialLng: _lng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      // Keep a label the admin typed themselves; replace one that was just
      // the previous place's name (or empty).
      final label = _location.text.trim();
      if (label.isEmpty || label == _placeName) _location.text = result.name;
      _placeName = result.name;
      _addressFull = result.address.isNotEmpty ? result.address : result.name;
      _placeId = result.placeId;
      _lat = result.lat;
      _lng = result.lng;
    });
  }

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

  // ---- Save -------------------------------------------------------------------

  /// Client-side checks; firestore.rules re-checks ownership and capacity.
  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Enter the event title.';
    if (_description.text.trim().isEmpty) return 'Enter a description.';
    // New events need a map pin; older text-only events may keep their
    // typed address until someone re-picks it.
    if (!_hasPin && (!_isEditing || _addressFull.trim().isEmpty)) return 'Pick the event location on the map.';
    if (_location.text.trim().isEmpty) return 'Enter the location label shown on event cards.';
    final startAt = _at(_start);
    if (!_at(_end).isAfter(startAt)) return 'End time must be after the start time.';
    if (!_isEditing && startAt.isBefore(DateTime.now())) return 'Choose a start time in the future.';
    final capacityText = _capacity.text.trim();
    if (capacityText.isNotEmpty) {
      final capacity = int.parse(capacityText);
      if (capacity <= 0) return 'Capacity must be at least 1.';
      final going = widget.existing?.goingCount ?? 0;
      if (capacity < going) return '$going people have already signed up — capacity can\'t be lower than that.';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final problem = _validate();
    if (problem != null) return showAdminSnack(context, problem, error: true);

    setState(() => _saving = true);
    try {
      final repo = ref.read(volunteerEventRepositoryProvider);
      var imageUrl = _imageUrl;
      if (_image != null) {
        imageUrl = await repo.uploadCoverImage(organizationId: widget.organizationId, filePath: _image!.path);
      }
      final organizerName = widget.existing?.organizerName ?? await _organizationName();
      final capacityText = _capacity.text.trim();
      final draft = VolunteerEvent(
        id: widget.existing?.id ?? '',
        organizationId: widget.organizationId,
        title: _title.text.trim(),
        description: _description.text.trim(),
        location: _location.text.trim(),
        addressFull: _addressFull.trim(),
        organizerName: organizerName,
        startAt: _at(_start),
        endAt: _at(_end),
        lat: _lat,
        lng: _lng,
        placeId: _placeId,
        imageUrl: imageUrl,
        capacity: capacityText.isEmpty ? null : int.parse(capacityText),
      );
      if (_isEditing) {
        await repo.updateEvent(eventId: widget.existing!.id, draft: draft);
      } else {
        await repo.createEvent(organizationId: widget.organizationId, draft: draft);
      }
      if (!mounted) return;
      showAdminSnack(context, _isEditing ? 'Changes saved.' : 'Event published.');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('[EventFormPage] save failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        showAdminSnack(context, 'Could not save the event.', error: true);
      }
    }
  }

  Future<String> _organizationName() async {
    final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
    final name = doc.data()?['name'] as String?;
    return (name == null || name.trim().isEmpty) ? 'Organization' : name.trim();
  }

  // ---- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final heading = _isEditing ? 'Edit Event' : 'Create New Event';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEditing ? 'Edit Event' : 'Events',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Center(child: Text(heading, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary))),
          const SizedBox(height: 8),
          Center(
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(text: '* ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                TextSpan(text: 'Required fields'),
              ]),
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Cover image ----------------------------------------------------
          const FieldLabel('Cover Image'),
          const SizedBox(height: 8),
          _coverPicker(),
          const SizedBox(height: 24),

          // ---- Event details --------------------------------------------------
          _sectionTitle('Event Details'),
          const FieldLabel('Event Title', required: true),
          _underlineField(_title, 'Enter'),
          const SizedBox(height: 18),
          const FieldLabel('Description', required: true),
          _underlineField(_description, 'What will volunteers do?', maxLines: 5),
          const SizedBox(height: 24),

          // ---- Location -------------------------------------------------------
          _sectionTitle('Location'),
          const FieldLabel('Address', required: true),
          const SizedBox(height: 8),
          _locationTile(),
          const SizedBox(height: 18),
          const FieldLabel('Location Label (shown on cards)', required: true),
          _underlineField(_location, 'e.g. General Trias, Cavite'),
          const SizedBox(height: 24),

          // ---- Schedule -------------------------------------------------------
          _sectionTitle('Schedule'),
          const FieldLabel('Date', required: true),
          _pickerRow(DateFormat('EEEE, MMMM d, y').format(_date), Icons.edit_calendar_outlined, _pickDate),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Starts', required: true),
                    _pickerRow(_start.format(context), Icons.access_time, () => _pickTime(start: true)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Ends', required: true),
                    _pickerRow(_end.format(context), Icons.access_time, () => _pickTime(start: false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ---- Capacity -------------------------------------------------------
          _sectionTitle('Sign-ups'),
          const FieldLabel('Capacity'),
          _underlineField(
            _capacity,
            'Leave blank for no limit',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          if (_isEditing && (widget.existing!.goingCount > 0))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Already signed up: ${widget.existing!.goingCount}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 32),

          Center(
            child: YellowPillButton(
              label: _isEditing ? 'Save Changes' : 'Publish Event',
              busy: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Divider(height: 1, color: AppColors.textPrimary.withValues(alpha: 0.15)),
          ],
        ),
      );

  Widget _underlineField(
    TextEditingController c,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
          isDense: true,
          border: const UnderlineInputBorder(),
        ),
      );

  Widget _pickerRow(String value, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
          child: Row(
            children: [
              Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary))),
              Icon(icon, size: 20, color: AppColors.textPrimary),
            ],
          ),
        ),
      );

  Widget _coverPicker() {
    final hasImage = _image != null || (_imageUrl != null && _imageUrl!.isNotEmpty);
    Widget preview;
    if (_image != null) {
      preview = Image.file(File(_image!.path), fit: BoxFit.cover);
    } else if (hasImage) {
      preview = CachedNetworkImage(
        imageUrl: _imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, color: AppColors.greenrspwn),
      );
    } else {
      preview = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined, size: 30, color: AppColors.greenrspwn),
          const SizedBox(height: 6),
          Text('Add a cover photo', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: hasImage ? 'Change cover image' : 'Choose cover image',
          child: GestureDetector(
            onTap: _saving ? null : _pickImage,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenrspwn, width: 1.5),
                ),
                child: preview,
              ),
            ),
          ),
        ),
        if (hasImage)
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined, size: 18, color: AppColors.textPrimary),
                label: Text('Change', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _removeImage,
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                label: Text('Remove', style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _locationTile() {
    final lat = _lat;
    final lng = _lng;
    final hasAddress = _addressFull.trim().isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lat != null && lng != null)
            SizedBox(
              height: 140,
              child: GoogleMap(
                // Rebuild the lite map when the pin moves.
                key: ValueKey('$lat,$lng'),
                initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 15),
                markers: {Marker(markerId: const MarkerId('event'), position: LatLng(lat, lng))},
                liteModeEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: hasAddress
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_hasPin && (_placeName ?? '').isNotEmpty && _placeName != _addressFull)
                              Text(_placeName!, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                            Text(_addressFull, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                            if (!_hasPin)
                              Text('No map pin yet — pick it on the map.',
                                  style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
                          ],
                        )
                      : Text('No location selected',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: _saving ? null : _pickLocation,
                  child: Text(_hasPin ? 'Change' : 'Pick on map',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
