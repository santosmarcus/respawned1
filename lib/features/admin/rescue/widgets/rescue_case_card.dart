import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/core/utils/species_summary.dart' as species_summary_util;
import 'package:respawnd1/features/admin/rescue/widgets/status_chip.dart';

/// Extra fields shown on a Rejected-tab card only (Rejected Rescue Reports
/// spec) — reporter/reason/rejected-date/rejected-by/Community Adoption
/// eligibility. [rejectedBy] is looked up from the case's activityLogs
/// subcollection by the caller (rescue_reports_page.dart), never here — this
/// card stays a plain StatelessWidget with no Firestore dependency of its
/// own, same reasoning as [pendingOfferNote].
class RejectionCardInfo {
  final String? reporterName;
  final String reasonLabel;
  final DateTime? rejectedDate;
  final String? rejectedBy;
  final bool communityAdoptionEligible;

  const RejectionCardInfo({
    this.reporterName,
    required this.reasonLabel,
    this.rejectedDate,
    this.rejectedBy,
    this.communityAdoptionEligible = false,
  });
}

/// Compact rescue list card — image, case ID, species summary, priority,
/// short location, reported date/time, current phase/status, and a "View
/// Details" action, sized consistently with AnimalRecordCard/adoption cards
/// (12px padding, 16 radius, 80x80 image). Always exactly one card per case
/// document — a multi-animal report's animals only ever affect the
/// species-summary line, never the number of cards shown. Deliberately
/// drops reporter name and the multi-line status-history preview that used
/// to make this card substantially taller than every other admin list card
/// — that detail still lives on Rescue Details, one tap away.
///
/// [showStatusChip] additionally renders a colored status pill (used
/// outside the five main pipeline tabs, where the tab itself doesn't
/// already communicate status) — the plain-text phase label from
/// [RescueStatus.label] is shown either way, per the compact-card spec's
/// "Current phase/status" field.
///
/// [pendingOfferNote] (Assign-tab only, spec §5) — when the case already
/// has a valid pending transporter offer, replaces the location/date line
/// with "Awaiting transporter response · Offered to: X" so the card never
/// reads as completely unassigned. Passed in by the caller (which watches
/// the assignment stream), not computed here — this card stays a plain
/// StatelessWidget with no Firestore dependency of its own.
class RescueCaseCard extends StatelessWidget {
  final RescueCase rescueCase;
  final VoidCallback onTap;
  final bool showStatusChip;
  final bool highlightBorder;
  final String? pendingOfferNote;

  /// Rejected-tab only (Rejected Rescue Reports spec) — reporter, rejection
  /// reason, rejected date/by, and Community Adoption eligibility, appended
  /// below the usual card content. Null on every other tab.
  final RejectionCardInfo? rejectionInfo;

  /// Restricts the species-summary/animal-count line to only the animals
  /// currently in this stage (spec §7: "card/page must show only the
  /// animals relevant to that stage") — e.g. 'intake' on the Intake tab so
  /// a case with one animal still in Treatment doesn't show that animal's
  /// species here too. Null (every call site outside Treatment/Intake)
  /// keeps the original whole-case summary unchanged.
  final String? stageFilter;

  const RescueCaseCard({
    super.key,
    required this.rescueCase,
    required this.onTap,
    this.showStatusChip = false,
    this.highlightBorder = false,
    this.pendingOfferNote,
    this.rejectionInfo,
    this.stageFilter,
  });

  @override
  Widget build(BuildContext context) {
    final c = rescueCase;
    final ts = c.createdAt;
    final timeStr = ts != null
        ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')} ${ts.hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null ? '${ts.month}/${ts.day}/${ts.year}' : '';
    final thumbnail = c.photoUrls.isNotEmpty ? c.photoUrls.first : null;
    // Treatment-stage cards show the clinic name instead of the reported
    // address — still exactly one line, same compact shape.
    final isTreatmentStage = c.status == RescueStatus.treatment;
    final locationLine = isTreatmentStage ? (c.vetClinicName ?? '') : (c.address ?? '');
    final dateTimeLine = ts != null ? '$dateStr  $timeStr' : '';

    // Stage-filtered species summary/count (spec §7) — falls back to the
    // whole-case summary whenever no filter is requested, or the case has
    // no `animals[]` array to filter (legacy single-animal case).
    final filterStage = stageFilter;
    final stageAnimalIndexes =
        filterStage != null && c.animals.isNotEmpty ? animalIndexesInStage(c, filterStage) : null;
    final stageAnimals = stageAnimalIndexes != null ? [for (final i in stageAnimalIndexes) c.animals[i]] : null;
    final speciesSummary =
        stageAnimals != null ? species_summary_util.summarizeSpecies(animals: stageAnimals) : c.speciesSummary;
    final animalCount = stageAnimals?.length ?? c.animalCount;

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
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
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
                          style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
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
                    animalCount > 1 ? '$speciesSummary · $animalCount animals' : speciesSummary,
                    style: GoogleFonts.zain(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if (pendingOfferNote != null)
                    Text(
                      pendingOfferNote!,
                      style: GoogleFonts.zain(
                          fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF9C6B10)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (locationLine.isNotEmpty)
                    Text(
                      locationLine,
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (dateTimeLine.isNotEmpty)
                    Text(dateTimeLine, style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                  if (rejectionInfo != null) ..._rejectionInfoLines(rejectionInfo!),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: showStatusChip
                            ? RescueStatusChip(status: c.status)
                            : Text(
                                c.status == RescueStatus.accepted
                                    ? 'Accepted · Clinic selection required'
                                    : c.status.label,
                                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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

  Widget _placeholder() => Container(
        width: 80,
        height: 80,
        color: AppColors.tearspwn,
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );

  List<Widget> _rejectionInfoLines(RejectionCardInfo info) {
    final rejectedDate = info.rejectedDate;
    final rejectedDateStr = rejectedDate != null
        ? '${rejectedDate.month}/${rejectedDate.day}/${rejectedDate.year}'
        : 'Unknown';
    return [
      const SizedBox(height: 3),
      if ((info.reporterName ?? '').isNotEmpty)
        Text('Reporter: ${info.reporterName}',
            style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      Text('Reason: ${info.reasonLabel}',
          style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      Text('Rejected $rejectedDateStr${info.rejectedBy != null ? ' by ${info.rejectedBy}' : ''}',
          style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      if (info.communityAdoptionEligible)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.greenrspwn.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Community Adoption eligible',
                style: GoogleFonts.zain(
                    fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.greenrspwn)),
          ),
        ),
    ];
  }
}