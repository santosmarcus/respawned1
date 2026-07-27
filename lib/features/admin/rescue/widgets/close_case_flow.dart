import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/animal_action_selection_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// `acted`: false if the admin cancelled/dismissed the flow before any
/// write happened. `wholeCaseClosed`: only meaningful when `acted` is true
/// — true once the case itself became terminal, false when only specific
/// animal(s) were marked deceased while the case stays active (spec §13's
/// "Animal 1 died, Animal 2 remains in Treatment" example). Callers use
/// this to decide whether popping back to Rescue history is correct, or
/// whether they should stay on the current page because the case is still
/// open for its other animals.
typedef CloseCaseOutcome = ({bool acted, bool wholeCaseClosed});

const _notActed = (acted: false, wholeCaseClosed: false);

/// The ONE call path into RescueCaseRepository.closeCase — every controlled
/// Close Case button (Ongoing, Treatment, Intake, the Ownership section's
/// preset-reason shortcuts, the needsSpecializedAssistance exception
/// buttons) calls this instead of each page hand-rolling its own
/// sheet-then-repository sequence. Never navigates itself — the caller
/// decides what happens after [CloseCaseOutcome.acted]/[wholeCaseClosed].
Future<CloseCaseOutcome> performCloseCase(
  BuildContext context,
  WidgetRef ref,
  RescueCase rescueCase, {
  ClosureReason? initialReason,
}) async {
  final result = await showCloseCaseSheet(
    context,
    rescueCase: rescueCase,
    initialReason: initialReason,
  );
  if (result == null) return _notActed;

  // Death is the only reason with a genuine per-animal outcome (spec §2/
  // §13) — only ask which animal(s) when the case actually has more than
  // one to disambiguate; a legacy/single-animal case skips straight to the
  // whole-case write, same as every other reason.
  Set<int>? animalIndexes;
  if (result.reason.isDeathReason && rescueCase.animals.length > 1) {
    if (!context.mounted) return _notActed;
    final options = buildCaseAnimalOptions(rescueCase);
    animalIndexes = await showAnimalActionSelectionSheet(
      context,
      rescueCase: rescueCase,
      actionLabel: 'Close Case',
      animalOptions: options,
    );
    if (animalIndexes == null || animalIndexes.isEmpty) return _notActed;
  }

  if (!context.mounted) return _notActed;
  final confirmed = await showConfirmActionDialog(
    context,
    title: 'Are you sure?',
    message: result.reason.isDeathReason && animalIndexes != null
        ? 'This will record the selected animal outcome as deceased. The case will close only if every animal is resolved.'
        : 'This will close the case as "${result.reason.label}". The case and its complete history will be preserved.',
    confirmLabel: 'Confirm Closure',
  );
  if (!confirmed) return _notActed;

  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
  final actorName = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : 'Admin Staff';
  String? actorRole;
  String? organizationId;
  if (uid.isNotEmpty) {
    try {
      final membership = await ref
          .read(orgMembershipServiceProvider)
          .getMembership(uid);
      actorRole = membership?.role.name;
      organizationId = membership?.organizationId;
    } catch (_) {
      // Best-effort only — a lookup failure never blocks closing the case,
      // it just leaves the audit role/org fields unset for this entry.
    }
  }

  final wholeCaseClosed = await ref
      .read(rescueCaseRepositoryProvider)
      .closeCase(
        caseId: rescueCase.id,
        reason: result.reason,
        details: result.details,
        actorUid: uid,
        actorName: actorName,
        actorRole: actorRole,
        organizationId: organizationId,
        lastKnownLocation: result.lastKnownLocation,
        clinicUnavailableDetails: result.clinicUnavailableDetails,
        serviceTypeNeeded: result.serviceTypeNeeded,
        animalIndexes: animalIndexes?.toList(),
      );
  return (acted: true, wholeCaseClosed: wholeCaseClosed);
}
