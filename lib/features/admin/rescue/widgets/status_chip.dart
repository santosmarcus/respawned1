import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';

/// Small rounded chip showing a [RescueStatus]. Reused on the rescue list,
/// detail page, and referral/merge history sections.
class RescueStatusChip extends StatelessWidget {
  final RescueStatus status;
  const RescueStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.zain(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small rounded chip showing urgency ('Critical' / 'Medium' / 'Low').
/// Accepts the raw string still used throughout the data model so existing
/// call sites don't need to construct a [UrgencyLevel] just to render this.
class UrgencyChip extends StatelessWidget {
  final String? urgency;
  const UrgencyChip({super.key, required this.urgency});

  @override
  Widget build(BuildContext context) {
    final level = UrgencyLevel.fromFirestoreValue(urgency);
    // Urgency is set once, from the report, and never changes afterwards —
    // the tooltip says so, so it isn't read as the animal's current state
    // (see [TreatmentConditionChip] for that).
    return Tooltip(
      message: 'Reported urgency',
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: level?.color ?? const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        (urgency == null || urgency!.isEmpty) ? 'Unrated' : urgency!,
        style: GoogleFonts.zain(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      ),
    );
  }
}

/// The animal's latest condition from its treatment logs ('Critical',
/// 'Stable', 'Recovering', 'Ready for Discharge', 'Deceased'). Unlike
/// [UrgencyChip] — fixed at report time — this follows treatment, so the
/// Treatment tab shows how the animal is doing now.
class TreatmentConditionChip extends StatelessWidget {
  final String condition;
  const TreatmentConditionChip({super.key, required this.condition});

  static Color colorFor(String condition) => switch (condition.toLowerCase()) {
        'critical' => AppColors.error,
        'stable' => const Color(0xFF4E8FE0),
        'recovering' => AppColors.greenrspwn,
        'ready for discharge' => AppColors.success,
        'deceased' => AppColors.textSecondary,
        _ => const Color(0xFFD9D9D9),
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Latest treatment condition',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: colorFor(condition),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          condition,
          style: GoogleFonts.zain(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
/// Marks a report the organization is not expected to act on by default:
/// reporter-led neglect/abuse reports and surrenders (org_involvement.dart).
class OrgInvolvementChip extends StatelessWidget {
  final OrgInvolvement involvement;
  const OrgInvolvementChip({super.key, required this.involvement});

  @override
  Widget build(BuildContext context) {
    final icon = switch (involvement) {
      OrgInvolvement.orgAssist => Icons.volunteer_activism_outlined,
      OrgInvolvement.independentReport => Icons.assignment_ind_outlined,
      OrgInvolvement.notFacilitated => Icons.visibility_outlined,
    };
    return Tooltip(
      message: involvement.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEDED),
          border: Border.all(color: const Color(0xFF9E9E9E)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: const Color(0xFF424242)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                involvement.label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF424242)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
