import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/rescue/neglect_abuse_guide_content.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Neglect or Abuse: choose between asking the organization for help and
/// reporting to the authorities yourself with the guide. What the reporter
/// has already filed comes from NeglectAbuseFields' "Reporting to
/// Authorities" answers; details can be added later from Track Case
/// (IndependentReportSection).
class NeglectAbusePathSection extends StatelessWidget {
  const NeglectAbusePathSection({
    super.key,
    required this.form,
    required this.onChanged,
  });

  final RescueFormController form;
  final VoidCallback onChanged;

  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final path = form.abuseReportPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RescueFieldLabel('How would you like to handle this report?', required: true),
        const SizedBox(height: 8),
        _PathOption(
          selected: path == kAbusePathOrgAssistance,
          icon: Icons.volunteer_activism_outlined,
          title: 'Ask the organization for help',
          body: 'The organization may assist, for example by coordinating with '
              'local authorities or rescuing the animal. Assistance depends on '
              'availability, whether the location is within its coverage area, '
              'and its assessment of the case. Submitting does not guarantee a '
              'personal response.',
          onTap: () => _set(() => form.abuseReportPath = kAbusePathOrgAssistance),
        ),
        const SizedBox(height: 8),
        _PathOption(
          selected: path == kAbusePathIndependent,
          icon: Icons.assignment_outlined,
          title: 'I will report it to the authorities myself',
          body: 'Follow our step-by-step guide. Your report is still recorded, '
              'and the organization can see it and may assist if it can.',
          onTap: () => _set(() => form.abuseReportPath = kAbusePathIndependent),
        ),
        if (path == kAbusePathIndependent) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showNeglectAbuseGuide(context),
            icon: const Icon(Icons.menu_book_outlined, color: AppColors.textPrimary),
            label: Text(
              'Open the reporting guide',
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Answer "Reporting to Authorities" below with what you have done so '
            'far. You can add the office, reference number and updates later '
            'from your report\'s tracking page.',
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _PathOption extends StatelessWidget {
  const _PathOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn.withValues(alpha: 0.25) : Colors.white,
            border: Border.all(
              color: selected ? AppColors.textPrimary : AppColors.slaterspwn,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: AppColors.textPrimary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
