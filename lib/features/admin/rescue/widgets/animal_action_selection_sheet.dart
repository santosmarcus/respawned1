import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';

/// "Select animals for Intake/Transfer/Release" (spec §8) — shown before
/// any post-treatment action opens its own destination flow, so an action
/// is always applied to specific discharged animals rather than the whole
/// case. Only ever opened for a case that actually has an `animals[]`
/// array (a legacy single-animal case has nothing to disambiguate and
/// skips straight to the existing whole-case flow — see
/// TreatmentDetailPage._startPostTreatmentAction).
///
/// Returns the confirmed set of animal-array indexes, or null if the admin
/// cancelled.
Future<Set<int>?> showAnimalActionSelectionSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required String actionLabel, // 'Intake' | 'Transfer' | 'Release'
  required List<CaseAnimalOption> animalOptions,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AnimalActionSelectionSheetBody(
      rescueCase: rescueCase,
      actionLabel: actionLabel,
      animalOptions: animalOptions,
    ),
  );
}

class _AnimalActionSelectionSheetBody extends StatefulWidget {
  final RescueCase rescueCase;
  final String actionLabel;
  final List<CaseAnimalOption> animalOptions;

  const _AnimalActionSelectionSheetBody({
    required this.rescueCase,
    required this.actionLabel,
    required this.animalOptions,
  });

  @override
  State<_AnimalActionSelectionSheetBody> createState() => _AnimalActionSelectionSheetBodyState();
}

class _AnimalActionSelectionSheetBodyState extends State<_AnimalActionSelectionSheetBody> {
  final Set<int> _selected = {};

  String _statusLabelFor(int index) {
    final c = widget.rescueCase;
    if (animalIsDeceased(c, index)) return 'Deceased';
    if (!animalIsDischarged(c, index)) return 'Still in treatment';
    final action = animalPostTreatmentAction(c, index);
    if (action != null) {
      final label = switch (action) {
        'intake' => 'Intake',
        'transfer' => 'Transfer',
        'release' => 'Release',
        _ => action,
      };
      return 'Already in $label';
    }
    return 'Discharged';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
          Text('Select animals for ${widget.actionLabel}',
              style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Only discharged animals can be selected.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final o in widget.animalOptions)
                    _AnimalCheckRow(
                      label: o.label,
                      statusLabel: _statusLabelFor(o.index),
                      eligible: animalEligibleForNewAction(c, o.index),
                      selected: _selected.contains(o.index),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _selected.add(o.index);
                        } else {
                          _selected.remove(o.index);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Cancel', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    disabledBackgroundColor: AppColors.slaterspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Continue', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimalCheckRow extends StatelessWidget {
  final String label;
  final String statusLabel;
  final bool eligible;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _AnimalCheckRow({
    required this.label,
    required this.statusLabel,
    required this.eligible,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: eligible ? 1 : 0.5,
      child: InkWell(
        onTap: eligible ? () => onChanged(!selected) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: eligible ? (v) => onChanged(v ?? false) : null,
                activeColor: AppColors.yellowrspwn,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('— $statusLabel', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
