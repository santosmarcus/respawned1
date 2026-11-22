import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/rescue/widgets/neglect_abuse_path_section.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Track Case, for a reporter-led Neglect or Abuse report: what the reporter
/// says they filed with the authorities, the guide, a way to add or update
/// those details, and a way to ask the organization for help after all.
class IndependentReportSection extends StatelessWidget {
  const IndependentReportSection({
    super.key,
    required this.caseId,
    required this.data,
    required this.isReporter,
  });

  final String caseId;
  final Map<String, dynamic> data;
  final bool isReporter;

  Map<String, dynamic> get _report {
    final v = data['independentReport'];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final reported = report['alreadyReported'] == true;
    final office = (report['reportedTo'] as String?)?.trim() ?? '';
    final ref = (report['referenceNumber'] as String?)?.trim() ?? '';
    final on = report['reportedOn'];
    final notes = (report['notes'] as String?)?.trim() ?? '';
    TextStyle body([FontWeight w = FontWeight.w400]) =>
        GoogleFonts.zain(fontSize: 13, fontWeight: w, color: AppColors.textPrimary);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reporting to the authorities', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            isReporter
                ? 'You chose to report this yourself. The organization can see your '
                    'report and may assist if its capacity and coverage allow.'
                : 'The reporter chose to report this to the authorities themselves.',
            style: body(),
          ),
          const SizedBox(height: 8),
          if (reported) ...[
            Text('Reported to: ${office.isEmpty ? 'not stated' : office}', style: body(FontWeight.w600)),
            if (ref.isNotEmpty) Text('Reference / blotter no.: $ref', style: body()),
            if (on is Timestamp) Text('Reported on: ${formatDate(on.toDate())}', style: body()),
          ] else
            Text('Not yet reported to the authorities.', style: body(FontWeight.w600)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Latest update: $notes', style: body()),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => showNeglectAbuseGuide(context),
                icon: const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.textPrimary),
                label: Text('Reporting guide', style: body(FontWeight.w700)),
              ),
              if (isReporter)
                OutlinedButton.icon(
                  onPressed: () => _showUpdateSheet(context, report),
                  icon: const Icon(Icons.edit_note, size: 18, color: AppColors.textPrimary),
                  label: Text(reported ? 'Update details' : 'I have reported it', style: body(FontWeight.w700)),
                ),
              if (isReporter)
                TextButton(
                  onPressed: () => _requestOrgAssistance(context),
                  child: Text('Ask the organization for help', style: body(FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateSheet(BuildContext context, Map<String, dynamic> report) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UpdateIndependentReportSheet(caseId: caseId, initial: report),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Report details updated.', kind: AppMessageKind.success));
    }
  }

  Future<void> _requestOrgAssistance(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask the organization for help?'),
        content: const Text(
          'Your report will be sent to the organization for review. Assistance '
          'depends on its availability, whether the location is within its '
          'coverage area, and its assessment of the case. You can keep any '
          'complaint you filed with the authorities open.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ask for help')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('cases').doc(caseId).update({
        'orgInvolvement': OrgInvolvement.orgAssist.firestoreValue,
        'abuseReportPath': kAbusePathOrgAssistance,
        'orgAssistanceRequestedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Reporter asked the organization for assistance.',
            'timestamp': Timestamp.now(),
          },
        ]),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Sent to the organization for review.', kind: AppMessageKind.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not send: $e', kind: AppMessageKind.error));
      }
    }
  }
}

class _UpdateIndependentReportSheet extends StatefulWidget {
  const _UpdateIndependentReportSheet({required this.caseId, required this.initial});
  final String caseId;
  final Map<String, dynamic> initial;

  @override
  State<_UpdateIndependentReportSheet> createState() => _UpdateIndependentReportSheetState();
}

class _UpdateIndependentReportSheetState extends State<_UpdateIndependentReportSheet> {
  // Both ways in ("I have reported it" / "Update details") mean the
  // reporter has filed; they can switch it off to add only an update.
  bool _reported = true;
  late final _office = TextEditingController(text: widget.initial['reportedTo'] as String? ?? '');
  late final _reference = TextEditingController(text: widget.initial['referenceNumber'] as String? ?? '');
  late final _notes = TextEditingController(text: widget.initial['notes'] as String? ?? '');
  late DateTime? _on = (widget.initial['reportedOn'] as Timestamp?)?.toDate();
  bool _saving = false;

  @override
  void dispose() {
    _office.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reported && _office.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Please say which office you reported it to.', kind: AppMessageKind.error),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('cases').doc(widget.caseId).update({
        'independentReport': {
          'alreadyReported': _reported,
          if (_reported) ...{
            'reportedTo': _office.text.trim(),
            'referenceNumber': _reference.text.trim(),
            'reportedOn': _on == null ? null : Timestamp.fromDate(_on!),
          },
          'notes': _notes.text.trim(),
          'updatedAt': Timestamp.now(),
        },
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': _reported
                ? 'Reporter updated their report to the authorities.'
                : 'Reporter added an update.',
            'timestamp': Timestamp.now(),
          },
        ]),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not save: $e', kind: AppMessageKind.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your report to the authorities', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            IndependentReportFields(
              alreadyReported: _reported,
              onAlreadyReportedChanged: (v) => setState(() => _reported = v),
              reportedToController: _office,
              referenceController: _reference,
              reportedOn: _on,
              onReportedOnChanged: (d) => setState(() => _on = d),
            ),
            const SizedBox(height: 12),
            RescueFieldLabel('Update or new information', required: false),
            const SizedBox(height: 6),
            RescueTextField(_notes, 'e.g. Animal still chained; followed up with the barangay'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: AppButtons.primary,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
