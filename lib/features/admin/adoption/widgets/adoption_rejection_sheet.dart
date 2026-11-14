import 'package:flutter/material.dart';

import 'package:respawnd1/core/widgets/reason_picker.dart';

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

/// Rejection Reason sheet for an adoption application. Several reasons may
/// be chosen; "Other" needs an explanation, and extra notes are optional.
/// The explanation and notes are saved together as the rejection notes.
Future<AdoptionRejectionResult?> showAdoptionRejectionSheet(BuildContext context) async {
  final result = await showReasonPicker<String>(
    context,
    title: 'Rejection Reason',
    confirmLabel: 'Confirm Rejection',
    multiple: true,
    noteLabel: 'Additional notes',
    options: [for (final r in kAdoptionRejectionReasons) ReasonOption(r, r, isOther: r == 'Other')],
  );
  if (result == null) return null;
  final notes = [?result.otherText, ?result.note].join('\n\n');
  return AdoptionRejectionResult(reasons: result.values, notes: notes.isEmpty ? null : notes);
}
