import 'package:flutter/material.dart';

import 'package:respawnd1/core/widgets/reason_picker.dart';

const List<String> kTreatmentRejectReasons = [
  'Clinic at full capacity',
  'Insufficient Medication/Treatment Supplies',
  'Require specialist care/equipment this clinic does not have',
  'Animal Deceased',
  'No Veterinarian/Specialist Available',
  'Other',
];

/// "Treatment Rejected" reason picker shown at the clinic. Resolves to the
/// chosen reason (or the typed explanation for "Other"), or null if
/// cancelled.
Future<String?> showTreatmentRejectDialog(BuildContext context) async {
  final result = await showReasonPicker<String>(
    context,
    title: 'Treatment Rejected',
    subtitle: 'Why did the clinic turn the animal away?',
    options: [for (final r in kTreatmentRejectReasons) ReasonOption(r, r, isOther: r == 'Other')],
  );
  if (result == null) return null;
  return result.otherText ?? result.value;
}
