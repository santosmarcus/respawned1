import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

const List<String> kAdoptionRejectionReasons = [
  'Housing not suitable',
  'Financial concerns',
  'Unable to verify information',
  'Animal not a good match',
  'Incomplete application',
  'Failed interview',
  'Animal not available',
  'Duplicate application',
  'Other',
];

class AdoptionRejectionResult {
  final List<String> reasons;
  final String? notes;
  const AdoptionRejectionResult({required this.reasons, this.notes});
}

/// Checkboxes (multiple reasons allowed) + required notes when "Other" is
/// checked — matches the supplied Rejection Reason design.
Future<AdoptionRejectionResult?> showAdoptionRejectionSheet(BuildContext context) {
  return showModalBottomSheet<AdoptionRejectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _AdoptionRejectionSheetBody(),
  );
}

class _AdoptionRejectionSheetBody extends StatefulWidget {
  const _AdoptionRejectionSheetBody();

  @override
  State<_AdoptionRejectionSheetBody> createState() => _AdoptionRejectionSheetBodyState();
}

class _AdoptionRejectionSheetBodyState extends State<_AdoptionRejectionSheetBody> {
  final Set<String> _selected = {};
  final _notesController = TextEditingController();
  String? _error;

  bool get _requiresNotes => _selected.contains('Other');

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one reason.');
      return;
    }
    if (_requiresNotes && _notesController.text.trim().isEmpty) {
      setState(() => _error = 'Notes are required when "Other" is selected.');
      return;
    }
    Navigator.pop(
      context,
      AdoptionRejectionResult(
        reasons: _selected.toList(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
              Text('Rejection Reason', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              for (final reason in kAdoptionRejectionReasons)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  value: _selected.contains(reason),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(reason);
                    } else {
                      _selected.remove(reason);
                    }
                    _error = null;
                  }),
                ),
              if (_requiresNotes) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Required notes for "Other"', isDense: true),
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                ),
              ] else ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Additional notes (optional)', isDense: true),
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE05353),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Confirm Rejection', style: GoogleFonts.tiltWarp(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
