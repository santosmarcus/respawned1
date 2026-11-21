import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';

/// Staff-facing explanation of a report the organization is not expected
/// to act on by default: a reporter-led neglect/abuse report (with what the
/// reporter says they filed with the authorities) or a surrender.
class OrgInvolvementBanner extends StatelessWidget {
  const OrgInvolvementBanner({super.key, required this.rescueCase});

  final RescueCase rescueCase;

  @override
  Widget build(BuildContext context) {
    final inv = rescueCase.orgInvolvement;
    final report = rescueCase.independentReport;
    TextStyle body([FontWeight w = FontWeight.w400]) =>
        GoogleFonts.zain(fontSize: 13, fontWeight: w, color: AppColors.textPrimary);

    final lines = <String>[];
    if (inv == OrgInvolvement.independentReport) {
      if (report != null && report['alreadyReported'] == true) {
        final office = (report['reportedTo'] as String?)?.trim();
        final ref = (report['referenceNumber'] as String?)?.trim();
        final on = report['reportedOn'];
        lines.add('Reporter says it was reported to: ${office == null || office.isEmpty ? 'not stated' : office}');
        if (ref != null && ref.isNotEmpty) lines.add('Reference / blotter no.: $ref');
        if (on is Timestamp) lines.add('Reported on: ${formatDate(on.toDate())}');
      } else {
        lines.add('Not yet reported to the authorities, according to the reporter.');
      }
      final notes = (report?['notes'] as String?)?.trim();
      if (notes != null && notes.isNotEmpty) lines.add('Reporter update: $notes');
      final updated = report?['updatedAt'];
      if (updated is Timestamp) lines.add('Last updated by reporter: ${formatDateTime(updated.toDate())}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slaterspwn.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.slaterspwn),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                inv == OrgInvolvement.independentReport ? Icons.assignment_ind_outlined : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(inv.label, style: body(FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 4),
          Text(inv.description, style: body()),
          for (final line in lines) ...[
            const SizedBox(height: 3),
            Text(line, style: body(FontWeight.w600)),
          ],
          const SizedBox(height: 4),
          Text(
            'Not counted in rescue workload or critical alerts while it waits '
            'in review. Accepting it makes it a regular case.',
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
