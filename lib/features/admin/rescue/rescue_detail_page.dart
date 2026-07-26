import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/widgets/rescue_risk_banner.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/accept_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_messages_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/community_reports_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/merge_history_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/ownership_status_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/possible_duplicate_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/referral_history_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/rejection_reason_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/status_chip.dart';
import 'package:respawnd1/features/admin/rescue/widgets/success_dialog.dart';

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
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    final name = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
    if (mounted && name.isNotEmpty) setState(() => _actorName = name);
  }

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _acceptCase(RescueCase c) async {
    final openForTransfer = await showAcceptCaseSheet(context);
    if (openForTransfer == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).acceptCase(
        caseId: c.id,
        actorUid: _actorUid,
        actorName: _actorName,
        openForTransfer: openForTransfer,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept case: $e'), backgroundColor: Colors.redAccent),
        );
      }
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = false);

    // Stay on Rescue Details — open the clinic sheet from here instead of
    // navigating away immediately. Whether this leads to Assign Transporter
    // is decided entirely by the sheet's own explicit result (see
    // _openClinicSheet): dismissing it just leaves the case in "accepted,
    // no clinic yet", which the action area below renders as "Select Clinic".
    if (mounted) await _openClinicSheet(c, offerAssignRider: true);
  }

  /// Shared Close Case flow (spec §2) — reused from every screen that can
  /// close a case. The sheet only picks a reason/details; this method does
  /// the actual write, guarded by [_isLoading] so a double-tap can't fire
  /// two closures.
  Future<void> _closeCase(RescueCase c, {ClosureReason? initialReason}) async {
    final result = await showCloseCaseSheet(context, rescueCase: c, initialReason: initialReason);
    if (result == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).closeCase(
            caseId: c.id,
            reason: result.reason,
            details: result.details,
            actorUid: _actorUid,
            actorName: _actorName,
            lastKnownLocation: result.lastKnownLocation,
            clinicUnavailableDetails: result.clinicUnavailableDetails,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Case closed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not close case: $e'), backgroundColor: Colors.redAccent));
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
      await ref.read(rescueCaseRepositoryProvider).updateOwnershipInfo(
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
          SnackBar(content: Text('Could not save ownership info: $e'), backgroundColor: Colors.redAccent),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Owner Contact'),
        content: Text(
          (contact == null || contact.isEmpty)
              ? 'No owner contact information has been recorded yet. Use Update Ownership Info to add it.'
              : '${name != null && name.isNotEmpty ? '$name\n' : ''}$contact',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  /// "Retry with a different transporter" after a safety report (spec
  /// §3) — requires the admin to acknowledge the warning before the case
  /// even becomes reassignable, then hands off to the existing Assign
  /// Transporter screen exactly as normal (no transporter is auto-picked).
  Future<void> _retryWithDifferentTransporter(RescueCase c) async {
    final notes = c.raw['endReasonNotes'] as String?;
    final acknowledged = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Acknowledge Safety Warning'),
        content: Text(
          'A previous transporter reported that this animal may be aggressive.'
          '${notes != null && notes.isNotEmpty ? '\n\n"$notes"' : ''}'
          '\n\nDo you acknowledge this before selecting another transporter?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
            child: const Text('I Acknowledge'),
          ),
        ],
      ),
    );
    if (acknowledged != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).resumeAssignmentAfterSafetyReport(
            caseId: c.id,
            actorUid: _actorUid,
            actorName: _actorName,
          );
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resume assignment: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _keepTransporterWithInstructions(RescueCase c) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Instructions for Transporter'),
        content: TextField(controller: controller, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. use a carrier, approach from the left, wait for backup')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty || !mounted) return;
    try {
      await ref.read(rescueCaseRepositoryProvider).addSafetyResponseNote(
            caseId: c.id,
            note: note,
            actorUid: _actorUid,
            actorName: _actorName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save instructions: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  /// Single entry point for the Select Clinic sheet, used both right after
  /// Accept and from the standalone Select/Reassign Clinic action below.
  /// The sheet performs its own save and returns an explicit
  /// [ClinicSheetResult] — this only reacts to that result, it never
  /// assumes "the sheet closed" means "continue".
  Future<void> _openClinicSheet(RescueCase c, {required bool offerAssignRider}) async {
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
        await showSuccessDialog(context,
            title: 'Clinic Saved', message: outcome.clinic?.name);
        break;
      case ClinicSheetResult.assignRider:
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)));
        break;
    }
  }

  Future<void> _rejectCase(RescueCase c) async {
    final result = await showRejectionReasonSheet(context);
    if (result == null || !mounted) return;

    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Reject This Report?',
      message: 'The reporter will see this report was rejected: ${result.reason.label}.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).rejectCase(
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
          SnackBar(content: Text('Could not reject case: $e'), backgroundColor: Colors.redAccent),
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
      await showSuccessDialog(context, title: 'Referral Sent', message: 'The case status has been updated to Referred.');
    }
  }

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
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => RescueDetailPage(caseId: caseId, data: const {})));
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '';
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm, ${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final caseAsync = ref.watch(caseDetailProvider(widget.caseId));
    final seed = widget.data.isNotEmpty ? RescueCase.fromMap(widget.caseId, widget.data) : null;
    final c = caseAsync.asData?.value ?? seed;

    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Whether a transporter offer is currently pending/accepted for this
    // case — used below to stop "Assign Transporter" from creating a
    // second active offer while one is already outstanding (the
    // repository's own transaction guards against this too; this just
    // keeps the button itself honest about the case's real state).
    final currentAssignment = ref.watch(currentAssignmentProvider(c.id)).asData?.value;
    final hasActiveAssignment = currentAssignment?.isActive ?? false;

    final membership = ref.watch(currentOrgMembershipProvider).asData?.value;
    // TODO(org-roles): Admin-vs-Staff enforcement is intentionally disabled
    // for this testing phase. `organizations/{orgId}/members/{uid}` isn't
    // populated for any real admin/NGO account yet, so this fails OPEN
    // (membership == null => treated as allowed) instead of locking every
    // existing tester out of Merge/Refer. This is a FRONTEND-ONLY gate —
    // it does not read or write any Firestore rule, and current rules do
    // not restrict these writes by role either (see org_membership_service.dart).
    // Before production: (1) backfill organizations/{orgId}/members for
    // every real admin/staff user, (2) flip this to fail CLOSED
    // (`membership != null && membership.role == OrgRole.admin`), and
    // (3) add the matching security-rule checks from the rescue-module
    // security-rule guidance so the server enforces this too, not just the UI.
    final canManageOrgActions = membership == null || membership.role == OrgRole.admin;

    final d = c.raw;
    final rescueType = d['rescueType'] as String?;
    final breed = d['breed'] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Rescue Details',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(c.speciesSummary,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    UrgencyChip(urgency: c.urgency),
                    const SizedBox(height: 4),
                    RescueStatusChip(status: c.status),
                  ],
                ),
              ],
            ),
            Text('CASE ID: ${c.shortCaseId}',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (c.reporterName != null)
                  Expanded(
                    child: Text('Reported by ${c.reporterName}',
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                if (c.createdAt != null)
                  Text(_formatDateTime(c.createdAt),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            RescueRiskBanner(highRiskAnimals: c.highRiskAnimals),

            if (c.openForTransfer) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz, size: 16, color: AppColors.textPrimary),
                    const SizedBox(width: 6),
                    Text('Open for Transfer to Another Organization',
                        style: GoogleFonts.zain(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            if (c.photoUrls.isNotEmpty || c.videoUrls.isNotEmpty)
              _PhotoCarousel(photoUrls: c.photoUrls, videoUrls: c.videoUrls)
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 48, color: AppColors.textSecondary),
                ),
              ),

            const SizedBox(height: 16),

            if (rescueType != null && rescueType.isNotEmpty)
              _DetailSection(label: 'Rescue Type', value: rescueType),

            const SizedBox(height: 8),

            _DetailSection(label: 'Description', value: c.condition ?? '-'),
            if (breed != null && breed.isNotEmpty)
              _DetailSection(label: 'Breed', value: breed),

            const SizedBox(height: 8),

            // Per-animal breakdown for multi-animal group reports (species/
            // breed/sex/size/color) — falls back to this case's own animal
            // fields when there's no group. Backward-compatible: older
            // cases without a groupId just show the single-animal view.
            _AnimalGroupSection(currentCase: c),

            const SizedBox(height: 8),

            // Full stray-report questionnaire — every field is optional so
            // older reports saved before these questions existed still
            // render without gaps or crashes.
            if ((d['containmentStatus'] as String?)?.isNotEmpty ?? false)
              _DetailSection(
                  label: 'Containment / Escape Risk', value: d['containmentStatus'] as String),
            if ((d['strayTemperament'] as String?)?.isNotEmpty ?? false)
              _DetailSection(
                  label: 'Approachability / Bite Risk', value: d['strayTemperament'] as String),
            if ((d['onSite'] as String?)?.isNotEmpty ?? false)
              _DetailSection(label: 'Reporter On-Site', value: d['onSite'] as String),
            if ((d['accessInstructions'] as String?)?.isNotEmpty ?? false)
              _DetailSection(
                  label: 'Access Instructions', value: d['accessInstructions'] as String),
            if ((d['bestTimeToContact'] as String?)?.isNotEmpty ?? false)
              _DetailSection(
                  label: 'Best Time to Reach Reporter', value: d['bestTimeToContact'] as String),
            if ((d['coordinateWithShelter'] as String?)?.isNotEmpty ?? false)
              _DetailSection(
                label: 'Willing to Coordinate with Shelter',
                value: d['coordinateWithShelter'] == 'yes' ? 'Yes' : 'No',
              ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _DetailSection(
                      label: 'Interest to adopt',
                      value: c.interestedToAdopt == 'yes' ? 'Yes' : 'No'),
                ),
                Expanded(
                  child: _DetailSection(
                    label: 'QR/NFC',
                    value: (c.scannedTagId != null && c.scannedTagId!.isNotEmpty)
                        ? 'Linked (${c.scannedTagId})'
                        : 'No',
                  ),
                ),
              ],
            ),

            if (d['coordinateWithShelter'] == 'no' &&
                ((d['witnessName'] as String?)?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _DetailSection(
                          label: 'Additional Witness', value: d['witnessName'] as String)),
                  Expanded(
                      child: _DetailSection(
                          label: 'Witness Number', value: d['witnessPhone'] as String? ?? '-')),
                ],
              ),
            ],

            const SizedBox(height: 8),

            _DetailSection(label: 'Location', value: c.address ?? '-'),
            Stack(
              children: [
                // Real map when we have coordinates — this used to be a
                // static icon in a gray box regardless of whether lat/lng
                // existed, which is why it always looked "blank". A fixed
                // height + ClipRRect gives it concrete layout constraints
                // so it can't collapse to zero size inside the scroll view.
                if (c.lat != null && c.lng != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: GoogleMap(
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                        initialCameraPosition:
                        CameraPosition(target: LatLng(c.lat!, c.lng!), zoom: 15),
                        markers: {
                          Marker(
                            markerId: const MarkerId('rescue_location'),
                            position: LatLng(c.lat!, c.lng!),
                          ),
                        },
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                    ),
                  )
                else
                // Fallback for reports with no saved coordinates —
                // avoids a broken/blank box instead of trying (and
                // failing) to render a map with nothing to center on.
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.slaterspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_off_outlined,
                              size: 32, color: AppColors.textSecondary),
                          const SizedBox(height: 6),
                          Text('No coordinates saved for this report.',
                              style: GoogleFonts.zain(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                if (c.address != null && c.address!.isNotEmpty)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.yellowrspwn,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(c.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            if (c.hasSavedClinic) ...[
              SectionCard(
                title: 'Selected Clinic',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.vetClinicName!,
                        style: GoogleFonts.zain(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (c.vetClinicAddress != null && c.vetClinicAddress!.isNotEmpty)
                      Text(c.vetClinicAddress!,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    if (c.vetClinicPhone != null && c.vetClinicPhone!.isNotEmpty)
                      Text(c.vetClinicPhone!,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            _OwnershipSection(
              rescueCase: c,
              busy: _isLoading,
              onUpdate: () => _updateOwnership(c),
              onContactOwner: () => _contactOwner(c),
              onReferToLgu: () => _referCase(c),
              onReturnToOwner: () => _closeCase(c, initialReason: ClosureReason.reunitedWithOwner),
              onCloseHasOwner: () => _closeCase(c, initialReason: ClosureReason.hasOwner),
            ),
            const SizedBox(height: 12),

            MergeHistorySection(rescueCase: c, onOpenCase: _openCase),
            const SizedBox(height: 12),
            ReferralHistorySection(caseId: c.id),

            const SizedBox(height: 24),

            if (c.status == RescueStatus.pendingReview) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => _rejectCase(c),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Reject',
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () => _acceptCase(c),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.textPrimary))
                          : Text('Accept',
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (_isLoading || !canManageOrgActions) ? null : () => _referCase(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(canManageOrgActions ? 'Refer' : 'Refer (Admin only)',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (_isLoading || !canManageOrgActions) ? null : () => _mergeDuplicate(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.slaterspwn),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(canManageOrgActions ? 'Check for Duplicates / Merge' : 'Merge (Admin only)',
                      style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textSecondary)),
                ),
              ),
            ] else if (c.status == RescueStatus.possibleDuplicate) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _mergeDuplicate(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Review Possible Duplicate',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
            ] else if (c.status == RescueStatus.accepted || c.status == RescueStatus.awaitingAssignment) ...[
              // Accepted. Primary action is derived from saved case data —
              // not local widget state — so reopening this screen always
              // shows the right button: no clinic yet means Select Clinic,
              // a saved clinic means Assign Transporter is unblocked.
              // status == accepted specifically means "no clinic yet" (see
              // acceptCase/assignClinic) — !c.hasSavedClinic covers it, but
              // is kept as the single source of truth here rather than
              // branching on status a second time, so this still behaves
              // correctly for animal-record admissions which start at
              // awaitingAssignment with no clinic (see createAdmissionCase).
              if (!c.hasSavedClinic)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _openClinicSheet(c, offerAssignRider: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Select Clinic',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                )
              else if (hasActiveAssignment)
              // A transporter offer already exists and hasn't been
              // rejected — route through AdminTrackCasePage, which shows
              // an inline "waiting for the transporter to respond" view
              // for as long as it stays pending (never a second "Assign
              // Transporter" while one is outstanding).
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AdminTrackCasePage(caseId: c.id, data: c.raw))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('View Assignment Status',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Assign Transporter',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
            ] else if (c.status == RescueStatus.ongoing) ...[
              // Transporter assigned and en route — primary action is
              // tracking the case; reassigning the clinic stays available
              // as a secondary action (no Assign Transporter prompt here,
              // a transporter is already on the case).
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AdminTrackCasePage(caseId: c.id, data: c.raw))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Track Case',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _openClinicSheet(c, offerAssignRider: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                      c.vetClinicName == null ? 'Assign Clinic' : 'Reassign Clinic (${c.vetClinicName})',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
            ] else if (c.status == RescueStatus.treatment) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _openClinicSheet(c, offerAssignRider: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                      c.vetClinicName == null ? 'Assign Clinic' : 'Reassign Clinic (${c.vetClinicName})',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
            ] else if (c.status == RescueStatus.needsSpecializedAssistance) ...[
              // Set by the real transporter app's own End Reason flow
              // (transit_progress_page.dart) — endReason/endReasonNotes are
              // read here, never re-derived or guessed.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFE05353).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Safety warning', style: GoogleFonts.tiltWarp(fontSize: 14, color: const Color(0xFFE05353))),
                    const SizedBox(height: 6),
                    Text(
                      'A previous transporter reported that the animal may be aggressive. Review the incident before assigning another transporter.',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    if ((c.raw['endReasonNotes'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text('Reported: ${c.raw['endReasonNotes']}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _retryWithDifferentTransporter(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Retry with a Different Transporter',
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _keepTransporterWithInstructions(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Keep Current Transporter + Instructions',
                      style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _referCase(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.slaterspwn),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Escalate to Trained Responder / Authority',
                      style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _closeCase(c, initialReason: ClosureReason.aggressiveAnimal),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE05353),
                    side: const BorderSide(color: Color(0xFFE05353)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Close Case — Aggressive Animal / Unsafe Rescue'),
                ),
              ),
            ] else
              SectionCard(
                child: Text(
                  'This case is ${c.status.label.toLowerCase()} — no further action is needed here.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),

            if (!c.status.isTerminal) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isLoading ? null : () => _closeCase(c),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFE05353)),
                  child: const Text('Close Case'),
                ),
              ),
            ],

            const SizedBox(height: 24),

            CaseMessagesSection(caseId: c.id),

            const SizedBox(height: 16),

            CommunityReportsSection(caseId: c.id),

            const SizedBox(height: 32),
          ],
        ),
      ),
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
    final hasPossibleOwner = status == 'Possible owner' || status == 'Owner identified';

    return SectionCard(
      title: 'Ownership Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'Unknown' ? AppColors.slaterspwn : AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (category != null) ...[
                const SizedBox(width: 8),
                Text(category, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: busy ? null : onUpdate, child: const Text('Update Ownership Info')),
              if (hasPossibleOwner) ...[
                OutlinedButton(onPressed: busy ? null : onContactOwner, child: const Text('Contact Owner')),
                OutlinedButton(onPressed: busy ? null : onReturnToOwner, child: const Text('Return/Reunite with Owner')),
                OutlinedButton(onPressed: busy ? null : onReferToLgu, child: const Text('Refer to LGU')),
                OutlinedButton(
                  onPressed: busy ? null : onCloseHasOwner,
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE05353), side: const BorderSide(color: Color(0xFFE05353))),
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
  const _PhotoCarousel({required this.photoUrls, this.videoUrls = const []});

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  int _current = 0;
  final PageController _ctrl = PageController();

  // Photos first, then videos — matches the order they were shown while
  // being attached in the report form.
  late final List<String> _items = [...widget.photoUrls, ...widget.videoUrls];
  late final int _videoStartIndex = widget.photoUrls.length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 220,
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
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.tearspwn,
                    child: const Icon(Icons.broken_image, size: 48, color: AppColors.textSecondary),
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
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    }).catchError((_) {
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
          child: Icon(Icons.videocam_off_outlined, size: 48, color: AppColors.textSecondary),
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
            child: const Icon(Icons.play_circle_fill, size: 56, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String label;
  final String value;
  const _DetailSection({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (value.isNotEmpty)
            Text(value, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// "No. of Animals" + per-animal breakdown.
///
/// Current submissions: every animal in a group report lives in this one
/// case doc's `animals` array — one Case ID for the whole report, however
/// many animals (or species) were logged together.
///
/// Legacy fallback: cases created before this fix stored one case doc PER
/// animal, linked only by a shared `groupId`; those are still read the old
/// way (querying sibling docs) so historic group reports keep displaying
/// correctly. Cases with neither `animals` nor `groupId` just show this
/// case's own single animal.
class _AnimalGroupSection extends StatelessWidget {
  final RescueCase currentCase;
  const _AnimalGroupSection({required this.currentCase});

  // Maps an `animals[]` entry onto the same key shape
  // `_AnimalCard._animalFields()` already expects from a full case doc
  // (animalType/breed/sex/size/colorMarkings/biteRisk/escapeRisk).
  Map<String, dynamic> _animalMap(Map raw) => {
    'animalType': raw['species'],
    'breed': raw['breed'],
    'sex': raw['sex'],
    'size': raw['size'],
    'colorMarkings': raw['colorMarkings'],
    'biteRisk': raw['biteRisk'],
    'escapeRisk': raw['escapeRisk'],
  };

  @override
  Widget build(BuildContext context) {
    final animals = currentCase.raw['animals'] as List?;
    if (animals != null && animals.isNotEmpty) {
      final total = animals.length;
      if (total <= 1) {
        return _AnimalCard(
          data: _animalMap(animals.first as Map),
          index: 1,
          total: 1,
          highlight: false,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailSection(label: 'No. of Animals', value: '$total'),
          const SizedBox(height: 4),
          _responsiveAnimalCards([
            for (var i = 0; i < animals.length; i++)
              _AnimalCard(
                data: _animalMap(animals[i] as Map),
                index: i + 1,
                total: total,
                highlight: false,
              ),
          ]),
        ],
      );
    }

    final groupId = currentCase.raw['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      return _AnimalCard(data: currentCase.raw, index: 1, total: 1, highlight: false);
    }

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('cases')
          .where('groupId', isEqualTo: groupId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Show this case's own animal immediately rather than blocking
          // on the group query — the count/other-animals list fills in
          // once it resolves.
          return _AnimalCard(data: currentCase.raw, index: 1, total: 1, highlight: false);
        }
        final docs = snapshot.data!.docs;
        final total = docs.length;
        if (total <= 1) {
          return _AnimalCard(data: currentCase.raw, index: 1, total: 1, highlight: false);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailSection(label: 'No. of Animals', value: '$total'),
            const SizedBox(height: 4),
            _responsiveAnimalCards([
              for (var i = 0; i < docs.length; i++)
                _AnimalCard(
                  data: docs[i].data(),
                  index: i + 1,
                  total: total,
                  highlight: docs[i].id == currentCase.id,
                ),
            ]),
          ],
        );
      },
    );
  }

  /// Full-width vertical stack on phone widths; a two-column grid of
  /// equal-width, equal-padding cards once there's enough room for both to
  /// stay legible — never a horizontally compressed single Row (which is
  /// what made the second card too narrow to read).
  Widget _responsiveAnimalCards(List<Widget> cards) {
    const breakpoint = 480.0;
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
        }
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final int total;
  final bool highlight;
  const _AnimalCard(
      {required this.data, required this.index, required this.total, required this.highlight});

  @override
  Widget build(BuildContext context) {
    // Single-animal reports don't need a card wrapper — just the plain
    // detail rows, matching how every other field on this screen renders.
    if (total <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailSection(label: 'No. of Animals', value: '1'),
          ..._animalFields(),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.tearspwn.withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Animal $index of $total${highlight ? ' (this report)' : ''}',
              style: GoogleFonts.zain(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          ..._animalFields(),
        ],
      ),
    );
  }

  List<Widget> _animalFields() {
    final species = data['animalType'] as String?;
    final breed = data['breed'] as String?;
    final sex = data['sex'] as String?;
    final size = data['size'] as String?;
    final colorMarkings = data['colorMarkings'] as String?;
    final biteRisk = data['biteRisk'] as String?;
    final escapeRisk = data['escapeRisk'] as String?;

    return [
      if (species != null && species.isNotEmpty) _DetailSection(label: 'Species', value: species),
      if (breed != null && breed.isNotEmpty) _DetailSection(label: 'Breed / Mixed', value: breed),
      if (sex != null && sex.isNotEmpty) _DetailSection(label: 'Sex', value: sex),
      if (size != null && size.isNotEmpty) _DetailSection(label: 'Size', value: size),
      if (colorMarkings != null && colorMarkings.isNotEmpty)
        _DetailSection(label: 'Color / Distinguishing Markings', value: colorMarkings),
      if (biteRisk != null && biteRisk.isNotEmpty) _DetailSection(label: 'Bite Risk', value: biteRisk),
      if (escapeRisk != null && escapeRisk.isNotEmpty) _DetailSection(label: 'Escape Risk', value: escapeRisk),
    ];
  }
}