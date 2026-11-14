import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/repos/transporter_application_repository.dart';
import 'package:respawnd1/features/admin/volunteers/application_review.dart';

/// Staff review of pet transporter verification applications. Approving or
/// rejecting also sets the transporter's `users/{uid}.isVerified` (see
/// TransporterApplicationRepository.review).
class TransporterApplicationsPage extends StatelessWidget {
  const TransporterApplicationsPage({super.key});

  static TransporterApplicationStatus _status(ApplicationTab t) => switch (t) {
        ApplicationTab.pending => TransporterApplicationStatus.pending,
        ApplicationTab.approved => TransporterApplicationStatus.approved,
        ApplicationTab.rejected => TransporterApplicationStatus.rejected,
      };

  @override
  Widget build(BuildContext context) {
    final repo = TransporterApplicationRepository();
    return ApplicationReviewPage<TransporterApplication>(
      title: 'Transporter Applications',
      noun: 'transporter applications',
      watch: (t) => repo.watchByStatus(_status(t)),
      summarize: transporterSummary,
      approveMessage: (app) => '${app.name.isEmpty ? 'This applicant' : app.name} will be marked verified and can '
          'receive transport requests.',
      save: (app, approve, reviewer, note) =>
          repo.review(uid: app.uid, approve: approve, reviewerUid: reviewer, note: note),
    );
  }
}

/// A transporter application as the shared card shows it.
ApplicationSummary transporterSummary(TransporterApplication app) {
  final vehicle = [app.vehicleType, app.licensePlate].whereType<String>().join(' · ');
  return ApplicationSummary(
    name: app.name,
    phone: app.mobileNumber,
    lines: [('Vehicle', vehicle), if (app.documents.isEmpty) ('Documents', 'None uploaded')],
    submittedAt: app.submittedAt,
    reviewedAt: app.status == TransporterApplicationStatus.pending ? null : app.reviewedAt,
    reviewNote: app.reviewNote,
    extra: app.documents.isEmpty
        ? null
        : SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: app.documents.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _DocumentThumb(doc: app.documents[i]),
            ),
          ),
  );
}

/// Read-only card for the transporter detail page.
class TransporterApplicationCard extends StatelessWidget {
  const TransporterApplicationCard({super.key, required this.app});

  final TransporterApplication app;

  @override
  Widget build(BuildContext context) => ApplicationCard(summary: transporterSummary(app));
}

class _DocumentThumb extends StatelessWidget {
  const _DocumentThumb({required this.doc});

  final ({String label, String url}) doc;

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.network(doc.url, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Text(doc.label, style: GoogleFonts.zain(fontSize: 14, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                doc.url,
                width: 96,
                height: 66,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 66,
                  color: AppColors.slaterspwn,
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(doc.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
