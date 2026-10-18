import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
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
  // Populated once the future resolves, so _keepSeparate can record exactly
  // which candidate ids were actually shown to the admin (not re-derivable
  // from the Future itself once it's settled).
  List<RescueCase> _shownCandidates = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _candidatesFuture = widget.repository.findPossibleDuplicates(widget.sourceCase).then((candidates) {
      if (mounted) setState(() => _shownCandidates = candidates);
      return candidates;
    });
  }

  Future<void> _viewReport(RescueCase c) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RescueDetailPage(caseId: c.id, data: c.raw)),
      );

  Future<void> _compare(RescueCase candidate) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _CompareReportsPage(source: widget.sourceCase, candidate: candidate)),
      );

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
        dismissedCandidateIds: _shownCandidates.map((c) => c.id).toList(),
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _viewReport(widget.sourceCase),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('View Current Report (#${widget.sourceCase.shortCaseId})',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
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
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _busy ? null : () => _viewReport(candidate),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: const BorderSide(color: AppColors.slaterspwn),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    child: Text('View Report', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _busy ? null : () => _compare(candidate),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: const BorderSide(color: AppColors.slaterspwn),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    child: Text('Compare', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
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

/// Sequential (stacked, not side-by-side — this app's cards are read on
/// phone-width screens) comparison of the current report against one
/// candidate: images, locations, distance, submission times, species/
/// description, reporter info, and current status for both. Opened from
/// the candidate card's "Compare" button; the possible-duplicate sheet
/// underneath is untouched and still has its full candidate list once the
/// admin backs out of this page.
class _CompareReportsPage extends StatelessWidget {
  final RescueCase source;
  final RescueCase candidate;
  const _CompareReportsPage({required this.source, required this.candidate});

  @override
  Widget build(BuildContext context) {
    final distanceKm = source.lat != null && source.lng != null && candidate.lat != null && candidate.lng != null
        ? RescueCaseRepository().distanceKmBetween(source, candidate)
        : null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Compare Reports', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (distanceKm != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: Text('${distanceKm.toStringAsFixed(2)} km apart',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ),
          _CompareCard(label: 'Current Report', c: source),
          const SizedBox(height: 14),
          const Center(child: Icon(Icons.compare_arrows, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          _CompareCard(label: 'Possible Duplicate', c: candidate),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  final String label;
  final RescueCase c;
  const _CompareCard({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    final ts = c.createdAt;
    final timeStr = ts != null ? '${ts.month}/${ts.day}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}' : 'Unknown';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.slaterspwn)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              const Spacer(),
              RescueStatusChip(status: c.status),
            ],
          ),
          const SizedBox(height: 4),
          Text('CASE ID: ${c.shortCaseId}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          if (c.photoUrls.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: c.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => Image.network(c.photoUrls[i], width: 140, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 140, color: AppColors.tearspwn)),
                ),
              ),
            )
          else
            Container(height: 100, color: AppColors.tearspwn, child: const Center(child: Icon(Icons.pets, color: AppColors.textSecondary))),
          const SizedBox(height: 10),
          _row('Species / description', '${c.speciesSummary}${(c.condition ?? '').isNotEmpty ? ' — ${c.condition}' : ''}'),
          _row('Location', c.address ?? 'Not provided'),
          _row('Submitted', timeStr),
          _row('Reporter', c.reporterName ?? 'Not provided'),
          _row('Reporter phone', c.reporterPhone ?? 'Not provided'),
          _row('Urgency', c.urgency ?? 'Not provided'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
          ],
        ),
      );
}
