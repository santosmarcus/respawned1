// Split out of transit_progress_page.dart (behavior-preserving refactor).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';

InputDecoration _fieldDecoration(String hint, {double hintSize = 12}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.zain(
      fontSize: hintSize,
      color: AppColors.textSecondary,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.slaterspwn),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.textPrimary),
    ),
  );
}

/// The transporter's "End Reason" dialog. Returns what was picked once
/// Confirm is tapped, or null when closed with the X.
Future<EndReasonSelection?> showCloseTransitDialog(BuildContext context) async {
  String? selectedReason;
  String? other;
  String? serviceType;
  bool searchedTenMinutes = false;
  final notesCtrl = TextEditingController();
  final serviceTypeOtherCtrl = TextEditingController();
  bool submitting = false;

  return showDialog<EndReasonSelection>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final needsSearchConfirm = selectedReason == kEndReasonNotFound;
        final needsOtherText = selectedReason == kEndReasonOther;
        final needsServiceType =
            selectedReason == kEndReasonSpecializedTransport;
        final needsNotes =
            selectedReason == kEndReasonNotFound ||
            selectedReason == kEndReasonReporterUnreachable ||
            selectedReason == kEndReasonAggressive;
        final canConfirm =
            !submitting &&
            selectedReason != null &&
            (!needsSearchConfirm || searchedTenMinutes) &&
            (!needsServiceType ||
                (serviceType != null &&
                    (serviceType != 'Other' ||
                        serviceTypeOtherCtrl.text.trim().isNotEmpty)));

        return Dialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        'End Reason',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...kEndReasons.map(
                  (r) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: r,
                    groupValue: selectedReason,
                    activeColor: AppColors.textPrimary,
                    title: Text(
                      r,
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onChanged: (v) => setDlg(() => selectedReason = v),
                  ),
                ),
                if (needsOtherText) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => other = v,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    decoration: _fieldDecoration(
                      'Describe reason…',
                      hintSize: 13,
                    ),
                  ),
                ],
                if (needsSearchConfirm) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: searchedTenMinutes,
                      activeColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      title: Text(
                        'I waited and searched the immediate area for at '
                        'least 10 minutes and could not locate the animal.',
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onChanged: (v) =>
                          setDlg(() => searchedTenMinutes = v ?? false),
                    ),
                  ),
                ],
                if (needsNotes) ...[
                  const SizedBox(height: 14),
                  Text(
                    selectedReason == kEndReasonAggressive
                        ? 'Describe the animal\'s behavior'
                        : 'Notes (what did you observe?)',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    decoration: _fieldDecoration(
                      selectedReason == kEndReasonAggressive
                          ? 'e.g. "Lunging and growling, could not be safely restrained."'
                          : 'e.g. "Neighbors said the dog left 30 minutes ago."',
                    ),
                  ),
                ],
                if (needsServiceType) ...[
                  const SizedBox(height: 14),
                  Text(
                    'What kind of service does this animal need?',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This is shown to the org so they can arrange the right transporter or vehicle.',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...kSpecializedServiceTypes.map(
                    (option) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: option,
                      groupValue: serviceType,
                      activeColor: AppColors.textPrimary,
                      title: Text(
                        option,
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onChanged: (v) => setDlg(() => serviceType = v),
                    ),
                  ),
                  if (serviceType == 'Other') ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: serviceTypeOtherCtrl,
                      onChanged: (_) => setDlg(() {}),
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(
                        'Describe the service needed…',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: !canConfirm
                        ? null
                        : () {
                            setDlg(() => submitting = true);
                            Navigator.pop(
                              ctx,
                              EndReasonSelection(
                                reason: selectedReason!,
                                otherText: other,
                                notes: notesCtrl.text.trim(),
                                serviceType: needsServiceType
                                    ? (serviceType == 'Other'
                                          ? serviceTypeOtherCtrl.text.trim()
                                          : serviceType)
                                    : null,
                              ),
                            );
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Confirm',
                            style: GoogleFonts.zain(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: canConfirm
                                  ? Colors.redAccent
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The transporter's in-person check before an adopter hand-off. Returns
/// true only for "Yes, confirm".
Future<bool> showConfirmAdopterPickupDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Confirm Adopter Pickup',
        style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
      ),
      content: Text(
        'Is the interested adopter actually here, in person, ready to take the animal?',
        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Not yet',
            style: GoogleFonts.zain(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.greenrspwn,
            foregroundColor: AppColors.textPrimary,
          ),
          child: const Text('Yes, confirm'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
