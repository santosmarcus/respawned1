import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Release Animal — a limited, temporary handoff-to-reporter flow. Only
/// ever shown when the reporter indicated adoption interest at submission
/// time (`RescueCase.interestedToAdopt == 'yes'`, the same field
/// rescue_detail_page.dart already displays) — callers must not open this
/// otherwise (see TreatmentDetailPage's `allowRelease` gate).
///
/// TODO(adoption): this is NOT a completed adoption. There is no
/// application, approval, contract, or post-adoption follow-up here —
/// those are a separate, not-yet-built feature. This only records the
/// minimal handoff fields needed for testing
/// (releasedToReporterId/Name/At/notes) and shows "Release confirmed", not
/// "Adoption approved".
Future<bool> showReleaseAnimalSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  List<int>? animalIndexes,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReleaseAnimalSheetBody(rescueCase: rescueCase, animalIndexes: animalIndexes),
  );
  return result ?? false;
}

class _ReleaseAnimalSheetBody extends ConsumerStatefulWidget {
  final RescueCase rescueCase;
  final List<int>? animalIndexes;
  const _ReleaseAnimalSheetBody({required this.rescueCase, this.animalIndexes});

  @override
  ConsumerState<_ReleaseAnimalSheetBody> createState() => _ReleaseAnimalSheetBodyState();
}

class _ReleaseAnimalSheetBodyState extends ConsumerState<_ReleaseAnimalSheetBody> {
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final c = widget.rescueCase;
    if (c.reporterId == null || c.reporterId!.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).releaseToReporter(
            caseId: c.id,
            reporterId: c.reporterId!,
            reporterName: c.reporterName ?? 'Unnamed Reporter',
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            actorUid: 'admin',
            actorName: 'Admin Staff',
            animalIndexes: widget.animalIndexes,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm release: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
            Text('Release Animal', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            _Label('Recipient'),
            Text(c.reporterName ?? 'Unnamed Reporter',
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('Reporter interested in adopting',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),

            _Label('Case ID'),
            Text('#${c.shortCaseId}', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            _Label('Species Summary'),
            Text(c.speciesSummary, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            if ((c.reporterPhone ?? '').isNotEmpty) ...[
              _Label('Contact Information'),
              Text(c.reporterPhone!, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
            ],

            _Label('Release Notes'),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Optional notes',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 6),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
              ),
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 10),
            Text(
              'This confirms a temporary handoff for testing only — it is not a '
              'completed adoption. Formal adoption approval and forms are not part of this yet.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : Text('Confirm Release',
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );
}
