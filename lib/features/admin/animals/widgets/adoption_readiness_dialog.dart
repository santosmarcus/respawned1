import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/adoption_readiness.dart';

/// Shown when staff tap the locked Adoptable switch: every readiness item
/// with ✓/✗ and its reason, plus "Override and mark adoptable". Returns the
/// override reason staff typed, or null when they closed the sheet or
/// cancelled the override.
Future<String?> showAdoptionReadinessSheet(
  BuildContext context, {
  required String animalName,
  required List<ReadinessCheck> checks,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReadinessSheet(animalName: animalName, checks: checks),
  );
}

class _ReadinessSheet extends StatelessWidget {
  final String animalName;
  final List<ReadinessCheck> checks;
  const _ReadinessSheet({required this.animalName, required this.checks});

  @override
  Widget build(BuildContext context) {
    final unmet = unmetReadiness(checks).length;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Not ready for adoption yet',
                        style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$unmet of ${checks.length} readiness items are not met for $animalName. '
                'Update the record, or override with a reason.',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              for (final c in checks) _CheckRow(check: c),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: AppButtons.dangerOutline,
                  onPressed: () async {
                    final reason = await _confirmOverride(context, animalName);
                    if (reason != null && context.mounted) Navigator.pop(context, reason);
                  },
                  child: const Text('Override and mark adoptable'),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final ReadinessCheck check;
  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(check.met ? Icons.check_circle : Icons.cancel,
              size: 20, color: check.met ? AppColors.success : AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label,
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(check.reason,
                    style: GoogleFonts.zain(
                        fontSize: 12, color: check.met ? AppColors.textSecondary : AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation with a required reason. Returns the trimmed reason, or
/// null when cancelled.
Future<String?> _confirmOverride(BuildContext context, String animalName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OverrideDialog(animalName: animalName),
  );
}

class _OverrideDialog extends StatefulWidget {
  final String animalName;
  const _OverrideDialog({required this.animalName});

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Override readiness?', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.animalName} will be marked adoptable with unmet readiness items. '
              'The reason is saved on the record and in its management logs.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                hintText: 'e.g. Spay booked for next week; adopter will be told.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: AppButtons.danger,
          onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
          child: const Text('Override'),
        ),
      ],
    );
  }
}
