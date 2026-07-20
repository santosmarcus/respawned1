import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/features/admin/rescue/widgets/status_chip.dart';

/// Rescue list card: photo, case ID (header) + species summary + urgency,
/// short location, reporter, time submitted, status, and a "View Details"
/// action. Always exactly one card per case document — a multi-animal
/// report's animals only ever affect the species-summary line below the
/// header, never the number of cards shown.
///
/// [showStatusChip] is on by default for anything outside the five main
/// pipeline tabs (where the tab itself already communicates the status) —
/// pass it explicitly to control this from the caller instead.
class RescueCaseCard extends StatelessWidget {
  final RescueCase rescueCase;
  final VoidCallback onTap;
  final bool showStatusChip;
  final bool highlightBorder;

  const RescueCaseCard({
    super.key,
    required this.rescueCase,
    required this.onTap,
    this.showStatusChip = false,
    this.highlightBorder = false,
  });

  String _previewText(RescueCase c) {
    switch (c.status) {
      case RescueStatus.pendingReview:
        return c.condition ?? '';
      case RescueStatus.accepted:
      case RescueStatus.awaitingAssignment:
        return 'Searching for Pet Transporter...';
      case RescueStatus.ongoing:
        return c.statusHistory.isNotEmpty ? c.statusHistory.last.status : 'In progress';
      case RescueStatus.treatment:
        return 'The animal has reached the clinic. Animal is now in treatment.';
      case RescueStatus.intake:
        return 'Animal marked ready for Intake.';
      case RescueStatus.rejected:
        return 'Rejected: ${c.rejectionReasonOther ?? c.rejectionReason?.label ?? '-'}';
      case RescueStatus.referred:
        return c.statusHistory.isNotEmpty ? c.statusHistory.last.status : 'Referred.';
      case RescueStatus.possibleDuplicate:
        return 'Flagged as a possible duplicate report.';
      case RescueStatus.merged:
        return 'Merged into another case.';
      case RescueStatus.completed:
        return 'Case completed.';
      case RescueStatus.cancelled:
        return 'Case cancelled.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = rescueCase;
    final ts = c.createdAt;
    final timeStr = ts != null
        ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')} ${ts.hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null ? '${ts.month}/${ts.day}/${ts.year}' : '';
    final thumbnail = c.photoUrls.isNotEmpty ? c.photoUrls.first : null;
    // Treatment-stage cards show clinic + days in treatment instead of the
    // generic status preview/address/timestamp lines — same shared card,
    // just a stage-aware body, per the Treatment card hierarchy.
    final isTreatmentStage = c.status == RescueStatus.treatment;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: highlightBorder
              ? Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: thumbnail != null
                  ? Image.network(
                      thumbnail,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: AppColors.tearspwn,
                      ),
                    )
                  : Container(
                      width: 72,
                      height: 72,
                      color: AppColors.tearspwn,
                      child: const Icon(Icons.pets, color: AppColors.textSecondary),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '#${c.shortCaseId}',
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      UrgencyChip(urgency: c.urgency),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Species summary — e.g. "Dog ×2, Cat" for a multi-animal
                  // report — plus a count when there's more than one
                  // animal. This, not the case ID above, is where a
                  // multi-animal report's animals actually show up; the
                  // card itself is always exactly one per case document.
                  Text(
                    c.animalCount > 1 ? '${c.speciesSummary} · ${c.animalCount} animals' : c.speciesSummary,
                    style: GoogleFonts.zain(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (isTreatmentStage) ...[
                    if ((c.vetClinicName ?? '').isNotEmpty)
                      Text(
                        c.vetClinicName!,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      '${c.daysInTreatment} day${c.daysInTreatment == 1 ? '' : 's'} in treatment',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ] else ...[
                    Text(
                      _previewText(c),
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.address ?? '',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ts != null)
                      Text(
                        '$timeStr  $dateStr',
                        style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Reported by: ${c.reporterName ?? '-'}',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Case ID already headlines the card above — this
                      // row is just the status chip now (when shown), not
                      // a second copy of the ID.
                      Expanded(
                        child: showStatusChip ? RescueStatusChip(status: c.status) : const SizedBox.shrink(),
                      ),
                      ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.yellowrspwn,
                          elevation: 0,
                          minimumSize: const Size(90, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(
                          'View Details',
                          style: GoogleFonts.zain(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
