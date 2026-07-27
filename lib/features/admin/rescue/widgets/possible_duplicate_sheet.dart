import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/status_chip.dart';

/// Possible Duplicate modal. The system suggests nearby active reports of
/// the same species; the organization makes the final call — merge
/// [sourceCase] into one of the suggestions, or confirm it's a separate
/// report. Returns true if a merge or keep-separate decision was made.
Future<bool> showPossibleDuplicateSheet(
  BuildContext context, {
  required RescueCase sourceCase,
  required RescueCaseRepository repository,
  required String actorUid,
  required String actorName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PossibleDuplicateSheetBody(
      sourceCase: sourceCase,
      repository: repository,
      actorUid: actorUid,
      actorName: actorName,
    ),
  );
  return result ?? false;
}

class _PossibleDuplicateSheetBody extends StatefulWidget {
  final RescueCase sourceCase;
  final RescueCaseRepository repository;
  final String actorUid;
  final String actorName;

  const _PossibleDuplicateSheetBody({
    required this.sourceCase,
    required this.repository,
    required this.actorUid,
    required this.actorName,
  });

  @override
  State<_PossibleDuplicateSheetBody> createState() => _PossibleDuplicateSheetBodyState();
}

class _PossibleDuplicateSheetBodyState extends State<_PossibleDuplicateSheetBody> {
  late Future<List<RescueCase>> _candidatesFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _candidatesFuture = widget.repository.findPossibleDuplicates(widget.sourceCase);
  }

  Future<void> _merge(RescueCase candidate) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Merge Duplicate Report?',
      message:
          'This report will be merged into CASE ID: ${candidate.shortCaseId}. '
          'Neither report is deleted — both reporters, their media, and their '
          'private messages are preserved, and both will see a shared status update.',
      confirmLabel: 'Merge',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.mergeDuplicate(
        primaryCaseId: candidate.id,
        duplicateCaseId: widget.sourceCase.id,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not merge: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _keepSeparate() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Keep as a Separate Report?',
      message: 'This report will go back to Pending Review as its own, unrelated case.',
      confirmLabel: 'Keep Separate',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.keepSeparate(
        caseId: widget.sourceCase.id,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _busy = false);
      }
    }
  }

  String _minutesApartLabel(RescueCase a, RescueCase b) {
    if (a.createdAt == null || b.createdAt == null) return 'Unknown time gap';
    final diff = a.createdAt!.difference(b.createdAt!).abs();
    if (diff.inMinutes < 60) return '${diff.inMinutes} min apart';
    if (diff.inHours < 24) return '${diff.inHours} hr apart';
    return '${diff.inDays} day(s) apart';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Possible Duplicate Reports',
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'The system found nearby active reports for the same species. '
              'Compare and decide whether this is the same rescue.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<RescueCase>>(
                future: _candidatesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final candidates = snapshot.data ?? const [];
                  if (candidates.isEmpty) {
                    return Center(
                      child: Text(
                        'No nearby active reports of the same species were found.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final candidate = candidates[i];
                      final distanceKm =
                          widget.repository.distanceKmBetween(widget.sourceCase, candidate);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.slaterspwn),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: candidate.photoUrls.isNotEmpty
                                      ? Image.network(candidate.photoUrls.first,
                                          width: 56, height: 56, fit: BoxFit.cover)
                                      : Container(
                                          width: 56,
                                          height: 56,
                                          color: AppColors.tearspwn,
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('CASE ID: ${candidate.shortCaseId}',
                                          style: GoogleFonts.tiltWarp(
                                              fontSize: 13, color: AppColors.textPrimary)),
                                      Text(
                                        '${distanceKm.toStringAsFixed(2)} km away · ${_minutesApartLabel(widget.sourceCase, candidate)}',
                                        style: GoogleFonts.zain(
                                            fontSize: 11, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                UrgencyChip(urgency: candidate.urgency),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              candidate.condition ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => _merge(candidate),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textPrimary,
                                  side: const BorderSide(color: AppColors.textPrimary),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                                child: Text('Merge into this case',
                                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _keepSeparate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('None of these — Keep Separate',
                        style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
