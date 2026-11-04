import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';

String _actorName() {
  final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
  return (name != null && name.isNotEmpty) ? name : 'Admin Staff';
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );

Future<void> _showSheet(BuildContext context, Widget body) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => body,
    );

/// Deworming, flea & tick or a vet checkup given while the animal is in the
/// shelter — no treatment episode needed. Past dates are allowed so older
/// paper records can be entered too.
Future<void> showAddCareRecordSheet(BuildContext context, {required AnimalRecord animal, CareType? initialType}) =>
    _showSheet(context, _AddCareRecordBody(animal: animal, initialType: initialType ?? CareType.deworming));

/// Several past entries at once (vaccines, deworming, flea & tick,
/// checkups) for backfilling an animal's outdated health history. Next-due
/// dates use the usual suggested intervals; individual records can be added
/// with the detailed forms when a vet gave a different schedule.
Future<void> showPastHealthHistorySheet(BuildContext context, {required AnimalRecord animal}) =>
    _showSheet(context, _PastHistoryBody(animal: animal));

class _AddCareRecordBody extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  final CareType initialType;
  const _AddCareRecordBody({required this.animal, required this.initialType});

  @override
  ConsumerState<_AddCareRecordBody> createState() => _AddCareRecordBodyState();
}

class _AddCareRecordBodyState extends ConsumerState<_AddCareRecordBody> {
  late CareType _type = widget.initialType;
  DateTime _dateGiven = DateTime.now();
  DateTime? _nextDueOverride;
  bool _noNextDue = false;
  final _productController = TextEditingController();
  final _providerController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  DateTime get _nextDue => _nextDueOverride ?? _dateGiven.add(Duration(days: _type.defaultIntervalDays));

  @override
  void dispose() {
    _productController.dispose();
    _providerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_noNextDue && !_nextDue.isAfter(_dateGiven)) {
      setState(() => _error = 'The next due date must be after the date given.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await ref.read(animalRecordRepositoryProvider).addCareRecord(
            animalId: widget.animal.id,
            record: CareRecord(
              id: '',
              animalId: widget.animal.id,
              type: _type,
              dateGiven: _dateGiven,
              nextDueDate: _noNextDue ? null : _nextDue,
              product: text(_productController),
              provider: text(_providerController),
              notes: text(_notesController),
              createdBy: _actorName(),
            ),
            actorId: user?.uid,
            actorEmail: user?.email,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCheckup = _type == CareType.vetCheckup;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Handle(),
            Text('Add Preventive Care', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in CareType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    selectedColor: AppColors.yellowrspwn,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _nextDueOverride = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _DateRow(
              label: isCheckup ? 'Visit date' : 'Date given',
              date: _dateGiven,
              onPick: (d) => setState(() => _dateGiven = d),
            ),
            const SizedBox(height: 12),
            if (!_noNextDue)
              _DateRow(
                label: isCheckup ? 'Next follow-up visit' : 'Next dose due',
                date: _nextDue,
                onPick: (d) => setState(() => _nextDueOverride = d),
              ),
            CheckboxListTile(
              value: _noNextDue,
              onChanged: (v) => setState(() => _noNextDue = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(isCheckup ? 'No follow-up needed' : 'No further dose scheduled',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
            ),
            Text(
              'Suggested: every ${_type.defaultIntervalDays} days. Confirm the schedule with the attending veterinarian.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            if (!isCheckup)
              TextField(
                controller: _productController,
                decoration: const InputDecoration(hintText: 'Product / dose (optional)', isDense: true),
                style: GoogleFonts.zain(fontSize: 14),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _providerController,
              decoration: InputDecoration(
                  hintText: isCheckup ? 'Clinic / veterinarian (optional)' : 'Given by (optional)', isDense: true),
              style: GoogleFonts.zain(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                  hintText: isCheckup ? 'Findings / instructions (optional)' : 'Notes (optional)', isDense: true),
              style: GoogleFonts.zain(fontSize: 14),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],
            const SizedBox(height: 18),
            _SaveButton(label: 'Save ${_type.label}', saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ---- Past health history (bulk backfill) ------------------------------------

/// One line of the backfill form: either a vaccine (by name) or a care type.
class _HistoryRow {
  String? vaccineName;
  CareType? careType;
  DateTime date = DateTime.now();

  bool get isSet => vaccineName != null || careType != null;
  String get key => vaccineName != null ? 'v:$vaccineName' : 'c:${careType?.name}';
}

class _PastHistoryBody extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const _PastHistoryBody({required this.animal});

  @override
  ConsumerState<_PastHistoryBody> createState() => _PastHistoryBodyState();
}

class _PastHistoryBodyState extends ConsumerState<_PastHistoryBody> {
  final List<_HistoryRow> _rows = [_HistoryRow()];
  bool _saving = false;
  String? _error;

  late final List<VaccineTemplate> _vaccines = VaccineTemplate.forSpecies(widget.animal.species);

  List<DropdownMenuItem<String>> get _options => [
        for (final v in _vaccines) DropdownMenuItem(value: 'v:${v.name}', child: Text('Vaccine · ${v.name}')),
        for (final c in CareType.values) DropdownMenuItem(value: 'c:${c.name}', child: Text(c.label)),
      ];

  void _setKind(_HistoryRow row, String? key) {
    setState(() {
      row.vaccineName = null;
      row.careType = null;
      if (key == null) return;
      if (key.startsWith('v:')) {
        row.vaccineName = key.substring(2);
      } else {
        row.careType = CareType.fromName(key.substring(2));
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final rows = _rows.where((r) => r.isSet).toList();
    if (rows.isEmpty) {
      setState(() => _error = 'Add at least one entry.');
      return;
    }
    if (rows.any((r) => r.date.isAfter(DateTime.now()))) {
      setState(() => _error = 'Past entries can\'t be dated in the future.');
      return;
    }
    // Same item on the same day = already recorded (matches the vaccine
    // sheet's own duplicate rule), whether on file or twice in this form.
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final vaccines = ref.read(vaccinationsProvider(widget.animal.id)).asData?.value ?? const <VaccinationRecord>[];
    final care = ref.read(careRecordsProvider(widget.animal.id)).asData?.value ?? const <CareRecord>[];
    final seen = <String>{};
    for (final r in rows) {
      final dayKey = '${r.key}@${_fmt(r.date)}';
      final onFile = r.vaccineName != null
          ? vaccines.any((v) => v.vaccineName.toLowerCase() == r.vaccineName!.toLowerCase() && sameDay(v.dateAdministered, r.date))
          : care.any((c) => c.type == r.careType && sameDay(c.dateGiven, r.date));
      if (onFile || !seen.add(dayKey)) {
        setState(() => _error =
            '${r.vaccineName ?? r.careType!.label} on ${_fmt(r.date)} is already recorded. Remove that line or change its date.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(animalRecordRepositoryProvider);
    final user = FirebaseAuth.instance.currentUser;
    final actor = _actorName();
    var saved = 0;
    try {
      for (final row in rows) {
        if (row.vaccineName != null) {
          final days = _vaccines
              .firstWhere((v) => v.name == row.vaccineName, orElse: () => _vaccines.first)
              .defaultValidityDays;
          await repo.addVaccination(
            animalId: widget.animal.id,
            record: VaccinationRecord(
              id: '',
              animalId: widget.animal.id,
              vaccineName: row.vaccineName!,
              species: widget.animal.species,
              dateAdministered: row.date,
              validityDurationDays: days,
              nextDueDate: row.date.add(Duration(days: days)),
              notes: 'Entered from past records',
              createdBy: actor,
            ),
            actorId: user?.uid,
            actorEmail: user?.email,
          );
        } else {
          final type = row.careType!;
          await repo.addCareRecord(
            animalId: widget.animal.id,
            record: CareRecord(
              id: '',
              animalId: widget.animal.id,
              type: type,
              dateGiven: row.date,
              nextDueDate: row.date.add(Duration(days: type.defaultIntervalDays)),
              notes: 'Entered from past records',
              createdBy: actor,
            ),
            actorId: user?.uid,
            actorEmail: user?.email,
          );
        }
        saved++;
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          // Entries already written stay saved; only the rest need redoing.
          final done = rows.take(saved).toSet();
          _rows.removeWhere(done.contains);
          _error = 'Saved $saved of ${rows.length}. Could not save the rest: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Handle(),
            Text('Add Past Health Records', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Enter what the paper records show, one line per dose or visit. Next due dates use the usual intervals.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_rows[i].isSet ? _rows[i].key : null),
                        initialValue: _rows[i].isSet ? _rows[i].key : null,
                        isExpanded: true,
                        hint: Text('What was given', style: GoogleFonts.zain(fontSize: 13)),
                        items: _options,
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (v) => _setKind(_rows[i], v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _DateRow(
                        label: 'Date',
                        date: _rows[i].date,
                        onPick: (d) => setState(() => _rows[i].date = d),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove line',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                      onPressed: _rows.length == 1 ? null : () => setState(() => _rows.removeAt(i)),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_HistoryRow())),
              icon: const Icon(Icons.add, size: 16, color: AppColors.textPrimary),
              label: Text('Add line',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],
            const SizedBox(height: 14),
            _SaveButton(
              label: 'Save ${_rows.where((r) => r.isSet).length} record(s)',
              saving: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Shared bits ---------------------------------------------------------------

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  const _DateRow({required this.label, required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        InkWell(
          onTap: () async {
            final picked = await _pickDate(context, date);
            if (picked != null) onPick(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(date), style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                const Icon(Icons.calendar_today_outlined, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback onPressed;
  const _SaveButton({required this.label, required this.saving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: saving
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
            : Text(label, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
      ),
    );
  }
}
