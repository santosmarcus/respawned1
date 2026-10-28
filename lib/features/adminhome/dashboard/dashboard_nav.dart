import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_detail_page.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/adoption/return_details_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_home.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_info.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/volunteers/volunteers_page.dart';

/// Every dashboard tap opens an EXISTING screen with that screen's own
/// constructor — the dashboard never creates its own record views.

void _push(BuildContext context, WidgetBuilder builder) => Navigator.push(context, MaterialPageRoute(builder: builder));

/// Mirrors RescueReportsPage._navigateToDetail's status → screen mapping
/// (kept private there), so a case opens exactly where it would from the
/// Rescue Reports list.
void openRescueCase(BuildContext context, RescueCase c) {
  switch (c.status) {
    case RescueStatus.awaitingAssignment:
      _push(context, (_) => AssignRiderPage(caseId: c.id, data: c.raw));
    case RescueStatus.ongoing:
      _push(context, (_) => AdminTrackCasePage(caseId: c.id, data: c.raw));
    case RescueStatus.treatment:
      _push(context, (_) => TreatmentDetailPage(caseId: c.id, data: c.raw));
    case RescueStatus.intake:
      _push(context, (_) => IntakeDetailPage(caseId: c.id, data: c.raw));
    default:
      _push(context, (_) => RescueDetailPage(caseId: c.id, data: c.raw));
  }
}

/// Same as the Rescue Reports Intake tab: a mixed-stage case (one animal
/// still in treatment) opens Intake Details for only its intake animals.
void openIntakeCase(BuildContext context, RescueCase c) {
  final indexes = c.animals.isNotEmpty ? animalIndexesInStage(c, 'intake') : const <int>[];
  _push(context, (_) => IntakeDetailPage(caseId: c.id, data: c.raw, animalIndexes: indexes.isEmpty ? null : indexes));
}

/// Treatment Details for a case regardless of an intake split — used by
/// vet-care rows that are specifically about the clinical record.
void openTreatment(BuildContext context, RescueCase c) =>
    _push(context, (_) => TreatmentDetailPage(caseId: c.id, data: c.raw));

void openRescueTab(BuildContext context, WidgetRef ref, RescuePipelineTab tab) {
  ref.read(rescuePipelineTabProvider.notifier).select(tab);
  _push(context, (_) => const RescueReportsPage());
}

void openAnimalRecord(BuildContext context, AnimalRecord a) =>
    _push(context, (_) => AnimalRecordDetailPage(animalId: a.id, data: a.raw));

void openAnimalRecords(BuildContext context) => _push(context, (_) => const AnimalRecordsPage());

void openAdoptionQueue(BuildContext context, AdoptionStatus status) =>
    _push(context, (_) => AdoptionApplicationReviewPage(initialStatus: status));

void openApplication(BuildContext context, AdoptionApplication app) =>
    _push(context, (_) => AdoptionApplicationDetailPage(applicationId: app.id));

void openReturn(BuildContext context, AdoptionApplication app) =>
    _push(context, (_) => ReturnDetailsPage(applicationId: app.id));

void openDonationsAdmin(BuildContext context) => _push(context, (_) => const DonationAdminHomeScreen());

void openCampaign(BuildContext context, String campaignId) =>
    _push(context, (_) => DonationAdminInfoPage(campaignId: campaignId));

void openVolunteers(BuildContext context) => _push(context, (_) => const VolunteersPage());
