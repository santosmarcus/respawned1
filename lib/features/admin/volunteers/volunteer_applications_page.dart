import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/volunteer/volunteer_application.dart';
import 'package:respawnd1/core/repos/volunteer_application_repository.dart';
import 'package:respawnd1/features/admin/volunteers/application_review.dart';

/// Staff review of general volunteer applications (paper 1.4.5).
class VolunteerApplicationsPage extends StatelessWidget {
  const VolunteerApplicationsPage({super.key});

  static VolunteerApplicationStatus _status(ApplicationTab t) => switch (t) {
        ApplicationTab.pending => VolunteerApplicationStatus.pending,
        ApplicationTab.approved => VolunteerApplicationStatus.approved,
        ApplicationTab.rejected => VolunteerApplicationStatus.rejected,
      };

  @override
  Widget build(BuildContext context) {
    final repo = VolunteerApplicationRepository();
    return ApplicationReviewPage<VolunteerApplication>(
      title: 'Volunteer Applications',
      noun: 'volunteer applications',
      watch: (t) => repo.watchByStatus(_status(t)),
      summarize: (app) => ApplicationSummary(
        name: app.name,
        phone: app.phone,
        lines: [
          ('Helps with', app.categories.map((c) => c.label).join(', ')),
          ('Available', app.availability),
          ('Area', app.serviceArea),
          ('Experience', app.experience),
        ],
        submittedAt: app.submittedAt,
        reviewedAt: app.status == VolunteerApplicationStatus.pending ? null : app.reviewedAt,
        reviewNote: app.reviewNote,
      ),
      approveMessage: (app) => '${app.name.isEmpty ? 'This applicant' : app.name} becomes an approved volunteer '
          'for the activities they applied for.',
      save: (app, approve, reviewer, note) =>
          repo.review(uid: app.uid, approve: approve, reviewerUid: reviewer, note: note),
    );
  }
}
