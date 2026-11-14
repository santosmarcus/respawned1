import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';

/// The transporter's "End Reason" sheet. Returns what was picked once
/// Confirm is tapped, or null when cancelled.
Future<EndReasonSelection?> showCloseTransitDialog(BuildContext context) {
  return showReasonSheet<EndReasonSelection>(context, builder: (_) => const _EndReasonSheet());
}

class _EndReasonSheet extends StatefulWidget {
  const _EndReasonSheet();

  @override
  State<_EndReasonSheet> createState() => _EndReasonSheetState();
}

class _EndReasonSheetState extends State<_EndReasonSheet> {
  String? _reason;
  String? _serviceType;
  bool _searchedTenMinutes = false;
  final _other = TextEditingController();
  final _notes = TextEditingController();
  final _serviceTypeOther = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    _notes.dispose();
    _serviceTypeOther.dispose();
    super.dispose();
  }

  bool get _needsSearchConfirm => _reason == kEndReasonNotFound;
  bool get _needsServiceType => _reason == kEndReasonSpecializedTransport;
  bool get _needsNotes =>
      _reason == kEndReasonNotFound || _reason == kEndReasonReporterUnreachable || _reason == kEndReasonAggressive;

  bool get _canConfirm =>
      _reason != null &&
      (_reason != kEndReasonOther || _other.text.trim().isNotEmpty) &&
      (!_needsSearchConfirm || _searchedTenMinutes) &&
      (!_needsServiceType ||
          (_serviceType != null && (_serviceType != 'Other' || _serviceTypeOther.text.trim().isNotEmpty)));

  void _confirm() {
    Navigator.pop(
      context,
      EndReasonSelection(
        reason: _reason!,
        otherText: _reason == kEndReasonOther ? _other.text.trim() : null,
        notes: _notes.text.trim(),
        serviceType: _needsServiceType
            ? (_serviceType == 'Other' ? _serviceTypeOther.text.trim() : _serviceType)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aggressive = _reason == kEndReasonAggressive;
    return ReasonSheetFrame(
      title: 'End Reason',
      confirmLabel: 'Confirm',
      onConfirm: _canConfirm ? _confirm : null,
      children: [
        ReasonChoiceList<String>(
          options: [for (final r in kEndReasons) ReasonOption(r, r, isOther: r == kEndReasonOther)],
          selected: [?_reason],
          otherController: _other,
          onChanged: (v) => setState(() => _reason = v.first),
          onOtherChanged: () => setState(() {}),
        ),
        if (_needsSearchConfirm) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _searchedTenMinutes,
              activeColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.textPrimary),
              title: Text(
                'I waited and searched the immediate area for at least 10 minutes and could not locate the animal.',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
              ),
              onChanged: (v) => setState(() => _searchedTenMinutes = v ?? false),
            ),
          ),
        ],
        if (_needsNotes) ...[
          ReasonSectionLabel(aggressive ? 'Describe the animal\'s behavior' : 'Notes (what did you observe?)'),
          ReasonTextField(
            controller: _notes,
            label: aggressive ? 'Behavior' : 'Notes',
            hint: aggressive
                ? 'e.g. "Lunging and growling, could not be safely restrained."'
                : 'e.g. "Neighbors said the dog left 30 minutes ago."',
            maxLines: 3,
          ),
        ],
        if (_needsServiceType) ...[
          const ReasonSectionLabel(
            'What kind of service does this animal need?',
            help: 'This is shown to the org so they can arrange the right transporter or vehicle.',
          ),
          ReasonChoiceList<String>(
            options: [for (final o in kSpecializedServiceTypes) ReasonOption(o, o, isOther: o == 'Other')],
            selected: [?_serviceType],
            otherController: _serviceTypeOther,
            otherHint: 'Describe the service needed',
            onChanged: (v) => setState(() => _serviceType = v.first),
            onOtherChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }
}

/// The transporter's in-person check before an adopter hand-off. Returns
/// true only for "Yes, confirm".
Future<bool> showConfirmAdopterPickupDialog(BuildContext context) {
  return showConfirmActionDialog(
    context,
    title: 'Confirm Adopter Pickup',
    message: 'Is the interested adopter actually here, in person, ready to take the animal?',
    confirmLabel: 'Yes, confirm',
    cancelLabel: 'Not yet',
  );
}
