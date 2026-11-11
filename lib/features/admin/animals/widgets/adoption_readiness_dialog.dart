import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/adoption_readiness.dart';

/// Shown when an animal is about to be marked adoptable. Returns the
/// confirmed checklist (stored on the animal as `adoptionReadiness`), or
/// null if staff cancelled or something blocks the listing.
Future<Map<String, dynamic>?> showAdoptionReadinessDialog(
  BuildContext context, {
  required String animalName,
  required List<ReadinessCheck> checks,
  required String confirmedBy,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _ReadinessDialog(animalName: animalName, checks: checks, confirmedBy: confirmedBy),
  );
}

class _ReadinessDialog extends StatefulWidget {
  final String animalName;
  final List<ReadinessCheck> checks;
  final String confirmedBy;
  const _ReadinessDialog({required this.animalName, required this.checks, required this.confirmedBy});

  @override
  State<_ReadinessDialog> createState() => _ReadinessDialogState();
}

class _ReadinessDialogState extends State<_ReadinessDialog> {
  final Set<ReadinessItem> _confirmed = {};

  bool get _blocked => widget.checks.any((c) => c.state == ReadinessState.blocked);

  @override
  Widget build(BuildContext context) {
    final ready = readinessSatisfied(widget.checks, _confirmed);
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Ready for adoption?', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check ${widget.animalName} before listing. Vaccination alone isn\'t enough.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              for (final c in widget.checks) _CheckTile(
                check: c,
                confirmed: _confirmed.contains(c.item),
                onChanged: (v) => setState(() => v ? _confirmed.add(c.item) : _confirmed.remove(c.item)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _blocked || !ready
              ? null
              : () => Navigator.pop(context, {
                    'confirmedBy': widget.confirmedBy,
                    'confirmedAt': DateTime.now().toIso8601String(),
                    'checks': {
                      for (final c in widget.checks)
                        c.item.name: {
                          'finding': c.finding,
                          'confirmed': c.state == ReadinessState.ok || _confirmed.contains(c.item),
                        },
                    },
                  }),
          style: AppButtons.primary,
          child: const Text('Mark Adoptable'),
        ),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  final ReadinessCheck check;
  final bool confirmed;
  final ValueChanged<bool> onChanged;
  const _CheckTile({required this.check, required this.confirmed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.state) {
      ReadinessState.ok => (Icons.check_circle, AppColors.greenrspwn),
      ReadinessState.blocked => (Icons.block, AppColors.error),
      ReadinessState.needsConfirmation =>
        confirmed ? (Icons.check_circle, AppColors.greenrspwn) : (Icons.radio_button_unchecked, AppColors.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(check.item.title,
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(check.finding,
                style: GoogleFonts.zain(
                    fontSize: 12, color: check.state == ReadinessState.blocked ? AppColors.error : AppColors.textSecondary)),
          ),
          if (check.confirmation != null)
            CheckboxListTile(
              value: confirmed,
              onChanged: (v) => onChanged(v ?? false),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(check.confirmation!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
            ),
        ],
      ),
    );
  }
}
