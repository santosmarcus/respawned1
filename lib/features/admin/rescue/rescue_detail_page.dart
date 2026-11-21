import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart' show animalsAfterShelterDropoff;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:respawnd1/core/models/rescue/case_claim_rules.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/activity_log_entry.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:respawnd1/core/widgets/rescue_risk_banner.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/accept_case_sheet.dart';
import 'package:respawnd1/features/rescue/widgets/case_report_details.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';
import 'package:respawnd1/features/admin/rescue/expenses/case_costs_card.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_messages_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_flow.dart';
import 'package:respawnd1/features/admin/rescue/widgets/community_reports_section.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/rescue/widgets/export_transfer_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/merge_history_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/ownership_status_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/possible_duplicate_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/referral_history_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/rescue_adoption_request_card.dart';
import 'package:respawnd1/features/admin/rescue/widgets/rejection_reason_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/report_verification_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/features/organization/widgets/shelter_pin_prompt.dart';
import 'package:respawnd1/features/admin/rescue/widgets/success_dialog.dart';
import 'package:respawnd1/core/geofence/geofence_config.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

class RescueDetailPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const RescueDetailPage({super.key, required this.caseId, required this.data});

  @override
  ConsumerState<RescueDetailPage> createState() => _RescueDetailPageState();
}

class _RescueDetailPageState extends ConsumerState<RescueDetailPage> {
  bool _isLoading = false;
  String _actorName = 'Staff';

  @override
  void initState() {
    super.initState();
    _loadActorName();
  }

  Future<void> _loadActorName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    final name = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'
        .trim();
    if (mounted && name.isNotEmpty) setState(() => _actorName = name);
  }

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _acceptCase(RescueCase c) async {
    final result = await showAcceptCaseSheet(context);
    if (result == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final organizationId = await ref.read(currentOrganizationIdProvider.future);
      await ref
          .read(rescueCaseRepositoryProvider)
          .acceptCase(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
        organizationId: organizationId,
        openForTransfer: result.openForTransfer,
        readinessSnapshot: result.readinessSnapshot,
      );
    } on CaseClaimException catch (e) {
      // Someone else took it first, or an independent rescuer can't take it
      // yet: say so, and leave a case that's gone.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
        if (e.alreadyTaken) Navigator.maybePop(context);
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not accept case: $e', kind: AppMessageKind.error),
        );
      }
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = false);

    // Straight to Assign Transport: the clinic and the transporter are
    // picked on that one page. Backing out leaves the case accepted with
    // no clinic yet, shown below as "Assign Transport".
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)),
      );
    }
  }

  /// Shared Close Case flow (spec §2) — every screen that can close a case
  /// calls the same performCloseCase helper (one repository call path, not
  /// a separate implementation per page). Guarded by [_isLoading] so a
  /// double-tap can't fire two closures.
  Future<void> _closeCase(RescueCase c, {ClosureReason? initialReason}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final outcome = await performCloseCase(
        context,
        ref,
        c,
        initialReason: initialReason,
      );
      if (outcome.acted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(outcome.wholeCaseClosed
              ? 'Case closed.'
              : 'Animal marked deceased.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not close case: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateOwnership(RescueCase c) async {
    final raw = c.raw;
    final result = await showOwnershipStatusSheet(
      context,
      currentOwnershipStatus: raw['ownershipStatus'] as String?,
      currentCategory: raw['ownedAnimalCategory'] as String?,
      currentOwnerName: raw['ownerName'] as String?,
      currentOwnerContact: raw['ownerContact'] as String?,
      currentNotes: raw['ownershipNotes'] as String?,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .updateOwnershipInfo(
        caseId: c.id,
        ownershipStatus: result.ownershipStatus,
        ownedAnimalCategory: result.ownedAnimalCategory,
        ownerName: result.ownerName,
        ownerContact: result.ownerContact,
        ownershipNotes: result.ownershipNotes,
        actorUid: _actorUid,
        actorName: _actorName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not save ownership info: $e', kind: AppMessageKind.error),
        );
      }
    }
  }

  /// "Contact owner" (spec §1) — this app has no owner-messaging channel,
  /// so this surfaces the stored contact info for the admin to reach out
  /// through their own means, rather than a fake "message sent" action.
  void _contactOwner(RescueCase c) {
    final name = c.raw['ownerName'] as String?;
    final contact = c.raw['ownerContact'] as String?;
    showInfoDialog(context, title: 'Owner Contact', message: (contact == null || contact.isEmpty)
        ? 'No owner contact information has been recorded yet. Use Update Ownership Info to add it.'
        : '${name != null && name.isNotEmpty ? '$name\n' : ''}$contact');
  }

  /// "Retry with a different transporter" after a safety report (spec
  /// §3) — requires the admin to acknowledge the warning before the case
  /// even becomes reassignable, then hands off to the existing Assign
  /// Transporter screen exactly as normal (no transporter is auto-picked).
  Future<void> _retryWithDifferentTransporter(RescueCase c) async {
    final notes = c.raw['endReasonNotes'] as String?;
    final acknowledged = await showConfirmActionDialog(context, title: 'Acknowledge Safety Warning', message: 'A previous transporter reported that this animal may be aggressive.'
        '${notes != null && notes.isNotEmpty ? '\n\n"$notes"' : ''}'
        '\n\nDo you acknowledge this before selecting another transporter?', confirmLabel: 'I Acknowledge');
    if (acknowledged != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .resumeAssignmentAfterSafetyReport(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not resume assignment: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Transporter stopped the trip (End Reason Other): back to Assign
  /// Transporter.
  Future<void> _returnToAssignAfterTransitEnded(RescueCase c) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Choose another transporter?',
      message: 'The case goes back to Assign Transporter. The transporter\'s report stays on the case.',
      confirmLabel: 'Assign Transporter',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).returnToAssignmentAfterTransitEnded(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not return the case to Assign: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _keepTransporterWithInstructions(RescueCase c) async {
    final note = await showTextInputDialog(
      context,
      title: 'Instructions for Transporter',
      label: 'Instructions',
      hint: 'e.g. use a carrier, approach from the left, wait for backup',
      required: true,
    );
    if (note == null || note.isEmpty || !mounted) return;
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .addSafetyResponseNote(
        caseId: c.id,
        note: note,
        actorUid: _actorUid,
        actorName: _actorName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not save instructions: $e', kind: AppMessageKind.error),
        );
      }
    }
  }

  /// Single entry point for the Select Clinic sheet, used both right after
  /// Accept and from the standalone Select/Reassign Clinic action below.
  /// The sheet performs its own save and returns an explicit
  /// [ClinicSheetResult] — this only reacts to that result, it never
  /// assumes "the sheet closed" means "continue".
  Future<void> _openClinicSheet(
      RescueCase c, {
        required bool offerAssignRider,
      }) async {
    final outcome = await showSelectClinicSheet(
      context,
      repository: ref.read(clinicSearchRepositoryProvider),
      caseRepository: ref.read(rescueCaseRepositoryProvider),
      savedClinicsRepository: ref.read(savedClinicsRepositoryProvider),
      caseId: c.id,
      actorUid: _actorUid,
      actorName: _actorName,
      centerLat: c.lat,
      centerLng: c.lng,
      currentClinicName: c.vetClinicName,
      currentClinicAddress: c.vetClinicAddress,
      currentClinicPlaceId: c.vetClinicPlaceId,
      currentClinicLat: c.vetClinicLat,
      currentClinicLng: c.vetClinicLng,
      currentClinicPhone: c.vetClinicPhone,
      offerAssignRider: offerAssignRider,
    );
    if (!mounted) return;

    switch (outcome.result) {
      case ClinicSheetResult.cancelled:
      // Remain on Rescue Details. Nothing to undo — nothing was saved.
        break;
      case ClinicSheetResult.clinicSaved:
        await showSuccessDialog(
          context,
          title: 'Clinic Saved',
          message: outcome.clinic?.name,
        );
        break;
      case ClinicSheetResult.assignRider:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw),
          ),
        );
        break;
    }
  }

  Future<void> _rejectCase(RescueCase c) async {
    final result = await showRejectionReasonSheet(context);
    if (result == null || !mounted) return;

    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Reject This Report?',
      message:
      'The reporter will see this report was rejected: ${result.reason.label}.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .rejectCase(
        caseId: c.id,
        reason: result.reason,
        otherText: result.otherText,
        actorUid: _actorUid,
        actorName: _actorName,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not reject case: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The team can't finish the trip: back to Awaiting Assignment, then
  /// straight to Assign Transporter.
  Future<void> _stopOrganizationTransport(RescueCase c) async {
    final reason = await showTextInputDialog(
      context,
      title: 'Switch to a transporter?',
      message: 'The case goes back to waiting for a transporter, and you can offer it to one now.',
      label: 'What happened (optional)',
      confirmLabel: 'Switch',
    );
    if (reason == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).stopOrganizationTransport(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
        reason: reason,
      );
      if (!mounted) return;
      _push(AssignRiderPage(
        caseId: c.id,
        data: {...c.raw, 'status': RescueStatus.awaitingAssignment.firestoreValue}..remove('organizationTransport'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not switch: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// "Straight to shelter" trip by the team: arrival moves the case to
  /// Intake, where staff confirm the animal was received.
  Future<void> _confirmOrganizationAtShelter(RescueCase c) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Animal arrived at the shelter?',
      message: 'The case moves to Intake, where you confirm the animal was received and create its record.',
      confirmLabel: 'Arrived at Shelter',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final now = Timestamp.now();
      final animals = animalsAfterShelterDropoff(
        [for (final a in (c.raw['animals'] as List?) ?? const []) if (a is Map) Map<String, dynamic>.from(a)],
        now,
      );
      await ref.read(rescueCaseRepositoryProvider).confirmOrganizationTransportAtShelter(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
        animals: animals,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IntakeDetailPage(
            caseId: c.id,
            data: {...c.raw, 'status': RescueStatus.intake.firestoreValue, if (animals.isNotEmpty) 'animals': animals},
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not record the arrival: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmOrganizationArrived(RescueCase c) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Animal arrived at the clinic?',
      message: 'The case moves to In Treatment.',
      confirmLabel: 'Start Treatment',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).confirmOrganizationTransportArrived(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TreatmentDetailPage(
            caseId: c.id,
            data: {...c.raw, 'status': RescueStatus.treatment.firestoreValue},
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not start treatment: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _referCase(RescueCase c) async {
    final sent = await showReferCaseSheet(
      context,
      rescueCase: c,
      caseRepository: ref.read(rescueCaseRepositoryProvider),
      organizationDirectory: ref.read(organizationDirectoryRepositoryProvider),
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (sent && mounted) {
      await showSuccessDialog(
        context,
        title: 'Referral Sent',
        message: 'The case status has been updated to Referred.',
      );
    }
  }

  /// The receiving organization accepts a referral: it becomes the owner and
  /// the case enters its Rescue Review.
  Future<void> _acceptReferral(RescueCase c) async {
    if (_isLoading) return;
    final from = _referralInfo(c)['fromOrgName'] as String?;
    final ok = await showConfirmActionDialog(
      context,
      title: 'Accept referral?',
      message: 'Your organization takes over this case${from == null || from.isEmpty ? '' : ' from $from'}. '
          'It moves to your Rescue Review.',
      confirmLabel: 'Accept',
    );
    if (!ok || !mounted) return;
    await _runReferralAnswer(
          () => ref.read(rescueCaseRepositoryProvider).acceptReferral(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
      ),
      done: 'Referral accepted. The case is in your Rescue Review.',
    );
  }

  /// The receiving organization declines a referral with a reason; the case
  /// goes back to the referring organization's Rescue Review.
  Future<void> _declineReferral(RescueCase c) async {
    if (_isLoading) return;
    final reason = await showTextInputDialog(
      context,
      title: 'Decline referral',
      message: 'The case goes back to the referring organization with your reason.',
      label: 'Reason',
      hint: 'e.g. no space for this species, outside our area',
      confirmLabel: 'Decline',
      required: true,
      destructive: true,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await _runReferralAnswer(
          () => ref.read(rescueCaseRepositoryProvider).declineReferral(
        caseId: c.id,
        reason: reason,
        actorUid: _actorUid,
        actorName: _actorName,
      ),
      done: 'Referral declined. The referring organization has been told.',
    );
  }

  Future<void> _runReferralAnswer(Future<void> Function() action, {required String done}) async {
    setState(() => _isLoading = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(done));
    } catch (e) {
      if (mounted) {
        final msg = e is StateError ? e.message : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not answer the referral: $msg', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static Map<String, dynamic> _referralInfo(RescueCase c) =>
      c.raw['referral'] is Map ? Map<String, dynamic>.from(c.raw['referral'] as Map) : const {};

  Future<void> _mergeDuplicate(RescueCase c) async {
    final acted = await showPossibleDuplicateSheet(
      context,
      sourceCase: c,
      repository: ref.read(rescueCaseRepositoryProvider),
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (acted && mounted) {
      await showSuccessDialog(context, title: 'Duplicate Reviewed');
    }
  }

  void _openCase(String caseId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RescueDetailPage(caseId: caseId, data: const {}),
      ),
    );
  }

  /// The referring organization takes an unanswered referral back (org or
  /// LGU). The case returns to the status it had before, and the refer
  /// sheet can then send it somewhere else.
  Future<void> _withdrawReferral(RescueCase c) async {
    if (_isLoading) return;
    final target = (c.raw['referredToOrgId'] as String? ?? '').isEmpty
        ? 'the LGU/barangay'
        : (_referralInfo(c)['targetOrgName'] as String? ?? 'the receiving organization');
    final reason = await showTextInputDialog(
      context,
      title: 'Withdraw referral & reopen',
      message: 'The referral to $target is cancelled and the case comes back to you as it was before. '
          'You can then handle it or refer it to someone else.',
      label: 'Reason',
      hint: 'e.g. no answer yet and the animal needs help now',
      confirmLabel: 'Withdraw & reopen',
      required: true,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).withdrawReferral(
        caseId: c.id,
        reason: reason,
        actorUid: _actorUid,
        actorName: _actorName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Referral withdrawn. The case is open again.'),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is StateError ? e.message : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not withdraw the referral: $msg', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _exportTransfer(RescueCase c) => showExportTransferSheet(
    context,
    rescueCase: c,
    transferredByUid: _actorUid,
    transferredByName: _actorName,
  );

  void _openMedia(RescueCase c, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            _PhotoCarousel(
              photoUrls: c.photoUrls,
              videoUrls: c.videoUrls,
              initialIndex: index,
              height: MediaQuery.of(ctx).size.height * 0.6,
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// Statuses a case can be referred from, where a returned/withdrawn
  /// referral is still worth mentioning.
  static const _reviewStatuses = {
    RescueStatus.pendingReview,
    RescueStatus.verifying,
    RescueStatus.accepted,
    RescueStatus.transitEnded,
    RescueStatus.needsSpecializedAssistance,
  };

  /// One primary, one secondary, the rest in the overflow — the same
  /// actions, conditions and handlers the page has always offered for each
  /// status.
  ({CaseAction? primary, CaseAction? secondary, List<CaseAction> overflow}) _actionsFor(
      RescueCase c, {
        required bool canManageOrgActions,
        required bool hasActiveAssignment,
        required String? myOrgId,
      }) {
    CaseAction? primary;
    CaseAction? secondary;
    final overflow = <CaseAction>[];
    final export = CaseAction('Export transfer details', () => _exportTransfer(c), icon: Icons.ios_share);
    final reassignClinic = CaseAction(
      // No clinic name: the button stays the same size as its primary
      // (e.g. Track Case). The clinic shows on the case details.
      c.vetClinicName == null ? 'Assign Clinic' : 'Reassign Clinic',
          () => _openClinicSheet(c, offerAssignRider: false),
      icon: Icons.local_hospital_outlined,
    );
    final specializedTransport =
        (c.raw['endReason'] as String?) == 'Animal requires specialized transport that I cannot provide';

    switch (c.status) {
      case RescueStatus.referred:
        final target = c.raw['referredToOrgId'] as String? ?? '';
        if (target.isNotEmpty && target == myOrgId) {
          primary = CaseAction('Accept referral', () => _acceptReferral(c));
          secondary = CaseAction('Decline', () => _declineReferral(c), destructive: true);
        } else {
          primary = CaseAction(
            canManageOrgActions ? 'Withdraw referral & reopen' : 'Withdraw (Admin only)',
            canManageOrgActions ? () => _withdrawReferral(c) : null,
            icon: Icons.undo,
          );
        }
      case RescueStatus.pendingReview:
      case RescueStatus.verifying:
        primary = CaseAction('Accept', () => _acceptCase(c));
        secondary = CaseAction('Reject', () => _rejectCase(c), destructive: true);
        overflow.addAll([
          CaseAction(canManageOrgActions ? 'Refer' : 'Refer (Admin only)',
              canManageOrgActions ? () => _referCase(c) : null, icon: Icons.forward_outlined),
          CaseAction(canManageOrgActions ? 'Check for Duplicates / Merge' : 'Merge (Admin only)',
              canManageOrgActions ? () => _mergeDuplicate(c) : null, icon: Icons.call_merge),
        ]);
      case RescueStatus.possibleDuplicate:
        primary = CaseAction('Review Possible Duplicate', () => _mergeDuplicate(c));
      case RescueStatus.accepted:
      case RescueStatus.awaitingAssignment:
      // Derived from saved case data, not local state: no clinic yet means
      // Select Clinic (also covers animal-record admissions, which start at
      // awaitingAssignment with no clinic); an outstanding offer routes to
      // its status view instead of a second Assign Transporter.
        if (!c.hasTransportDestination) {
          primary = CaseAction('Assign Transport', () => _push(AssignRiderPage(caseId: c.id, data: c.raw)));
        } else if (hasActiveAssignment) {
          primary = CaseAction('View Assignment Status', () => _push(AdminTrackCasePage(caseId: c.id, data: c.raw)));
        } else {
          primary = CaseAction('Assign Transporter', () => _push(AssignRiderPage(caseId: c.id, data: c.raw)));
        }
      case RescueStatus.ongoing when c.raw['organizationTransport'] is Map && c.goesToShelter:
        primary = CaseAction('Arrived at Shelter', () => _confirmOrganizationAtShelter(c));
        secondary = CaseAction('Switch to a Transporter', () => _stopOrganizationTransport(c));
        overflow.add(CaseAction('Close Case', () => _closeCase(c), icon: Icons.block, destructive: true));
      case RescueStatus.ongoing when c.raw['organizationTransport'] is Map:
        primary = CaseAction('Arrived — Start Treatment', () => _confirmOrganizationArrived(c));
        secondary = CaseAction('Switch to a Transporter', () => _stopOrganizationTransport(c));
        overflow.add(CaseAction('Close Case', () => _closeCase(c), icon: Icons.block, destructive: true));
      case RescueStatus.ongoing:
        primary = CaseAction('Track Case', () => _push(AdminTrackCasePage(caseId: c.id, data: c.raw)));
        secondary = reassignClinic;
        overflow.add(CaseAction('Close Case', () => _closeCase(c), icon: Icons.block, destructive: true));
      case RescueStatus.treatment:
        secondary = reassignClinic;
      case RescueStatus.needsSpecializedAssistance:
        primary = CaseAction('Retry with a Different Transporter', () => _retryWithDifferentTransporter(c));
        secondary = CaseAction('Keep Transporter + Instructions', () => _keepTransporterWithInstructions(c));
        overflow.addAll([
          CaseAction('Escalate to Trained Responder / Authority', () => _referCase(c), icon: Icons.forward_outlined),
          CaseAction(
            specializedTransport
                ? 'Close Case — Specialized Transport Unavailable'
                : 'Close Case — Aggressive Animal / Unsafe Rescue',
                () => _closeCase(c,
                initialReason: specializedTransport ? ClosureReason.requiresTransport : ClosureReason.aggressive),
            icon: Icons.block,
            destructive: true,
          ),
        ]);
      case RescueStatus.transitEnded:
        final assignAnother = CaseAction('Assign Another Transporter', () => _returnToAssignAfterTransitEnded(c));
        final refer = CaseAction('Refer Case', () => _referCase(c), icon: Icons.forward_outlined);
        final close = CaseAction('Close Case', () => _closeCase(c), icon: Icons.block, destructive: true);
        if (c.raw['endReasonKind'] == 'deceased') {
          primary = CaseAction('Confirm Death', () => _closeCase(c, initialReason: ClosureReason.died));
          secondary = assignAnother;
          overflow.addAll([refer, close]);
        } else {
          primary = assignAnother;
          secondary = refer;
          overflow.add(close);
        }
      default:
        break;
    }
    overflow.add(export);
    return (primary: primary, secondary: secondary, overflow: overflow);
  }

  /// Where the case stands: the outcome for closed/rejected/referred
  /// cases, the next step for active ones, warnings from the transporter.
  Widget? _outcomeBanner(RescueCase c, {required String? myOrgId, required bool hasActiveAssignment}) {
    final referral = _referralInfo(c);
    switch (c.status) {
      case RescueStatus.rejected:
        return _RejectedBanner(rescueCase: c);
      case RescueStatus.referred:
        final target = c.raw['referredToOrgId'] as String? ?? '';
        final at = referral['referredAt'] is Timestamp ? (referral['referredAt'] as Timestamp).toDate() : null;
        final note = (referral['note'] as String?)?.trim() ?? '';
        if (target.isEmpty) {
          // LGU referrals keep only their status line on the case.
          String? lguLine;
          DateTime? lguAt;
          for (final h in c.statusHistory.reversed) {
            if (h.status.startsWith('Referred to the ') && h.status.contains('LGU/barangay')) {
              lguLine = h.status;
              lguAt = h.timestamp;
              break;
            }
          }
          return CaseOutcomeBanner(
            tone: CaseBannerTone.warning,
            icon: Icons.account_balance_outlined,
            title: 'Referred to the LGU/barangay${lguAt == null ? '' : ' · ${caseAgeLabel(lguAt)} ago'}',
            message: '${lguLine ?? 'This case was referred to the local government.'} '
                'LGU referrals don\'t come back by themselves: withdraw it to take the case back.',
          );
        }
        final targetName = (referral['targetOrgName'] as String?) ?? 'another organization';
        final fromName = (referral['fromOrgName'] as String?) ?? '';
        final isTarget = target == myOrgId;
        return CaseOutcomeBanner(
          tone: isTarget ? CaseBannerTone.info : CaseBannerTone.warning,
          icon: Icons.forward_to_inbox_outlined,
          title: isTarget
              ? 'Referred to you${fromName.isEmpty ? '' : ' by $fromName'}'
              : 'Waiting on $targetName${at == null ? '' : ' · ${caseAgeLabel(at)}'}',
          message: isTarget
              ? 'Accept to take it into your Rescue Review, or decline with a reason to send it back.'
              : 'They are reminded after $kReferralReminderHours hours; with no answer after '
              '$kReferralReturnHours hours the case comes back to your Rescue Review. '
              'You can also withdraw it now and reopen the case.',
          facts: [
            if (at != null) ('Referred', formatDateTime(at)),
            if ((referral['referredByName'] as String?)?.isNotEmpty ?? false) ('By', referral['referredByName'] as String),
            if (note.isNotEmpty) ('Note', note),
          ],
        );
      case RescueStatus.completed:
        return _CompletedBanner(rescueCase: c);
      case RescueStatus.cancelled:
        final closedAt = c.raw['closedAt'] is Timestamp ? (c.raw['closedAt'] as Timestamp).toDate() : null;
        final details = (c.raw['closureDetails'] as String?)?.trim() ?? '';
        return CaseOutcomeBanner(
          tone: CaseBannerTone.neutral,
          icon: Icons.block,
          title: 'Case closed',
          facts: [
            ('Reason', ClosureReason.fromName(c.raw['closureReason'] as String?).label),
            if (closedAt != null) ('Closed', formatDateTime(closedAt)),
            if ((c.raw['closedByName'] as String?)?.isNotEmpty ?? false) ('By', c.raw['closedByName'] as String),
            if (details.isNotEmpty) ('Details', details),
          ],
        );
      case RescueStatus.merged:
        return const CaseOutcomeBanner(
          tone: CaseBannerTone.neutral,
          icon: Icons.call_merge,
          title: 'Merged into another case',
          message: 'See History below for the case it was merged into.',
        );
      case RescueStatus.needsSpecializedAssistance:
        final specialized =
            (c.raw['endReason'] as String?) == 'Animal requires specialized transport that I cannot provide';
        final serviceType = c.raw['endReasonServiceType'] as String?;
        final notes = c.raw['endReasonNotes'] as String?;
        return CaseOutcomeBanner(
          tone: CaseBannerTone.danger,
          title: specialized ? 'Specialized transport needed' : 'Safety warning',
          message: specialized
              ? 'The assigned transporter could not provide the transport this animal needs. Arrange the right '
              'vehicle/service before assigning a new transporter.'
              : 'A previous transporter reported that the animal may be aggressive. Review the incident before '
              'assigning another transporter.',
          facts: [
            if (specialized && (serviceType?.isNotEmpty ?? false)) ('Service needed', serviceType!),
            if (notes?.isNotEmpty ?? false) ('Reported', notes!),
          ],
        );
      case RescueStatus.transitEnded:
        final deceased = c.raw['endReasonKind'] == 'deceased';
        final reason = c.raw['endReason'] as String?;
        final notes = c.raw['endReasonNotes'] as String?;
        return CaseOutcomeBanner(
          tone: CaseBannerTone.danger,
          title: deceased ? 'Animal reported deceased in transit' : 'Transporter stopped the trip',
          message: deceased
              ? 'Confirm the death to record it on the animal and close the case, or choose another step if the '
              'report was wrong.'
              : 'Decide what happens next: offer the case to another transporter, refer it, or close it.',
          facts: [
            if (!deceased && (reason?.isNotEmpty ?? false)) ('Reason', reason!),
            if (notes?.isNotEmpty ?? false) ('Reported', notes!),
          ],
        );
      case RescueStatus.ongoing when c.raw['organizationTransport'] is Map:
        return CaseOutcomeBanner(
          tone: CaseBannerTone.info,
          icon: Icons.local_shipping_outlined,
          title: (c.raw['organizationTransport'] as Map)['byChoice'] == true
              ? 'Your team is transporting'
              : 'Your organization is transporting',
          message: 'Bringing this animal to ${c.transportDestinationName} (recorded by '
              '${(c.raw['organizationTransport'] as Map)['byName'] ?? 'staff'}). '
              '${c.goesToShelter ? 'Confirm arrival to start intake.' : 'Confirm arrival to start treatment.'}',
        );
      case RescueStatus.accepted:
      case RescueStatus.awaitingAssignment:
        return CaseOutcomeBanner(
          tone: CaseBannerTone.info,
          icon: Icons.arrow_forward,
          title: !c.hasTransportDestination
              ? 'Next: choose where the animal goes'
              : hasActiveAssignment
              ? 'Waiting on the transporter'
              : 'Next: assign a transporter',
          message: !c.hasTransportDestination
              ? 'The case is accepted. Pick a clinic, or the shelter, before assigning a transporter.'
              : hasActiveAssignment
              ? 'An offer is out. Open the assignment status to follow it.'
              : c.goesToShelter
              ? 'Going straight to the shelter: ${c.transportDestinationName}.'
              : 'Clinic saved: ${c.vetClinicName}.',
        );
      default:
        break;
    }
    if (_reviewStatuses.contains(c.status)) return _referralReturnBanner(c);
    if (c.status.isAwaitingReporterResponse) {
      return CaseOutcomeBanner(
        tone: CaseBannerTone.neutral,
        icon: Icons.hourglass_empty,
        title: c.status.label,
        message: 'Waiting on the reporter. It closes by itself if they do not respond; no action is needed here.',
      );
    }
    return null;
  }

  /// A case back with this organization after a referral: who declined it
  /// and why, that nobody answered in time, or that it was withdrawn.
  Widget? _referralReturnBanner(RescueCase c) {
    final o = c.raw['referralOutcome'];
    if (o is! Map) return null;
    final status = o['status'] as String?;
    if (status != 'declined' && status != 'expired' && status != 'withdrawn') return null;
    final name = (o['targetOrgName'] as String?) ?? 'The receiving organization';
    final reason = (o['reason'] as String?)?.trim() ?? '';
    final by = (o['byName'] as String?)?.trim() ?? '';
    return CaseOutcomeBanner(
      tone: status == 'withdrawn' ? CaseBannerTone.neutral : CaseBannerTone.warning,
      icon: Icons.undo,
      title: switch (status) {
        'declined' => '$name declined the referral',
        'expired' => 'Referral returned: no answer',
        _ => 'Referral withdrawn',
      },
      message: switch (status) {
        'expired' => '$name did not answer within $kReferralReturnHours hours, so it came back to you.',
        'withdrawn' => 'The referral to $name was taken back${by.isEmpty ? '' : ' by $by'}. '
            'The case is open again; refer it elsewhere or handle it here.',
        _ => null,
      },
      facts: [if (reason.isNotEmpty && status != 'expired') ('Reason', reason)],
    );
  }

  /// Staff-only facts not on the rescue form. Everything the reporter
  /// entered is in the Report Details card (CaseReportDetails).
  List<CaseInfoItem> _reportItems(RescueCase c) {
    final d = c.raw;
    String? s(String key) => (d[key] as String?)?.trim();
    return [
      CaseInfoItem('QR/NFC',
          (c.scannedTagId != null && c.scannedTagId!.isNotEmpty) ? 'Linked (${c.scannedTagId})' : 'No'),
      // Older reports only.
      if ((s('containmentStatus') ?? '').isNotEmpty)
        CaseInfoItem('Containment / escape risk', s('containmentStatus')),
      if ((s('strayTemperament') ?? '').isNotEmpty)
        CaseInfoItem('Approachability / bite risk', s('strayTemperament')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final caseAsync = ref.watch(caseDetailProvider(widget.caseId));
    final seed = widget.data.isNotEmpty
        ? RescueCase.fromMap(widget.caseId, widget.data)
        : null;
    final c = caseAsync.asData?.value ?? seed;

    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pendingLocationReports = ref
        .watch(caseCommunityReportsProvider(c.id))
        .asData
        ?.value
        .where((r) => r.type == 'moved' && r.approvalStatus == 'pending' && r.newLat != null && r.newLng != null)
        .toList() ??
        const [];

    // Whether a transporter offer is currently pending/accepted — stops
    // "Assign Transporter" from creating a second active offer (the
    // repository's transaction guards against this too).
    final hasActiveAssignment = ref.watch(currentAssignmentProvider(c.id)).asData?.value?.isActive ?? false;

    // Merge/Refer are ordinary organization operations: Owner/Admin/Member
    // parity via the centralized capability resolver.
    final canManageOrgActions =
        ref.watch(currentOrganizationCapabilitiesProvider).asData?.value.canManageRescues ?? true;
    final myOrgId = ref.watch(currentOrganizationIdProvider).asData?.value;

    final d = c.raw;
    final verification = CaseVerification.fromMap(d['verification']);
    final actions = _actionsFor(
      c,
      canManageOrgActions: canManageOrgActions,
      hasActiveAssignment: hasActiveAssignment,
      myOrgId: myOrgId,
    );
    final banner = _outcomeBanner(c, myOrgId: myOrgId, hasActiveAssignment: hasActiveAssignment);
    final inReview = c.status == RescueStatus.pendingReview || c.status == RescueStatus.verifying;
    const gap = SizedBox(height: kCaseGap);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Rescue Details',
          style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background),
        ),
        actions: [CaseOverflowMenu(actions: actions.overflow, busy: _isLoading)],
      ),
      bottomNavigationBar: CaseActionBar.maybe(
        primary: actions.primary,
        secondary: actions.secondary,
        busy: _isLoading,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CaseHeaderCard(
              title: c.speciesSummary,
              caseId: c.shortCaseId,
              status: c.status,
              urgency: c.urgency,
              reporterName: c.reporterName,
              reportedAt: c.createdAt,
              photoUrls: c.photoUrls,
              videoUrls: c.videoUrls,
              onMediaTap: (i) => _openMedia(c, i),
              badges: [
                if (c.openForTransfer)
                  const CaseBadge(label: 'Open for transfer', icon: Icons.swap_horiz),
                if (verification?.isConfirmed ?? false)
                  const CaseBadge(label: 'Verified', icon: Icons.verified, color: AppColors.success),
                if (c.animalCount > 1) CaseBadge(label: '${c.animalCount} animals', icon: Icons.pets),
              ],
            ),
            if (c.highRiskAnimals.isNotEmpty) ...[
              gap,
              RescueRiskBanner(highRiskAnimals: c.highRiskAnimals),
            ],

            // The transporter stopped before the shelter leg: no shelter pin.
            if (d['shelterLocationMissing'] is Map && (c.organizationId ?? '').isNotEmpty) ...[
              gap,
              ShelterPinPrompt(
                organizationId: c.organizationId!,
                canSet: ref.watch(isOrgAdminProvider).asData?.value ?? false,
                message: 'The transporter cannot take this animal to the shelter: your organization has no '
                    'shelter location saved. Set it, then the transporter can continue.',
              ),
            ],

            if (banner != null) ...[gap, banner],

            gap,
            CaseInfoGrid(
              title: 'Report',
              items: _reportItems(c),
              // Analytics gap 5: staff confirm or correct the reporter's
              // "community cat" answer; Analytics counts the tagged reports.
              trailing: c.allSpecies.any((s) => s.toLowerCase() == 'cat')
                  ? SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                activeThumbColor: AppColors.textPrimary,
                title: Text('Community cat (outdoor, no owner)',
                    style: GoogleFonts.zain(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                value: d['communityCat'] == true,
                onChanged: (v) => FirebaseFirestore.instance
                    .collection('cases')
                    .doc(c.id)
                    .update({'communityCat': v}).catchError((Object e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
                  }
                }),
              )
                  : null,
            ),

            gap,
            // Everything the reporter entered on the rescue form, grouped
            // into cards — the same section the reporter sees on Track
            // Case. Two or more animals show as collapsed cards.
            // Already grouped into its own cards; the address is in the
            // Location card below.
            CaseReportDetails(caseId: c.id, data: c.raw, showAddress: false),

            gap,
            _LocationCard(rescueCase: c, pendingLocationReports: pendingLocationReports),

            if (c.hasSavedClinic) ...[
              gap,
              CaseCard(
                title: 'Clinic',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.vetClinicName!,
                        style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    for (final line in [c.vetClinicAddress, c.vetClinicPhone])
                      if (line != null && line.isNotEmpty)
                        Text(line, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],

            // A case past treatment (closed, intaked, referred): its costs.
            if (c.status != RescueStatus.treatment) CaseCostsCard(rescueCase: c),

            gap,
            _OwnershipSection(
              rescueCase: c,
              busy: _isLoading,
              onUpdate: () => _updateOwnership(c),
              onContactOwner: () => _contactOwner(c),
              onReferToLgu: () => _referCase(c),
              onReturnToOwner: () => _closeCase(c, initialReason: ClosureReason.reunited),
              onCloseHasOwner: () => _closeCase(c, initialReason: ClosureReason.reunited),
            ),

            // Rescue gaps 6/10: the interested adopter's request, the
            // organization's confirmation and the pickup window.
            RescueAdoptionRequestCard(
              rescueCase: c,
              actorUid: _actorUid,
              actorName: _actorName,
              onRefer: () => _referCase(c),
            ),

            gap,
            // Desk check before accepting: evidence, live proof from the
            // reporter, and the recorded result (including a rider visit).
            // Open while the report is still being reviewed.
            CollapsibleSection(
              title: 'Verification',
              icon: Icons.fact_check_outlined,
              summary: verification?.summary ?? 'Evidence, live proof and rider visits',
              initiallyExpanded: inReview,
              child: ReportVerificationSection(
                key: ValueKey('verification-${c.id}'),
                rescueCase: c,
                actorUid: _actorUid,
                actorName: _actorName,
              ),
            ),
            const SizedBox(height: 8),
            CollapsibleSection(
              title: 'Referral & merge history',
              icon: Icons.history,
              summary: [
                if (c.mergedCaseIds.isNotEmpty) '${c.mergedCaseIds.length} merged',
                if (c.mergedIntoCaseId != null) 'merged into another case',
                if (d['referralOutcome'] is Map || d['referral'] is Map) 'has referrals',
              ].join(' · '),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MergeHistorySection(rescueCase: c, onOpenCase: _openCase),
                  const SizedBox(height: 8),
                  ReferralHistorySection(caseId: c.id),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CollapsibleSection(
              title: 'Messages',
              icon: Icons.chat_bubble_outline,
              child: CaseMessagesSection(caseId: c.id),
            ),
            const SizedBox(height: 8),
            CollapsibleSection(
              title: 'Community reports',
              icon: Icons.campaign_outlined,
              summary: pendingLocationReports.isEmpty
                  ? 'Sightings and updates from the public'
                  : '${pendingLocationReports.length} location change${pendingLocationReports.length == 1 ? '' : 's'} to review',
              attention: pendingLocationReports.isNotEmpty,
              initiallyExpanded: pendingLocationReports.isNotEmpty,
              child: CommunityReportsSection(caseId: c.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// Address, service-area note and a small map with the case pin, its
/// geofence and any proposed new location awaiting approval.
class _LocationCard extends StatelessWidget {
  final RescueCase rescueCase;
  final List<CommunityReport> pendingLocationReports;
  const _LocationCard({required this.rescueCase, required this.pendingLocationReports});

  @override
  Widget build(BuildContext context) {
    final c = rescueCase;
    return CaseCard(
      title: 'Location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (c.address?.isNotEmpty ?? false) ? c.address! : 'No address given.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          _ServiceAreaGeofenceNote(data: c.raw),
          if (c.lat != null && c.lng != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 150,
                child: GoogleMap(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                  initialCameraPosition: CameraPosition(target: LatLng(c.lat!, c.lng!), zoom: 15),
                  markers: {
                    Marker(markerId: const MarkerId('rescue_location'), position: LatLng(c.lat!, c.lng!)),
                    for (final report in pendingLocationReports)
                      Marker(
                        markerId: MarkerId('proposed_location_${report.id}'),
                        position: LatLng(report.newLat!, report.newLng!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                        infoWindow: InfoWindow(
                          title: 'Proposed location — awaiting approval',
                          snippet: report.newAddress,
                        ),
                      ),
                  },
                  // On-device geofence around this case (GeofenceService).
                  circles: {
                    Circle(
                      circleId: const CircleId('case_geofence'),
                      center: LatLng(c.lat!, c.lng!),
                      radius: GeofenceConfig.caseGeofenceRadiusMeters,
                      strokeWidth: 2,
                      strokeColor: AppColors.error,
                      fillColor: AppColors.error.withValues(alpha: 0.10),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            )
          else
            Row(
              children: [
                const Icon(Icons.location_off_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('No coordinates saved for this report.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          if (pendingLocationReports.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _MapLegendItem(color: AppColors.error, label: 'Current location'),
                _MapLegendItem(color: AppColors.warning, label: 'Proposed location — awaiting approval'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _MapLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _MapLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Rejected case: reason, who rejected it and when, and whether the
/// rejection makes it Community-Adoption eligible.
class _RejectedBanner extends ConsumerWidget {
  final RescueCase rescueCase;
  const _RejectedBanner({required this.rescueCase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = rescueCase;
    final reason = c.rejectionReason;
    final reasonLabel = reason == RejectionReason.other
        ? (c.rejectionReasonOther?.trim().isNotEmpty ?? false ? c.rejectionReasonOther! : 'Other')
        : (reason?.label ?? 'Not specified');

    final rejectionLog = ref
        .watch(caseActivityLogsProvider(c.id))
        .asData
        ?.value
        .where((l) => l.action == 'rejected')
        .fold<ActivityLogEntry?>(null, (latest, entry) {
      if (latest == null) return entry;
      if (entry.timestamp == null) return latest;
      if (latest.timestamp == null) return entry;
      return entry.timestamp!.isAfter(latest.timestamp!) ? entry : latest;
    });
    final rejectedDate = rejectionLog?.timestamp;
    final eligible = isCommunityAdoptionEligible(
      status: c.status.firestoreValue,
      rejectionReason: reason?.name,
      rescueType: c.raw['rescueType'] as String?,
    );

    return CaseOutcomeBanner(
      tone: CaseBannerTone.danger,
      icon: Icons.cancel_outlined,
      title: 'Rejected: $reasonLabel',
      facts: [
        ('Rejected', rejectedDate != null ? formatDate(rejectedDate) : 'Unknown'),
        ('By', rejectionLog?.actorName ?? 'Unknown'),
      ],
      actions: [
        if (eligible)
          const CaseBadge(label: 'Community Adoption eligible', icon: Icons.volunteer_activism, color: AppColors.greenrspwn),
      ],
    );
  }
}

/// Animal records created from this case at intake (`linkedCaseId`).
final _caseAnimalRecordsProvider =
StreamProvider.autoDispose.family<List<({String id, String name})>, String>((ref, caseId) {
  // Org-scoped: an unfiltered `animals` query is denied for org staff.
  return ref.watch(animalRecordRepositoryProvider).streamRecordsForCase(caseId).map((records) => [
    for (final r in records) (id: r.id, name: r.name.trim().isNotEmpty ? r.name.trim() : 'Animal record'),
  ]);
});

/// Completed case: intaked (with links to the animal records it created),
/// or closed because the animal died / every animal was claimed.
class _CompletedBanner extends ConsumerWidget {
  final RescueCase rescueCase;
  const _CompletedBanner({required this.rescueCase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = rescueCase;
    final raw = c.raw;
    if (raw['status'] == 'closed') {
      final claimed = (raw['communityAdoptionIds'] as List?)?.isNotEmpty ?? false;
      final reason = raw['closureReason'] as String?;
      final closedAt = raw['closedAt'] is Timestamp ? (raw['closedAt'] as Timestamp).toDate() : null;
      return CaseOutcomeBanner(
        tone: CaseBannerTone.neutral,
        icon: claimed ? Icons.volunteer_activism : Icons.inventory_2_outlined,
        title: claimed
            ? 'Closed: every animal was claimed through Community Adoption'
            : reason != null
            ? 'Closed: ${ClosureReason.fromName(reason).label}'
            : 'Closed: animal deceased',
        facts: [
          if (closedAt != null) ('Closed', formatDateTime(closedAt)),
          if ((raw['closedByName'] as String?)?.isNotEmpty ?? false) ('By', raw['closedByName'] as String),
        ],
      );
    }
    final records = ref.watch(_caseAnimalRecordsProvider(c.id)).asData?.value ?? const [];
    final shelter = (raw['shelterName'] as String?)?.trim();
    return CaseOutcomeBanner(
      tone: CaseBannerTone.success,
      icon: Icons.home_outlined,
      title: 'Intaked',
      message: records.isEmpty
          ? 'The rescue is complete.'
          : 'The rescue is complete. ${records.length == 1 ? 'Its animal record' : 'Its ${records.length} animal records'} '
          'hold the animal${records.length == 1 ? '' : 's'}\' care from here.',
      facts: [
        if (shelter != null && shelter.isNotEmpty) ('Shelter', shelter),
        if (c.vetClinicName != null) ('Clinic', c.vetClinicName!),
      ],
      actions: [
        for (final r in records)
          ActionChip(
            avatar: const Icon(Icons.pets, size: 16),
            label: Text('Open ${r.name}', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AnimalRecordDetailPage(animalId: r.id, data: const {})),
            ),
          ),
      ],
    );
  }
}

/// Owner-identification section (spec §1) — always visible (not just once
/// a status is set), so ownership can be recorded the moment it's
/// discovered at any point in the rescue. Owner contact details are
/// intentionally never rendered inline in this card (only via the
/// "Contact Owner" dialog, an explicit tap) — this card itself only ever
/// shows the status/category, never the contact info, so it stays safe to
/// have on screen during a normal triage pass.
class _OwnershipSection extends StatelessWidget {
  final RescueCase rescueCase;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onContactOwner;
  final VoidCallback onReferToLgu;
  final VoidCallback onReturnToOwner;
  final VoidCallback onCloseHasOwner;
  const _OwnershipSection({
    required this.rescueCase,
    required this.busy,
    required this.onUpdate,
    required this.onContactOwner,
    required this.onReferToLgu,
    required this.onReturnToOwner,
    required this.onCloseHasOwner,
  });

  @override
  Widget build(BuildContext context) {
    final raw = rescueCase.raw;
    final status = raw['ownershipStatus'] as String? ?? 'Unknown';
    final category = raw['ownedAnimalCategory'] as String?;
    final hasPossibleOwner =
        status == 'Possible owner' || status == 'Owner identified';

    return SectionCard(
      title: 'Ownership Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: status == 'Unknown'
                      ? AppColors.slaterspwn
                      : AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (category != null) ...[
                const SizedBox(width: 8),
                Text(
                  category,
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onUpdate,
                child: const Text('Update Ownership Info'),
              ),
              if (hasPossibleOwner) ...[
                OutlinedButton(
                  onPressed: busy ? null : onContactOwner,
                  child: const Text('Contact Owner'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onReturnToOwner,
                  child: const Text('Return/Reunite with Owner'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onReferToLgu,
                  child: const Text('Refer to LGU'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onCloseHasOwner,
                  style: AppButtons.dangerOutline,
                  child: const Text('Close Case'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;
  final List<String> videoUrls;
  final int initialIndex;
  final double height;
  const _PhotoCarousel({
    required this.photoUrls,
    this.videoUrls = const [],
    this.initialIndex = 0,
    this.height = 220,
  });

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  late int _current = widget.initialIndex;
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Photos first, then videos — matches the order they were shown while
  // being attached in the report form.
  late final List<String> _items = [...widget.photoUrls, ...widget.videoUrls];
  late final int _videoStartIndex = widget.photoUrls.length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final isVideo = i >= _videoStartIndex;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isVideo
                    ? _NetworkVideoTile(url: _items[i])
                    : Image.network(
                  _items[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.tearspwn,
                    child: const Icon(
                      Icons.broken_image,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          bottom: 10,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_current + 1}/${_items.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// A single video within the carousel — starts paused with a play button
// overlay (rather than autoplaying every video the moment it's swiped
// into view), and tears down its controller as soon as it's disposed.
class _NetworkVideoTile extends StatefulWidget {
  final String url;
  const _NetworkVideoTile({required this.url});

  @override
  State<_NetworkVideoTile> createState() => _NetworkVideoTileState();
}

class _NetworkVideoTileState extends State<_NetworkVideoTile> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
        .initialize()
        .then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    })
        .catchError((_) {
      if (!mounted) return;
      setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: AppColors.tearspwn,
        child: const Center(
          child: Icon(
            Icons.videocam_off_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    if (!_ready || _controller == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    final controller = _controller!;
    return GestureDetector(
      onTap: () => setState(() {
        controller.value.isPlaying ? controller.pause() : controller.play();
      }),
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          AnimatedOpacity(
            opacity: controller.value.isPlaying ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.play_circle_fill,
              size: 56,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

/// Result of the service-area geofence check done by notifyNewCaseReported
/// (functions/index.js): which organizations' coverage contains this case,
/// or a warning when it's outside every coverage area.
class _ServiceAreaGeofenceNote extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ServiceAreaGeofenceNote({required this.data});

  @override
  Widget build(BuildContext context) {
    final outside = data['outsideServiceArea'] == true;
    final orgIds = ((data['areaOrgIds'] as List?) ?? const []).whereType<String>().toList();
    if (!outside && orgIds.isEmpty) return const SizedBox.shrink();

    final text = outside
        ? 'Outside every organization service area. Consider referring this case to the LGU.'
        : orgIds.length == 1
        ? 'Inside 1 organization service area.'
        : 'Inside ${orgIds.length} organization service areas.';
    final color = outside ? Colors.orange.shade800 : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(outside ? Icons.warning_amber_rounded : Icons.radar, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.zain(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
