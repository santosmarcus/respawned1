import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/animal_records_flow_page.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_flow.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';

typedef ShelterDestination = ({
  String name,
  String? address,
  String? placeId,
  double? lat,
  double? lng,
});

class IntakeDetailPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;

  /// Restricts this page's "Animal Records" progress (spec §9) to a
  /// specific subset of the case's `animals[]` indexes — the animals the
  /// admin selected on Treatment Details' Intake action. Null means "every
  /// animal on the case" (legacy whole-case behavior, unchanged) — the
  /// shelter destination/transport/quarantine sections below stay
  /// case-wide either way (a case only ever has one transport leg/shelter
  /// destination/quarantine decision, even with animals on separate
  /// post-treatment paths).
  final List<int>? animalIndexes;

  const IntakeDetailPage({
    super.key,
    required this.caseId,
    required this.data,
    this.animalIndexes,
  });

  @override
  ConsumerState<IntakeDetailPage> createState() => _IntakeDetailPageState();
}

class _IntakeDetailPageState extends ConsumerState<IntakeDetailPage> {
  bool _isConfirmingIntake = false;
  bool _isConfirmingReceived = false;
  bool _isStartingQuarantine = false;
  bool _isEndingQuarantine = false;
  bool _isSkippingQuarantine = false;
  bool _isClosingCase = false;
  final _quarantineDaysController = TextEditingController(text: '7');
  bool _hasCheckedQuarantineAutoComplete = false;
  bool _quarantineExpanded = false;

  ShelterDestination? _resolvedDestination;
  String? _currentOrganizationId;

  @override
  void initState() {
    super.initState();
    _resolveDestination();
  }

  @override
  void dispose() {
    _quarantineDaysController.dispose();
    super.dispose();
  }

  /// Resolves the Intake destination in priority order: the linked
  /// organization's saved shelter location -> this account's own temporary
  /// saved shelter location (see the TODO on the user-scoped fallback below
  /// — testing-only, for accounts with no organization membership yet) ->
  /// null, in which case the UI prompts "Set Shelter Location" instead of
  /// silently defaulting to a placeholder address.
  Future<void> _resolveDestination() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    ShelterDestination? resolved;
    String? orgId;
    if (uid != null) {
      final membership = await OrgMembershipService().getMembership(uid);
      orgId = membership?.organizationId;
      final repo = ref.read(organizationDirectoryRepositoryProvider);
      resolved = await repo.resolveShelterLocation(orgId);
      // TODO: Remove the user-scoped shelter fallback once organization
      // membership is required for every admin/NGO account.
      resolved ??= await repo.resolveUserShelterLocation(uid);
    }
    if (mounted) {
      setState(() {
        _resolvedDestination = resolved;
        _currentOrganizationId = orgId;
      });
    }
  }

  Future<void> _openShelterPicker() async {
    final orgId = _currentOrganizationId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (orgId == null && (uid == null || uid.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to set a shelter location.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    // No organization linked -> save onto this account's own temporary
    // shelter fields instead, so Intake can still be exercised end-to-end.
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage(
          organizationId: orgId,
          userId: orgId == null ? uid : null,
        ),
      ),
    );
    if (saved == true) _resolveDestination();
  }

  /// Fires at most once per page instance. See
  /// RescueCaseRepository.checkAndCompleteQuarantineIfDue's own doc comment
  /// for why this is a read-time derived completion, not a live timer.
  Future<void> _checkQuarantineAutoComplete(RescueCase c) async {
    if (_hasCheckedQuarantineAutoComplete) return;
    _hasCheckedQuarantineAutoComplete = true;
    if (c.quarantineStatus == 'active' && !c.isQuarantineActive) {
      await ref
          .read(rescueCaseRepositoryProvider)
          .checkAndCompleteQuarantineIfDue(c);
    }
  }

  /// Reactively completes Intake the moment "animal received" and "every
  /// expected animal record created" are both true — deliberately NOT
  /// guarded to fire only once per page instance (unlike quarantine's
  /// check above): completedCount changes live while this page stays
  /// mounted underneath a pushed AnimalRecordsFlowPage route, and
  /// RescueCaseRepository.checkAndCompleteIntakeIfDue is cheap/idempotent
  /// (its own guards make every call a no-op once already complete, or
  /// before intake is received / before every record exists).
  Future<void> _checkIntakeAutoComplete(
    RescueCase c, {
    required int completedCount,
    required int totalAnimals,
  }) async {
    await ref
        .read(rescueCaseRepositoryProvider)
        .checkAndCompleteIntakeIfDue(
          c,
          totalAnimalsExpected: totalAnimals,
          completedCount: completedCount,
        );
  }

  Future<void> _confirmIntake({
    required RescueCase c,
    required String? transporterUid,
    required String transporterName,
    required String transporterType,
    required bool transporterIsDemo,
  }) async {
    if (_isConfirmingIntake) return;
    final destination = _resolvedDestination;
    if (destination == null ||
        destination.lat == null ||
        destination.lng == null)
      return;
    if (transporterUid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Intake',
          style: GoogleFonts.tiltWarp(
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow('Intake Destination', destination.name),
            _ConfirmRow('Transporter', '$transporterName ($transporterType)'),
            _ConfirmRow(
              'Clinic Pickup Location',
              c.vetClinicName ?? 'Not on file',
            ),
            _ConfirmRow('Case ID', '#${c.shortCaseId}'),
            _ConfirmRow('Species Summary', c.speciesSummary),
            _ConfirmRow(
              'Discharge Date',
              c.dischargedAt != null
                  ? '${_monthName(c.dischargedAt!.month)} ${c.dischargedAt!.day}, ${c.dischargedAt!.year}'
                  : 'Not on file',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              'Confirm',
              style: GoogleFonts.zain(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isConfirmingIntake = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .confirmIntake(
            caseId: widget.caseId,
            destinationName: destination.name,
            destinationAddress: destination.address,
            destinationPlaceId: destination.placeId,
            destinationLat: destination.lat,
            destinationLng: destination.lng,
            transporterUid: transporterUid,
            transporterName: transporterName,
            transporterType: transporterType,
            isDemoTransporter: transporterIsDemo,
          );
      if (mounted) setState(() => _isConfirmingIntake = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isConfirmingIntake = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not confirm intake: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Marks the animal as physically received at the shelter — reuses
  /// RescueCaseRepository.confirmAnimalReceived exactly as Track Case's own
  /// intake-mode "Confirm Animal Received" button already does, just
  /// exposed here too so the admin doesn't have to leave Intake Details to
  /// take this action. Stamps intakeReceivedAt (server timestamp), and —
  /// when a transport assignment is on file — completes it in the same
  /// call, which is what frees the transporter back to Available. Never
  /// touches the case's own RescueStatus: the case stays in Intake.
  Future<void> _confirmAnimalReceived(RescueCase c) async {
    if (_isConfirmingReceived) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Confirm Animal Received',
      message:
          'Confirm that the animal has arrived at the shelter?\n\n'
          'This will complete the transport assignment and allow animal records to be created.',
      confirmLabel: 'Confirm Received',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isConfirmingReceived = true);
    try {
      final assignment = ref
          .read(currentAssignmentProvider(widget.caseId))
          .asData
          ?.value;
      await ref
          .read(rescueCaseRepositoryProvider)
          .confirmAnimalReceived(
            caseId: widget.caseId,
            currentAssignmentId: assignment?.id,
            animalIndexes: widget.animalIndexes,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not confirm receipt: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirmingReceived = false);
    }
  }

  Future<void> _closeCase(RescueCase c) async {
    if (_isClosingCase) return;
    setState(() => _isClosingCase = true);
    try {
      final outcome = await performCloseCase(context, ref, c);
      if (outcome.acted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.wholeCaseClosed
                  ? 'Case closed.'
                  : 'Animal marked deceased.',
            ),
          ),
        );
        if (outcome.wholeCaseClosed) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not close case: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClosingCase = false);
    }
  }

  Future<void> _startQuarantine() async {
    final days = int.tryParse(_quarantineDaysController.text.trim());
    if (days == null || days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a quarantine duration in days.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isStartingQuarantine = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .startQuarantine(caseId: widget.caseId, durationDays: days);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start quarantine: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingQuarantine = false);
    }
  }

  Future<void> _endQuarantine() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'End Quarantine?',
      message:
          'This marks quarantine complete right now, ahead of its scheduled end.',
      confirmLabel: 'End Quarantine',
    );
    if (!confirmed) return;
    setState(() => _isEndingQuarantine = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .endQuarantine(
            caseId: widget.caseId,
            reason: 'Manually ended early.',
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not end quarantine: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isEndingQuarantine = false);
    }
  }

  Future<void> _skipQuarantine() async {
    setState(() => _isSkippingQuarantine = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .skipQuarantine(caseId: widget.caseId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not skip quarantine: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSkippingQuarantine = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveCase = ref.watch(caseDetailProvider(widget.caseId)).asData?.value;
    final c = liveCase ?? RescueCase.fromMap(widget.caseId, widget.data);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkQuarantineAutoComplete(c),
    );

    final latestAssignment = ref
        .watch(currentAssignmentProvider(widget.caseId))
        .asData
        ?.value;

    // Default transporter priority: most recent accepted/completed
    // transport assignment -> the case's own flat assignedVolunteer*
    // fields (set the same way by acceptAssignment/confirmIntake) -> none.
    // Opening this page never writes any of this — purely a read.
    String? defaultUid;
    String defaultName = 'Unassigned';
    String defaultType = 'Pet Transporter';
    bool defaultIsDemo = false;
    if (latestAssignment != null &&
        (latestAssignment.status == TransportAssignmentStatus.accepted ||
            latestAssignment.status == TransportAssignmentStatus.completed)) {
      defaultUid = latestAssignment.riderId;
      defaultName = latestAssignment.riderName;
      defaultType = latestAssignment.riderType;
      defaultIsDemo = latestAssignment.isDemo;
    } else if (c.assignedVolunteerId != null) {
      defaultUid = c.assignedVolunteerId;
      defaultName = c.assignedVolunteerName ?? 'Unnamed Transporter';
    }

    // A case admitted from an existing Animal Record (medical re-admission
    // or an adoption return — see RescueCaseRepository.createAdmissionCase/
    // createReturnIntakeCase) reuses that record instead of creating a new
    // one, so there is nothing new for streamCompletedAnimalRecordIndexes
    // (which only counts records CREATED FROM this case) to ever find.
    // Treat every animal as already having its record in that case, both
    // for the UI below and for intake auto-completion.
    final sourceAnimalRecordId = c.raw['sourceAnimalRecordId'] as String?;
    // Per-animal path (spec §9): scoped to just the animals this Intake
    // action was started for — another animal on the same case may still
    // be mid-Treatment or on a different post-treatment path, and this
    // page's own "N of M records" progress/completion must never wait on
    // that other animal.
    final totalAnimals = widget.animalIndexes?.length ?? c.animalCount;
    final allCompletedIndexes = sourceAnimalRecordId != null
        ? Set<int>.from(List.generate(c.animalCount, (i) => i))
        : (ref
                  .watch(completedAnimalRecordIndexesProvider(widget.caseId))
                  .asData
                  ?.value ??
              <int>{});
    final completedIndexes = widget.animalIndexes != null
        ? allCompletedIndexes.where(widget.animalIndexes!.contains).toSet()
        : allCompletedIndexes;
    final intakeAnimalIndexes =
        widget.animalIndexes ?? List<int>.generate(c.animalCount, (i) => i);
    final selectedAnimalsReceived =
        intakeAnimalIndexes.isNotEmpty &&
        intakeAnimalIndexes.every((i) => animalIsReceived(c, i));

    if (widget.animalIndexes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (completedIndexes.length >= totalAnimals &&
            selectedAnimalsReceived) {
          await ref
              .read(rescueCaseRepositoryProvider)
              .completeIntakeForAnimals(
                caseId: widget.caseId,
                animalIndexes: widget.animalIndexes!,
              );
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkIntakeAutoComplete(
          c,
          completedCount: completedIndexes.length,
          totalAnimals: totalAnimals,
        ),
      );
    }

    final dischargeDateStr = c.dischargedAt != null
        ? '${_monthName(c.dischargedAt!.month)} ${c.dischargedAt!.day}, ${c.dischargedAt!.year}'
        : '-';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Intake Details',
          style: GoogleFonts.tiltWarp(
            fontSize: 18,
            color: AppColors.background,
          ),
        ),
        // Reassign Transporter / Change Intake Destination live here instead
        // of as standalone buttons in the body — Reassign is only offered
        // while there's still something to reassign (before the animal is
        // marked received); Change Destination stays available throughout.
        actions: [
          if (c.intakeConfirmedAt != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.background),
              onSelected: (value) {
                switch (value) {
                  case 'reassign':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignRiderPage(
                          caseId: widget.caseId,
                          data: c.raw,
                          postAcceptTrackingMode: TrackingMode.intakeTransfer,
                        ),
                      ),
                    );
                    break;
                  case 'change_destination':
                    _openShelterPicker();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (c.intakeReceivedAt == null)
                  const PopupMenuItem(
                    value: 'reassign',
                    child: Text('Reassign Transporter'),
                  ),
                const PopupMenuItem(
                  value: 'change_destination',
                  child: Text('Change Intake Destination'),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — same hierarchy as Treatment Details / Rescue Reports.
            Text(
              '#${c.shortCaseId}',
              style: GoogleFonts.tiltWarp(
                fontSize: 22,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              c.speciesSummary,
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if ((c.vetClinicName ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                c.vetClinicName!,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              'Discharged $dischargeDateStr',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),

            if (c.raw['sourceType'] == 'adoptionReturn') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.pinkrspwn.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.assignment_return_outlined,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Intake Source: Adoption Return',
                      style: GoogleFonts.zain(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            if (c.intakeConfirmedAt == null)
              _ConfirmIntakeSection(
                rescueCase: c,
                destination: _resolvedDestination,
                defaultUid: defaultUid,
                defaultName: defaultName,
                defaultType: defaultType,
                defaultIsDemo: defaultIsDemo,
                isConfirming: _isConfirmingIntake,
                onChangeShelter: _openShelterPicker,
                onReassign: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssignRiderPage(
                      caseId: widget.caseId,
                      data: c.raw,
                      postAcceptTrackingMode: TrackingMode.intakeTransfer,
                    ),
                  ),
                ),
                onConfirm: () => _confirmIntake(
                  c: c,
                  transporterUid: defaultUid,
                  transporterName: defaultName,
                  transporterType: defaultType,
                  transporterIsDemo: defaultIsDemo,
                ),
              )
            else ...[
              _SectionHeader('Intake Destination'),
              _InfoItem('Destination', c.intakeDestinationName ?? '-'),
              if ((c.intakeDestinationAddress ?? '').isNotEmpty)
                _InfoItem('Address', c.intakeDestinationAddress!),
              const SizedBox(height: 16),

              // Compact transport summary only — the full transporter card
              // (avatar, vehicle, Message/Call, Busy chip) already lives on
              // Track Case and isn't repeated here. Reassign Transporter
              // moved to the overflow menu (see AppBar actions above).
              _SectionHeader('Clinic-to-Shelter Transport'),
              if (selectedAnimalsReceived)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenrspwn.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.greenrspwn,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Animal received',
                              style: GoogleFonts.zain(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              c.intakeReceivedAt == null
                                  ? 'Receipt confirmed'
                                  : 'Received ${_monthName(c.intakeReceivedAt!.month)} '
                                        '${c.intakeReceivedAt!.day}, ${c.intakeReceivedAt!.year}',
                              style: GoogleFonts.zain(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Transport in progress.',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminTrackCasePage(
                      caseId: widget.caseId,
                      data: c.raw,
                      mode: TrackingMode.intakeTransfer,
                    ),
                  ),
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(
                  'View Transport Tracking',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _QuarantineSection(
                rescueCase: c,
                daysController: _quarantineDaysController,
                isStarting: _isStartingQuarantine,
                isEnding: _isEndingQuarantine,
                isSkipping: _isSkippingQuarantine,
                expanded: _quarantineExpanded,
                onToggleExpand: () =>
                    setState(() => _quarantineExpanded = !_quarantineExpanded),
                onStart: _startQuarantine,
                onEnd: _endQuarantine,
                onSkip: _skipQuarantine,
              ),

              const SizedBox(height: 20),
              if (!selectedAnimalsReceived) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isConfirmingReceived
                        ? null
                        : () => _confirmAnimalReceived(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      disabledBackgroundColor: AppColors.slaterspwn,
                      foregroundColor: AppColors.textPrimary,
                      disabledForegroundColor: AppColors.textSecondary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isConfirmingReceived
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : Text(
                            'Confirm Animal Received',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _AnimalRecordsSection(
                caseId: widget.caseId,
                data: c.raw,
                totalAnimals: totalAnimals,
                completedCount: completedIndexes.length,
                received: selectedAnimalsReceived,
                sourceAnimalRecordId: sourceAnimalRecordId,
                animalIndexes: widget.animalIndexes,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isClosingCase ? null : () => _closeCase(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE05353),
                    side: const BorderSide(color: Color(0xFFE05353)),
                    disabledForegroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isClosingCase
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Close Case',
                          style: GoogleFonts.tiltWarp(fontSize: 15),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ConfirmIntakeSection extends StatelessWidget {
  final RescueCase rescueCase;
  final ShelterDestination? destination;
  final String? defaultUid;
  final String defaultName;
  final String defaultType;
  final bool defaultIsDemo;
  final bool isConfirming;
  final VoidCallback onChangeShelter;
  final VoidCallback onReassign;
  final VoidCallback onConfirm;

  const _ConfirmIntakeSection({
    required this.rescueCase,
    required this.destination,
    required this.defaultUid,
    required this.defaultName,
    required this.defaultType,
    required this.defaultIsDemo,
    required this.isConfirming,
    required this.onChangeShelter,
    required this.onReassign,
    required this.onConfirm,
  });

  bool get _hasUsableDestination =>
      destination != null &&
      destination!.lat != null &&
      destination!.lng != null;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _hasUsableDestination && defaultUid != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Confirm Intake'),
        _DestinationCard(
          destination: destination,
          onChangeShelter: onChangeShelter,
        ),
        const SizedBox(height: 16),
        _InfoItem(
          'Selected Transporter',
          defaultUid != null ? '$defaultName ($defaultType)' : 'None selected',
        ),
        _InfoItem(
          'Clinic Pickup Location',
          rescueCase.vetClinicName ?? 'Not on file',
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onReassign,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.textPrimary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            'Reassign Transporter',
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 20),
        if (!canConfirm) ...[
          Text(
            !_hasUsableDestination
                ? 'Set a shelter location before confirming intake.'
                : 'Select a transporter before confirming intake.',
            style: GoogleFonts.zain(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isConfirming
                ? null
                : (!_hasUsableDestination
                      ? onChangeShelter
                      : (canConfirm ? onConfirm : null)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              disabledBackgroundColor: AppColors.slaterspwn,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: isConfirming
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : Text(
                    !_hasUsableDestination
                        ? 'Set Shelter Location'
                        : 'Confirm Intake',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// "Intake Destination / <name> / [Change Location]" or, with nothing
/// configured yet, "No shelter location configured. / [Set Shelter
/// Location]" — deliberately card-sized, not a permanent map; the map only
/// exists inside ShelterLocationPickerPage.
class _DestinationCard extends StatelessWidget {
  final ShelterDestination? destination;
  final VoidCallback onChangeShelter;

  const _DestinationCard({
    required this.destination,
    required this.onChangeShelter,
  });

  @override
  Widget build(BuildContext context) {
    final d = destination;
    final hasCoords = d != null && d.lat != null && d.lng != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Row(
        children: [
          Icon(
            Icons.home_work_outlined,
            color: hasCoords ? AppColors.textPrimary : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Intake Destination',
                  style: GoogleFonts.zain(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d == null ? 'No shelter location configured.' : d.name,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (d != null && (d.address ?? '').isNotEmpty)
                  Text(
                    d.address!,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (d != null && !hasCoords)
                  Text(
                    'No coordinates on file — set an exact location.',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onChangeShelter,
            child: Text(
              d == null ? 'Set Shelter Location' : 'Change Location',
              style: GoogleFonts.zain(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed by default — shows only title + a one-line status summary +
/// expand arrow, never the active quarantine's controls or dates in full.
/// The summary line itself (computed from persisted quarantineStatus/
/// quarantine*At fields, not local state) always stays visible even while
/// collapsed, so an active quarantine is never silently hidden. Expand/
/// collapse is purely a local UI toggle owned by the parent page — it does
/// not read or write Firestore.
class _QuarantineSection extends StatelessWidget {
  final RescueCase rescueCase;
  final TextEditingController daysController;
  final bool isStarting;
  final bool isEnding;
  final bool isSkipping;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onSkip;

  const _QuarantineSection({
    required this.rescueCase,
    required this.daysController,
    required this.isStarting,
    required this.isEnding,
    required this.isSkipping,
    required this.expanded,
    required this.onToggleExpand,
    required this.onStart,
    required this.onEnd,
    required this.onSkip,
  });

  ({String title, String subtitle}) _summary(RescueCase c) {
    if (c.quarantineStatus == 'active' && c.isQuarantineActive) {
      final end = c.quarantineScheduledEndAt;
      return (
        title: 'Quarantine',
        subtitle: end != null ? 'Active · Ends ${_fmtDate(end)}' : 'Active',
      );
    }
    if (c.hasQuarantineDecision) {
      if (c.quarantineStatus == 'skipped')
        return (title: 'Quarantine', subtitle: 'Skipped');
      final end = c.quarantineEndedAt;
      return (
        title: 'Quarantine',
        subtitle: end != null ? 'Completed ${_fmtDate(end)}' : 'Completed',
      );
    }
    return (title: 'Quarantine — Optional', subtitle: 'Not started');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary(rescueCase);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.title,
                        style: GoogleFonts.tiltWarp(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.subtitle,
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            _buildExpandedContent(rescueCase),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedContent(RescueCase c) {
    if (c.quarantineStatus == 'active' && c.isQuarantineActive) {
      final remaining = c.quarantineScheduledEndAt?.difference(DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.quarantineStartedAt != null)
            _InfoItem('Started', _fmtDate(c.quarantineStartedAt!)),
          if (c.quarantineDurationDays != null)
            _InfoItem('Duration', '${c.quarantineDurationDays} days'),
          if (c.quarantineScheduledEndAt != null)
            _InfoItem('Scheduled End', _fmtDate(c.quarantineScheduledEndAt!)),
          if (remaining != null)
            _InfoItem('Remaining', '${remaining.inDays} day(s)'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isEnding ? null : onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE05353),
                side: const BorderSide(color: Color(0xFFE05353)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: isEnding
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'End Quarantine',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      );
    }

    if (c.hasQuarantineDecision) {
      final isSkipped = c.quarantineStatus == 'skipped';
      final detail = isSkipped
          ? 'Quarantine was skipped for this case.'
          : 'Quarantine completed'
                '${c.quarantineEndedAt != null ? ' on ${_fmtDate(c.quarantineEndedAt!)}' : ''}.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.slaterspwn),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              isSkipped ? 'Quarantine Skipped' : 'Quarantine Completed',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: GoogleFonts.zain(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    // Not yet decided — offer Start/Skip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Days',
                  labelStyle: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 6),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textPrimary),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.textPrimary,
                      width: 1.5,
                    ),
                  ),
                ),
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: isStarting ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  // Explicit foreground — without it, ElevatedButton falls
                  // back to the theme's ColorScheme.onPrimary, which (since
                  // the app theme overrides `primary` to yellowrspwn without
                  // recomputing onPrimary to match) ends up too close to the
                  // yellow background to read. Every other yellow button in
                  // this file already sets this explicitly; this one didn't.
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textSecondary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: isStarting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Text(
                        'Start Quarantine',
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: isSkipping ? null : onSkip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.slaterspwn),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: isSkipping
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Skip',
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) => '${_monthName(d.month)} ${d.day}, ${d.year}';
}

/// Disabled — with a real, always-visible reason, not just a greyed-out
/// button — until the animal has actually arrived at the shelter
/// (RescueCase.intakeReceivedAt). Enforced again in
/// CreateAnimalRecordPage._createRecord itself, so this UI gate is backup,
/// not the only line of defense.
class _AnimalRecordsSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final int totalAnimals;
  final int completedCount;
  final bool received;

  /// Set when this case was admitted from an animal that already has an
  /// Animal Record (RescueCase.raw['sourceAnimalRecordId'] — written by
  /// RescueCaseRepository.createAdmissionCase/createReturnIntakeCase). The
  /// existing record is reused, never duplicated — this section becomes
  /// "View Animal Record" instead of Create/Continue. Per-animal mixed
  /// handling (some animals in a multi-animal case already have records,
  /// others don't) isn't representable yet: sourceAnimalRecordId is a
  /// single case-level id, and both origin flows that set it are
  /// single-animal only today.
  final String? sourceAnimalRecordId;
  final List<int>? animalIndexes;

  const _AnimalRecordsSection({
    required this.caseId,
    required this.data,
    required this.totalAnimals,
    required this.completedCount,
    required this.received,
    this.sourceAnimalRecordId,
    this.animalIndexes,
  });

  @override
  Widget build(BuildContext context) {
    final recordId = sourceAnimalRecordId;
    if (recordId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This case was admitted from an existing Animal Record — no new record is created.',
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnimalRecordDetailPage(
                    animalId: recordId,
                    data: const {},
                  ),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'View Animal Record',
                style: GoogleFonts.tiltWarp(fontSize: 15),
              ),
            ),
          ),
        ],
      );
    }

    final allDone = completedCount >= totalAnimals;
    final buttonLabel = allDone
        ? 'View Animal Records'
        : (completedCount == 0
              ? 'Create Animal Records'
              : 'Continue Animal Records');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          received
              ? '$completedCount of $totalAnimals records created'
              : 'Confirm that the animal has been received before creating its record.',
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: !received
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnimalRecordsFlowPage(
                        caseId: caseId,
                        caseData: data,
                        animalIndexes: animalIndexes,
                      ),
                    ),
                  ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              disabledBackgroundColor: AppColors.slaterspwn,
              foregroundColor: AppColors.textPrimary,
              disabledForegroundColor: AppColors.textSecondary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              received ? buttonLabel : 'Create Animal Records',
              style: GoogleFonts.tiltWarp(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
