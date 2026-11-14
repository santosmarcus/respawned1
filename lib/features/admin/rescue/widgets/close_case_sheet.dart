import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';

typedef CloseCaseResult = ({
ClosureReason reason,
String details,
String? serviceTypeNeeded,
});

/// Shared Close Case confirmation form — every allowed Close Case button
/// (Ongoing, Treatment, Intake, plus the Ownership section's Reunited
/// shortcut and the needsSpecializedAssistance exception buttons) opens
/// this SAME sheet, optionally with a pre-selected reason, rather than
/// building its own; the actual close write is
/// RescueCaseRepository.closeCase, called by the caller with this sheet's
/// result, once. Returns null if dismissed without confirming.
///
/// Reason list reduced to the 5 approved options
/// (ClosureReason.selectable) — Requires transport / Died / Aggressive /
/// Reunited / Rescued outside ResPAWnd. Nothing else is offered.
Future<CloseCaseResult?> showCloseCaseSheet(
    BuildContext context, {
      required RescueCase rescueCase,
      ClosureReason? initialReason,
    }) {
  return showReasonSheet<CloseCaseResult>(
    context,
    builder: (_) => _CloseCaseSheetBody(rescueCase: rescueCase, initialReason: initialReason),
  );
}

class _CloseCaseSheetBody extends StatefulWidget {
  final RescueCase rescueCase;
  final ClosureReason? initialReason;
  const _CloseCaseSheetBody({required this.rescueCase, this.initialReason});

  @override
  State<_CloseCaseSheetBody> createState() => _CloseCaseSheetBodyState();
}

class _CloseCaseSheetBodyState extends State<_CloseCaseSheetBody> {
  late ClosureReason? _reason = widget.initialReason;
  final _detailsController = TextEditingController();
  final _serviceTypeOtherController = TextEditingController();
  final _unusedOtherController = TextEditingController();
  String? _serviceType;

  // Common specialized-transport needs — kept short and concrete so the
  // next transporter (or the admin re-assigning one) knows exactly what to
  // bring/arrange, rather than a vague free-text guess.
  static const _serviceTypeOptions = [
    'Larger enclosed vehicle (van/truck)',
    'Secure crate/cage required',
    'Two-person handling required',
    'Climate-controlled transport',
    'Other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    _serviceTypeOtherController.dispose();
    _unusedOtherController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_reason == null || _detailsController.text.trim().isEmpty) return false;
    if (_reason!.needsServiceType) {
      if (_serviceType == null) return false;
      if (_serviceType == 'Other' && _serviceTypeOtherController.text.trim().isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    final hasActiveAssignment = c.assignedVolunteerName != null || (c.raw['currentAssignmentId'] as String?) != null;

    return ReasonSheetFrame(
      title: 'Close Case',
      confirmLabel: 'Close Case',
      onConfirm: _canConfirm
          ? () => Navigator.pop(
                context,
                (
                  reason: _reason!,
                  details: _detailsController.text.trim(),
                  serviceTypeNeeded: _reason!.needsServiceType
                      ? (_serviceType == 'Other' ? _serviceTypeOtherController.text.trim() : _serviceType)
                      : null,
                ),
              )
          : null,
      children: [
        // Pre-close summary.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Case ID', c.id),
              _summaryRow('Current phase', c.status.label),
              _summaryRow('Animals affected', '${c.animalCount}'),
              _summaryRow('Active transporter', c.assignedVolunteerName ?? 'None'),
              _summaryRow('Selected clinic', c.vetClinicName ?? 'None'),
            ],
          ),
        ),
        if (hasActiveAssignment) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Closing will cancel the pending/active transporter assignment, current route, and clinic destination.',
              style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFF9C6B10)),
            ),
          ),
        ],
        const ReasonSectionLabel('Closure Reason'),
        ReasonChoiceList<ClosureReason>(
          options: [for (final r in ClosureReason.selectable) ReasonOption(r, r.label)],
          selected: [?_reason],
          otherController: _unusedOtherController,
          onChanged: (v) => setState(() => _reason = v.first),
        ),
        const SizedBox(height: 8),
        ReasonTextField(
          controller: _detailsController,
          label: 'Detailed explanation',
          hint: 'What happened, and why the case is being closed',
          maxLines: 3,
          onChanged: () => setState(() {}),
        ),
        if (_reason?.needsServiceType ?? false) ...[
          const ReasonSectionLabel(
            'What kind of service does this animal need?',
            help: 'Shown on the case so whoever handles it next (or a re-assigned transporter) knows what to arrange.',
          ),
          ReasonChoiceList<String>(
            options: [for (final o in _serviceTypeOptions) ReasonOption(o, o, isOther: o == 'Other')],
            selected: [?_serviceType],
            otherController: _serviceTypeOtherController,
            otherHint: 'Describe the service needed',
            onChanged: (v) => setState(() => _serviceType = v.first),
            onOtherChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 130, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ],
    ),
  );
}
