import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

String _formatReportDateTime(DateTime? d) {
  if (d == null) return '';
  final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
  final m = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ampm, ${d.month}/${d.day}/${d.year}';
}

/// Read-only view of `cases/{caseId}/communityReports` — the same
/// subcollection the user-side track_case_page.dart's
/// `_CommunityReportSection` writes to. Reused as-is on both the admin
/// Rescue Details page and the admin Track Case page so there's a single
/// source of truth for these submissions.
class CommunityReportsSection extends ConsumerWidget {
  final String caseId;
  const CommunityReportsSection({super.key, required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(caseCommunityReportsProvider(caseId));

    return SectionCard(
      title: 'Community Reports',
      child: reportsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text('Could not load community reports.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        data: (reports) {
          if (reports.isEmpty) {
            return Text('No community reports submitted yet.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: reports.map((r) => _CommunityReportTile(caseId: caseId, report: r)).toList(),
          );
        },
      ),
    );
  }
}

class _CommunityReportTile extends ConsumerStatefulWidget {
  final String caseId;
  final CommunityReport report;
  const _CommunityReportTile({required this.caseId, required this.report});

  @override
  ConsumerState<_CommunityReportTile> createState() => _CommunityReportTileState();
}

class _CommunityReportTileState extends ConsumerState<_CommunityReportTile> {
  bool _busy = false;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).approveLocationUpdate(
            caseId: widget.caseId,
            reportId: widget.report.id,
            actorUid: _actorUid,
            actorName: _actorName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not approve: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).rejectLocationUpdate(
            caseId: widget.caseId,
            reportId: widget.report.id,
            actorUid: _actorUid,
            actorName: _actorName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reject: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final name = (report.reporterName?.trim().isNotEmpty ?? false)
        ? report.reporterName!
        : 'A community member';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.textPrimary,
            child: Text(
              name.characters.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.background, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · ${report.typeLabel}',
                    style: GoogleFonts.zain(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (report.timestamp != null)
                  Text(_formatReportDateTime(report.timestamp),
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                if (report.comment != null && report.comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(report.comment!,
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                ],
                if (report.newAddress != null && report.newAddress!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('New location: ${report.newAddress}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
                // Community Location Approval spec §9 — the case's own
                // address/lat/lng only ever change once Approve is tapped
                // here; this card never implies otherwise while pending.
                if (report.approvalStatus == 'pending') ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFF9C6B10).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                      child: Text('Pending approval',
                          style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF9C6B10))),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _reject,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), minimumSize: const Size(0, 32)),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _busy ? null : _approve,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.greenrspwn, foregroundColor: Colors.white, minimumSize: const Size(0, 32)),
                      child: _busy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Approve Location Change', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ] else if (report.approvalStatus == 'approved') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Location change approved by ${report.approvedBy ?? '—'}${report.approvedAt != null ? ' on ${_formatReportDateTime(report.approvedAt)}' : ''}',
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.greenrspwn),
                  ),
                ] else if (report.approvalStatus == 'rejected') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Location change rejected by ${report.rejectedBy ?? '—'}${report.rejectedAt != null ? ' on ${_formatReportDateTime(report.rejectedAt)}' : ''}',
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          if (report.photoUrl != null && report.photoUrl!.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                report.photoUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: AppColors.slaterspwn,
                  child: const Icon(Icons.broken_image_outlined, size: 18, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
