import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/rescue/neglect_abuse_guide_content.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/features/rescue/widgets/neglect_abuse_fields.dart';

/// Neglect or Abuse, right after the rescue type: what happens to this
/// report depends on where the animal is (the pinned location).
///
/// * Outside every partner organization's coverage: the reporting
///   guidelines first, with why (no partner can be sent there; the
///   barangay, the city or municipal LGU and the police can act anywhere,
///   and only they can act against an owner). The report is still recorded
///   as reporter-led.
/// * Inside: the rescue form, with the disclaimer that the report is
///   subject to the organization's review and approval, and a nudge to
///   report it to the authorities too.
///
/// The path is set from coverage (RescueFormController.applyAbuseCoverage);
/// the reporter is no longer asked to choose.
class NeglectAbuseCoverageSection extends StatelessWidget {
  const NeglectAbuseCoverageSection({
    super.key,
    required this.form,
    required this.hasPin,
  });

  final RescueFormController form;

  /// Whether the location step has a resolved pin yet.
  final bool hasPin;

  @override
  Widget build(BuildContext context) {
    TextStyle body([FontWeight w = FontWeight.w400, double size = 13]) =>
        GoogleFonts.zain(fontSize: size, fontWeight: w, color: AppColors.textPrimary);

    if (!hasPin) {
      return _note(
        icon: Icons.place_outlined,
        child: Text(
          'Pin the animal\'s location in step 1 first. We use it to check whether a partner '
          'organization can respond there.',
          style: body(),
        ),
      );
    }
    final covered = form.abuseAreaCovered;
    if (covered == null) {
      return _note(
        icon: Icons.travel_explore,
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text('Checking whether a partner organization covers this location…', style: body())),
          ],
        ),
      );
    }

    final guideButton = OutlinedButton.icon(
      onPressed: () => showNeglectAbuseGuide(context),
      icon: const Icon(Icons.menu_book_outlined, color: AppColors.textPrimary),
      label: Text(
        'Open the step-by-step reporting guide',
        style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
    );

    if (!covered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_off_outlined, size: 18, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('This location is outside our partner organizations\' reach',
                          style: body(FontWeight.w700, 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'No partner organization operates here, so we cannot send anyone to help. '
                  'Please report it directly to your barangay, your city or municipal LGU '
                  '(its veterinary office), or the police (911). They can act anywhere, and only '
                  'they can act against an owner or file a case.',
                  style: body(),
                ),
                const SizedBox(height: 6),
                Text(
                  'You can still submit this report. It is kept on record as a report you are '
                  'taking to the authorities yourself, and an organization may assist if it can. '
                  'It is subject to review.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const NeglectAbuseGuidanceBox(),
          const SizedBox(height: 10),
          guideButton,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same "Please read before you continue" notice as before.
        const NeglectAbuseGuidanceBox(),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greenrspwn.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.greenrspwn),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.volunteer_activism_outlined, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can ask a partner organization for help',
                      style: body(FontWeight.w700, 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Fill in the form below to ask for help. Your report is subject to the '
                'organization\'s review and approval: it may coordinate with the authorities or '
                'rescue the animal depending on its assessment, capacity and availability. '
                'Submitting does not guarantee a rescue or a personal response.',
                style: body(),
              ),
              const SizedBox(height: 6),
              Text(
                'Please also report it yourself to your barangay or the police (911). Only they '
                'can act against an owner or file a case, and your report helps.',
                style: body(FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        guideButton,
      ],
    );
  }

  Widget _note({required IconData icon, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.slaterspwn.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      );
}

/// "Already reported" switch and its details. Shared by the report form
/// and the Track Case update sheet.
class IndependentReportFields extends StatelessWidget {
  const IndependentReportFields({
    super.key,
    required this.alreadyReported,
    required this.onAlreadyReportedChanged,
    required this.reportedToController,
    required this.referenceController,
    required this.reportedOn,
    required this.onReportedOnChanged,
  });

  final bool alreadyReported;
  final ValueChanged<bool> onAlreadyReportedChanged;
  final TextEditingController reportedToController;
  final TextEditingController referenceController;
  final DateTime? reportedOn;
  final ValueChanged<DateTime?> onReportedOnChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'I have already reported this to the authorities',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
            Switch(
              value: alreadyReported,
              activeThumbColor: AppColors.textPrimary,
              onChanged: onAlreadyReportedChanged,
            ),
          ],
        ),
        if (alreadyReported) ...[
          const SizedBox(height: 6),
          RescueFieldLabel('Office you reported to', required: true),
          const SizedBox(height: 6),
          RescueTextField(reportedToController, 'e.g. Barangay hall, police station, city vet office'),
          const SizedBox(height: 12),
          RescueFieldLabel('Reference or blotter number', required: false),
          const SizedBox(height: 6),
          RescueTextField(referenceController, 'If you were given one'),
          const SizedBox(height: 12),
          RescueFieldLabel('Date reported', required: false),
          const SizedBox(height: 6),
          RescuePickerField(
            label: reportedOn == null ? 'Select date' : formatDate(reportedOn!),
            icon: Icons.calendar_today_outlined,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: reportedOn ?? now,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now,
              );
              if (picked != null) onReportedOnChanged(picked);
            },
          ),
        ],
      ],
    );
  }
}

/// The step-by-step guide, inside the reporting flow (a sheet, so the
/// reporter never leaves the form).
Future<void> showNeglectAbuseGuide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            'Reporting suspected neglect or abuse',
            style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          if (kAbuseGuideSourceNote.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                kAbuseGuideSourceNote,
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < kNeglectAbuseGuideSteps.length; i++)
            _GuideStepTile(index: i, step: kNeglectAbuseGuideSteps[i]),
        ],
      ),
    ),
  );
}

class _GuideStepTile extends StatelessWidget {
  const _GuideStepTile({required this.index, required this.step});
  final int index;
  final GuideStep step;

  String? get _sourceLabel => switch (step.source) {
        GuideSource.respawndGeneral => null,
        GuideSource.pawsRecommendation => 'PAWS recommendation',
        GuideSource.officialProcedure => 'Official procedure',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.slaterspwn),
      ),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        shape: const Border(),
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.yellowrspwn,
          child: Text('${index + 1}', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        title: Text(step.title, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        subtitle: Text(step.summary, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sourceLabel case final label?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(label, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
          for (final point in step.points)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  Expanded(child: Text(point, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
