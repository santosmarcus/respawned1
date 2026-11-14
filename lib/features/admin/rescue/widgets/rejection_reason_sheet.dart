import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';

typedef RejectionResult = ({RejectionReason reason, String? otherText});

/// Rejection Reason sheet for a rescue report. Returns null if dismissed,
/// otherwise the chosen reason (+ the typed text for [RejectionReason.other]).
Future<RejectionResult?> showRejectionReasonSheet(BuildContext context) async {
  final result = await showReasonPicker<RejectionReason>(
    context,
    title: 'Rejection Reason',
    confirmLabel: 'Confirm Rejection',
    options: [
      for (final r in RejectionReason.values)
        ReasonOption(r, r.label, isOther: r == RejectionReason.other),
    ],
  );
  if (result == null) return null;
  return (reason: result.value, otherText: result.otherText);
}
