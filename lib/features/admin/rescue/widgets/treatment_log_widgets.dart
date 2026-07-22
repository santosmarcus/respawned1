import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';

/// Shared treatment-log rendering — the same compact card + expandable
/// detail sheet used by both treatment_detail_page.dart's Treatment Logs
/// list and the Animal Record Medical tab's episode expansion, so a
/// treatment log looks and behaves identically no matter which screen
/// surfaces it. Not a second/parallel treatment-log system — this IS the
/// one renderer, just made public so it isn't reimplemented per screen.
const String kNotProvided = 'Not provided';

String _monthName(int month) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][month - 1];

String _fmtDateTime(DateTime d) =>
    '${_monthName(d.month)} ${d.day}, ${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void showFullTreatmentImage(BuildContext context, String url) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          child: Image.network(
            url,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
          ),
        ),
      ),
    ),
  );
}

/// Compact preview card — tap opens [TreatmentLogDetailSheet].
class TreatmentLogCard extends StatelessWidget {
  final TreatmentLogEntry log;
  const TreatmentLogCard({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final d = log.displayDate;
    final dateStr = d != null ? '${_monthName(d.month)} ${d.day}, ${d.year}' : '';

    final subLines = <String>[
      if (log.medicationName != null && log.medicationName!.isNotEmpty)
        'Medication: ${log.medicationName}${(log.medicationDose ?? '').isNotEmpty ? ' (${log.medicationDose})' : ''}',
      if (log.procedurePerformed != null && log.procedurePerformed!.isNotEmpty)
        'Procedure: ${log.procedurePerformed}',
      if (log.vaccineName != null && log.vaccineName!.isNotEmpty)
        'Vaccine: ${log.vaccineName}${(log.vaccineDose ?? '').isNotEmpty ? ' (${log.vaccineDose})' : ''}',
      if (log.dischargeNotes != null && log.dischargeNotes!.isNotEmpty) log.dischargeNotes!,
      if (log.causeOfDeath != null && log.causeOfDeath!.isNotEmpty) 'Cause: ${log.causeOfDeath}',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.background,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => TreatmentLogDetailSheet(log: log),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.tearspwn.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(8)),
                  child: log.mediaUrls.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(log.mediaUrls.first,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) => progress == null
                                  ? child
                                  : const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 18)),
                        )
                      : const Icon(Icons.description_outlined, size: 18, color: AppColors.textSecondary),
                ),
                if (log.mediaUrls.length > 1)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(8)),
                      child: Text('+${log.mediaUrls.length - 1}',
                          style: GoogleFonts.zain(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.type,
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (log.notes.isNotEmpty)
                    Text(log.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  for (final line in subLines)
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if (log.createdBy != null && log.createdBy!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('By ${log.createdBy}',
                          style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (log.condition != null && log.condition!.isNotEmpty)
                  Text(log.condition!,
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(dateStr, style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One centralized renderer for every treatment-log detail view — so old
/// and new logs (and every update type, and every screen: Treatment
/// Details, Animal Record Medical tab) are shown consistently. Every
/// applicable question from the Add Update form gets its own row here
/// unconditionally, falling back to "Not provided" rather than being
/// hidden, so a submitted-but-empty-looking answer is never confused with a
/// field that was never asked.
class TreatmentLogDetailSheet extends StatelessWidget {
  final TreatmentLogEntry log;
  const TreatmentLogDetailSheet({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final displayDate = log.displayDate;
    final dateStr = displayDate != null
        ? '${_monthName(displayDate.month)} ${displayDate.day}, ${displayDate.year}'
        : kNotProvided;

    String orNotProvided(String? v) => (v == null || v.isEmpty) ? kNotProvided : v;

    final rows = <(String, String)>[
      ('Update Type', log.type),
      ('Date', dateStr),
      ('Overall Condition', orNotProvided(log.condition)),
      ('Notes', orNotProvided(log.notes)),
      ('Medication Name', orNotProvided(log.medicationName)),
      ('Dose', orNotProvided(log.medicationDose)),
      ('Procedure', orNotProvided(log.procedurePerformed)),
      ('Vaccine', orNotProvided(log.vaccineName)),
      ('Vaccine Dose', orNotProvided(log.vaccineDose)),
      ('Next Schedule', log.nextScheduleAt != null ? _fmtDateTime(log.nextScheduleAt!) : kNotProvided),
      ('Discharge Notes', orNotProvided(log.dischargeNotes)),
      ('Final Condition', orNotProvided(log.finalCondition)),
      ('Post-treatment Instructions', orNotProvided(log.postTreatmentInstructions)),
      ('Cause of Death', orNotProvided(log.causeOfDeath)),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(log.type, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              for (final (label, value) in rows) ...[
                Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
              ],
              Text('Images and Videos', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (log.mediaUrls.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(kNotProvided, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final url in log.mediaUrls)
                      GestureDetector(
                        onTap: () => showFullTreatmentImage(context, url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            url,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : Container(
                                    width: 84,
                                    height: 84,
                                    color: AppColors.tearspwn,
                                    child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                                  ),
                            errorBuilder: (_, __, ___) => Container(
                              width: 84,
                              height: 84,
                              color: AppColors.tearspwn,
                              child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text('Created By', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(orNotProvided(log.createdBy), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text('Created At', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(log.timestamp != null ? _fmtDateTime(log.timestamp!) : kNotProvided,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
