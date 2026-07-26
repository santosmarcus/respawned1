import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

Future<void> showAddVaccineRecordSheet(BuildContext context, {required AnimalRecord animal}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddVaccineRecordSheetBody(animal: animal),
  );
}

class _AddVaccineRecordSheetBody extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const _AddVaccineRecordSheetBody({required this.animal});

  @override
  ConsumerState<_AddVaccineRecordSheetBody> createState() => _AddVaccineRecordSheetBodyState();
}

class _AddVaccineRecordSheetBodyState extends ConsumerState<_AddVaccineRecordSheetBody> {
  late List<VaccineTemplate> _templates = VaccineTemplate.forSpecies(widget.animal.species);
  VaccineTemplate? _selectedTemplate;
  final _customNameController = TextEditingController();
  final _validityController = TextEditingController(text: '365');
  DateTime _dateAdministered = DateTime.now();
  DateTime? _nextDueOverride;
  final _clinicController = TextEditingController();
  final _batchController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  String get _vaccineName => _selectedTemplate?.name ?? _customNameController.text.trim();

  DateTime get _computedNextDue {
    if (_nextDueOverride != null) return _nextDueOverride!;
    final days = int.tryParse(_validityController.text.trim()) ?? 365;
    return _dateAdministered.add(Duration(days: days));
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _validityController.dispose();
    _clinicController.dispose();
    _batchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Same vaccine name + same administration date = the same event already
  /// recorded — blocked. A later (or earlier) date for the same vaccine
  /// name is a legitimate booster/separate dose and stays allowed.
  bool _isDuplicateEvent(List<VaccinationRecord> existing) {
    return existing.any((r) =>
        r.vaccineName.trim().toLowerCase() == _vaccineName.trim().toLowerCase() &&
        r.dateAdministered.year == _dateAdministered.year &&
        r.dateAdministered.month == _dateAdministered.month &&
        r.dateAdministered.day == _dateAdministered.day);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_vaccineName.isEmpty) {
      setState(() => _error = 'Select a vaccine or enter a name.');
      return;
    }
    final validityDays = int.tryParse(_validityController.text.trim());
    if (validityDays == null || validityDays <= 0) {
      setState(() => _error = 'Enter a valid duration in days.');
      return;
    }
    final existing = ref.read(vaccinationsProvider(widget.animal.id)).asData?.value ?? const <VaccinationRecord>[];
    if (_isDuplicateEvent(existing)) {
      setState(() => _error =
          'A "$_vaccineName" record for ${_dateAdministered.month}/${_dateAdministered.day}/${_dateAdministered.year} already exists. '
          'Pick a different date if this is a booster or separate dose.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final record = VaccinationRecord(
        id: '',
        animalId: widget.animal.id,
        vaccineName: _vaccineName,
        species: widget.animal.species,
        dateAdministered: _dateAdministered,
        validityDurationDays: validityDays,
        nextDueDate: _computedNextDue,
        clinicOrProvider: _clinicController.text.trim().isEmpty ? null : _clinicController.text.trim(),
        batchOrLotNumber: _batchController.text.trim().isEmpty ? null : _batchController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdBy: 'Admin Staff',
      );
      await ref.read(animalRecordRepositoryProvider).addVaccination(animalId: widget.animal.id, record: record);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save vaccination: $e';
        });
      }
    }
  }

  void _showExistingRecords(List<VaccinationRecord> records, String vaccineName) {
    final matches = records.where((r) => r.vaccineName.trim().toLowerCase() == vaccineName.trim().toLowerCase()).toList()
      ..sort((a, b) => b.dateAdministered.compareTo(a.dateAdministered));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('$vaccineName — already added', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in matches) ...[
                Text(
                  'Last administered: ${r.dateAdministered.month}/${r.dateAdministered.day}/${r.dateAdministered.year}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                ),
                Text('Validity: ${r.validityDurationDays} days', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                Text('Next due: ${r.nextDueDate.month}/${r.nextDueDate.day}/${r.nextDueDate.year}',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
              ],
              Text(
                'You may still add this vaccine again with a different administration date (booster/new dose).',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedTemplate = VaccineTemplate.forSpecies(widget.animal.species)
                    .where((t) => t.name.toLowerCase() == vaccineName.toLowerCase())
                    .cast<VaccineTemplate?>()
                    .firstWhere((t) => true, orElse: () => null);
                if (_selectedTemplate == null) _customNameController.text = vaccineName;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
            child: const Text('Add Another Dose'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingRecords = ref.watch(vaccinationsProvider(widget.animal.id)).asData?.value ?? const <VaccinationRecord>[];
    final addedNames = existingRecords.map((r) => r.vaccineName.trim().toLowerCase()).toSet();
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Add Vaccine Record', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Text('Vaccine', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Chips marked "Added" already have a record — tap the ⓘ to view it. To add a booster, use "Other" with a new date.',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _templates)
                  _VaccineChip(
                    label: t.name,
                    added: addedNames.contains(t.name.toLowerCase()),
                    selected: _selectedTemplate?.name == t.name,
                    onTapAdded: () => _showExistingRecords(existingRecords, t.name),
                    onSelect: () => setState(() {
                      _selectedTemplate = t;
                      _validityController.text = '${t.defaultValidityDays}';
                      _nextDueOverride = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Other'),
                  selected: _selectedTemplate == null,
                  selectedColor: AppColors.yellowrspwn,
                  onSelected: (_) => setState(() => _selectedTemplate = null),
                ),
              ],
            ),
            if (_selectedTemplate == null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customNameController,
                decoration: const InputDecoration(hintText: 'Vaccine name', isDense: true),
                style: GoogleFonts.zain(fontSize: 14),
              ),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Date Administered',
                    date: _dateAdministered,
                    onPick: (d) => setState(() => _dateAdministered = d),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Validity (days)', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      TextField(
                        controller: _validityController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _nextDueOverride = null),
                        decoration: const InputDecoration(isDense: true),
                        style: GoogleFonts.zain(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            _DateField(
              label: 'Next Due Date (override, optional)',
              date: _computedNextDue,
              onPick: (d) => setState(() => _nextDueOverride = d),
            ),
            const SizedBox(height: 6),
            Text('Confirm the renewal schedule with the attending veterinarian.',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),

            const SizedBox(height: 14),
            TextField(
              controller: _clinicController,
              decoration: const InputDecoration(hintText: 'Clinic / provider (optional)', isDense: true),
              style: GoogleFonts.zain(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _batchController,
              decoration: const InputDecoration(hintText: 'Batch / lot number (optional)', isDense: true),
              style: GoogleFonts.zain(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Notes (optional)', isDense: true),
              style: GoogleFonts.zain(fontSize: 14),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Save Vaccine Record', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vaccine option chip that's either plain-selectable (never recorded
/// yet) or marked "Added" (at least one record already exists). An Added
/// chip uses the exact same yellow the app already uses for a selected
/// chip elsewhere — never a separate warning/error color — and is
/// otherwise inert: the chip body itself has no tap handler, so it can't
/// be mistaken for participating in vaccine selection. Its prior record
/// is still reachable, just via a separate small info affordance rather
/// than the chip acting pressable; a legitimate booster is added through
/// the normal flow (pick the "Other" chip, or wait for a future dose —
/// the duplicate check is keyed on name+date, not on this chip).
class _VaccineChip extends StatelessWidget {
  final String label;
  final bool added;
  final bool selected;
  final VoidCallback onTapAdded;
  final VoidCallback onSelect;
  const _VaccineChip({
    required this.label,
    required this.added,
    required this.selected,
    required this.onTapAdded,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (!added) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.yellowrspwn,
        onSelected: (_) => onSelect(),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          Text('Added', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onTapAdded,
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.info_outline, size: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  const _DateField({required this.label, required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
            );
            if (picked != null) onPick(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${date.month}/${date.day}/${date.year}', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                const Icon(Icons.calendar_today_outlined, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
