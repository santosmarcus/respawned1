import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/repos/clinic_search_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/repos/saved_clinics_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/clinic_picker_body.dart';

/// What the Select Clinic sheet actually did, so callers never have to
/// guess what a bare `null`/non-null pop result means. Fixes a real bug:
/// dismissing the sheet (back button, tap-outside, swipe-down) used to be
/// indistinguishable from "continue to Assign Rider" at some call sites,
/// which sent admins to Assign Rider even when they'd cancelled.
enum ClinicSheetResult { cancelled, clinicSaved, assignRider }

class ClinicSheetOutcome {
  final ClinicSheetResult result;
  final ClinicSearchResult? clinic;
  const ClinicSheetOutcome._(this.result, this.clinic);
  const ClinicSheetOutcome.cancelled() : this._(ClinicSheetResult.cancelled, null);
  const ClinicSheetOutcome.clinicSaved(ClinicSearchResult clinic)
      : this._(ClinicSheetResult.clinicSaved, clinic);
  const ClinicSheetOutcome.assignRider(ClinicSearchResult clinic)
      : this._(ClinicSheetResult.assignRider, clinic);
}

/// Select Clinic modal — map/Places search, select a result, save it to
/// the case, and (when [offerAssignRider] is true) continue straight to
/// Assign Rider. The picker UI itself (map/search/Saved+Nearby
/// sections/bookmarks/closed-clinic warning) lives in the shared
/// [ClinicPickerBody] — this function only wires its [onConfirm] to
/// actually persist the pick onto the case via
/// [RescueCaseRepository.assignClinic]/[RescueCaseRepository.changeClinic].
/// The sheet performs the save itself and waits for it to succeed before
/// returning [ClinicSheetResult.clinicSaved] or
/// [ClinicSheetResult.assignRider] — a failed save keeps the sheet open
/// with an error instead of popping. Dismissing the sheet any other way
/// (back button, tap-outside, drag-to-close) always resolves to
/// [ClinicSheetResult.cancelled], never [ClinicSheetResult.assignRider].
///
/// [offerAssignRider] should be false when reassigning a clinic on a case
/// that already has a rider (e.g. from the Ongoing/In Treatment "Reassign
/// Clinic" action) — there, "continue to Assign Rider" doesn't apply, so
/// the primary action is just "Save Clinic".
///
/// [centerLat]/[centerLng] seed the initial nearby search and map camera —
/// normally the rescue case's own location. [currentClinicName] and the
/// rest of the `currentClinic*` fields describe whatever is already saved
/// on the case (if any) — passing the full set (not just name/address)
/// lets the sheet actually restore it as the *selected* clinic on open,
/// not just show it as an informational banner.
Future<ClinicSheetOutcome> showSelectClinicSheet(
  BuildContext context, {
  required ClinicSearchRepository repository,
  required RescueCaseRepository caseRepository,
  required SavedClinicsRepository savedClinicsRepository,
  required String caseId,
  required String actorUid,
  required String actorName,
  double? centerLat,
  double? centerLng,
  String? currentClinicName,
  String? currentClinicAddress,
  String? currentClinicPlaceId,
  double? currentClinicLat,
  double? currentClinicLng,
  String? currentClinicPhone,
  bool offerAssignRider = true,
  // Set when this sheet is opened as a mid-tracking reselection (spec §7)
  // rather than the initial pick — makes the confirm step call
  // RescueCaseRepository.changeClinic (which names both clinics in the
  // timeline entry) instead of assignClinic.
  String? previousClinicName,
}) async {
  ClinicSearchResult? initialClinic;
  if (currentClinicPlaceId != null &&
      currentClinicPlaceId.isNotEmpty &&
      currentClinicLat != null &&
      currentClinicLng != null &&
      currentClinicName != null) {
    initialClinic = ClinicSearchResult(
      placeId: currentClinicPlaceId,
      name: currentClinicName,
      address: currentClinicAddress ?? '',
      lat: currentClinicLat,
      lng: currentClinicLng,
      phone: currentClinicPhone,
    );
  }

  final outcome = await showModalBottomSheet<ClinicSheetOutcome>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => ClinicPickerBody(
      repository: repository,
      savedClinicsRepository: savedClinicsRepository,
      actorUid: actorUid,
      centerLat: centerLat,
      centerLng: centerLng,
      initialClinic: initialClinic,
      title: 'Select Clinic',
      confirmLabel: offerAssignRider ? 'Assign Transporter' : 'Save Clinic',
      onConfirm: (clinic, closedWarningAcknowledged) async {
        final availabilityStatus = clinic.openNow == null ? null : (clinic.openNow! ? 'open' : 'closed');
        if (previousClinicName != null) {
          await caseRepository.changeClinic(
            caseId: caseId,
            previousClinicName: previousClinicName,
            clinicName: clinic.name,
            clinicAddress: clinic.address,
            clinicPlaceId: clinic.placeId,
            clinicLat: clinic.lat,
            clinicLng: clinic.lng,
            clinicPhone: clinic.phone,
            actorUid: actorUid,
            actorName: actorName,
            availabilityStatus: availabilityStatus,
            closedWarningAcknowledged: closedWarningAcknowledged,
          );
        } else {
          await caseRepository.assignClinic(
            caseId: caseId,
            clinicName: clinic.name,
            clinicAddress: clinic.address,
            clinicPlaceId: clinic.placeId,
            clinicLat: clinic.lat,
            clinicLng: clinic.lng,
            clinicPhone: clinic.phone,
            actorUid: actorUid,
            actorName: actorName,
            availabilityStatus: availabilityStatus,
            closedWarningAcknowledged: closedWarningAcknowledged,
          );
        }
        if (!sheetContext.mounted) return;
        Navigator.pop(
          sheetContext,
          offerAssignRider ? ClinicSheetOutcome.assignRider(clinic) : ClinicSheetOutcome.clinicSaved(clinic),
        );
      },
    ),
  );
  // showModalBottomSheet returns null for every dismissal path (back
  // button, tap-outside, swipe-down) — normalize that to an explicit
  // cancelled outcome so callers never branch on null.
  return outcome ?? const ClinicSheetOutcome.cancelled();
}
