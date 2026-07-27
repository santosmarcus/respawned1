import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

/// Structured health-detail editing (spec section 6) — separate from the
/// main Animal Record form since these fields change far more often than a
/// profile edit and shouldn't require reopening that whole form. Never
/// touches `vaccinated` (that's derived from vaccination records, see
/// AnimalRecordRepository._refreshVaccineSummary).
Future<void> showHealthDetailsSheet(BuildContext context, {required AnimalRecord animal}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _HealthDetailsSheetBody(animal: animal),
  );
}

class _HealthDetailsSheetBody extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const _HealthDetailsSheetBody({required this.animal});

  @override
  ConsumerState<_HealthDetailsSheetBody> createState() => _HealthDetailsSheetBodyState();
}

class _HealthDetailsSheetBodyState extends ConsumerState<_HealthDetailsSheetBody> {
  late bool? _sterilized = widget.animal.health.sterilized;
  late bool? _dewormed = widget.animal.health.dewormed;
  late final _allergiesController = TextEditingController(text: widget.animal.health.allergies ?? '');
  late final _chronicController = TextEditingController(text: widget.animal.health.chronicConditions ?? '');
  late final _medsController = TextEditingController(text: widget.animal.health.currentMedications ?? '');
  late final _weightController =
      TextEditingController(text: widget.animal.health.weightKg != null ? '${widget.animal.health.weightKg}' : '');
  late final _bodyConditionController = TextEditingController(text: widget.animal.health.bodyCondition ?? '');
  late final _microchipController = TextEditingController(text: widget.animal.health.microchipStatus ?? '');
  late DateTime? _lastCheckup = widget.animal.health.lastVetCheckup;
  bool _saving = false;

  @override
  void dispose() {
    _allergiesController.dispose();
    _chronicController.dispose();
    _medsController.dispose();
    _weightController.dispose();
    _bodyConditionController.dispose();
    _microchipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(animalRecordRepositoryProvider).updateHealthDetails(
            animalId: widget.animal.id,
            spayedNeutered: _sterilized,
            dewormed: _dewormed,
            allergies: _allergiesController.text.trim(),
            chronicConditions: _chronicController.text.trim(),
            currentMedications: _medsController.text.trim(),
            lastVetCheckup: _lastCheckup,
            weightKg: double.tryParse(_weightController.text.trim()),
            bodyCondition: _bodyConditionController.text.trim(),
            microchipStatus: _microchipController.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save medical profile: $e'), backgroundColor: Colors.redAccent),
        );
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Edit Medical Profile', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            _TriStateRow(label: 'Spay/Neuter Status', value: _sterilized, onChanged: (v) => setState(() => _sterilized = v)),
            _TriStateRow(label: 'Deworming Status', value: _dewormed, onChanged: (v) => setState(() => _dewormed = v)),

            const SizedBox(height: 8),
            _Field('Known Allergies', _allergiesController),
            _Field('Chronic Conditions', _chronicController),
            _Field('Current Medications', _medsController),
            _Field('Weight (kg)', _weightController, keyboardType: TextInputType.number),
            _Field('Body Condition', _bodyConditionController),
            _Field('Identification Tag Status', _microchipController),

            const SizedBox(height: 6),
            Text('Last Veterinary Checkup', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _lastCheckup ?? DateTime.now(),
                  firstDate: DateTime(2010),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _lastCheckup = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_lastCheckup == null ? 'Not set' : '${_lastCheckup!.month}/${_lastCheckup!.day}/${_lastCheckup!.year}',
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                    const Icon(Icons.calendar_today_outlined, size: 14),
                  ],
                ),
              ),
            ),

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
                    : Text('Save Medical Profile', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  const _Field(this.label, this.controller, {this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: const InputDecoration(hintText: 'Unknown / not provided', isDense: true),
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _TriStateRow extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  const _TriStateRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Label above the selector (not side-by-side) — a Row with a label
    // like "Deworming status" plus a 3-segment Unknown/No/Yes button had no
    // Expanded/Flexible on either side, so it overflowed horizontally on
    // narrow screens ("RIGHT OVERFLOWED BY ... PIXELS"). Stacking instead
    // of squeezing them onto one line fixes that at any width.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool?>(
              segments: const [
                ButtonSegment(value: null, label: Text('Unknown')),
                ButtonSegment(value: false, label: Text('No')),
                ButtonSegment(value: true, label: Text('Yes')),
              ],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}
