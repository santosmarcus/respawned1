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
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_flow.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transporter_details_card.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

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
  bool _resolvingDestination = true;
  // Post-frame intake completion runs once per distinct state, not on every
  // rebuild (each rebuild used to schedule another uncaught transaction).
  String? _lastIntakeCompletionKey;

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
    if (mounted) setState(() => _resolvingDestination = true);
    try {
      if (uid != null) {
        final membership = await OrgMembershipService().getMembership(uid);
        orgId = membership?.organizationId;
        final repo = ref.read(organizationDirectoryRepositoryProvider);
        resolved = await repo.resolveShelterLocation(orgId);
        // TODO: Remove the user-scoped shelter fallback once organization
        // membership is required for every admin/NGO account.
        resolved ??= await repo.resolveUserShelterLocation(uid);
      }
    } catch (_) {
      // Shown as "no shelter location" with a way to set one.
    }
    if (mounted) {
      setState(() {
        _resolvedDestination = resolved;
        _currentOrganizationId = orgId;
        _resolvingDestination = false;
      });
    }
  }

  Future<void> _openShelterPicker() async {
    final orgId = _currentOrganizationId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (orgId == null && (uid == null || uid.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Sign in to set a shelter location.', kind: AppMessageKind.error),
      );
      return;
    }
    // Open on whatever is already saved where this will write
    // (organizations/{orgId}.shelter*, or the account's own temporary
    // shelter), not a blank search. A legacy name-only location has no pin
    // to show, so it opens blank.
    final repo = ref.read(organizationDirectoryRepositoryProvider);
    ShelterDestination? current;
    try {
      current = orgId != null ? await repo.resolveShelterLocation(orgId) : await repo.resolveUserShelterLocation(uid);
    } catch (_) {
      current = null;
    }
    if (current != null && (current.lat == null || current.lng == null)) current = null;
    if (!mounted) return;
    // No organization linked -> save onto this account's own temporary
    // shelter fields instead, so Intake can still be exercised end-to-end.
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage(
          organizationId: orgId,
          userId: orgId == null ? uid : null,
          initialName: current?.name,
          initialAddress: current?.address,
          initialPlaceId: current?.placeId,
          initialLat: current?.lat,
          initialLng: current?.lng,
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
        destination.lng == null) {
      return;
    }
    if (transporterUid == null) return;

    // No second "Confirm Intake" popup: this page already lists the
    // destination, transporter and case, so the button is the confirmation.

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
          appSnackBar('Could not confirm intake: $e', kind: AppMessageKind.error),
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
          appSnackBar('Could not confirm receipt: $e', kind: AppMessageKind.error),
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
          appSnackBar(outcome.wholeCaseClosed
                  ? 'Case closed.'
                  : 'Animal marked deceased.'),
        );
        if (outcome.wholeCaseClosed) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not close case: $e', kind: AppMessageKind.error),
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
        appSnackBar('Enter a quarantine duration in days.', kind: AppMessageKind.error),
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
          appSnackBar('Could not start quarantine: $e', kind: AppMessageKind.error),
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
          appSnackBar('Could not end quarantine: $e', kind: AppMessageKind.error),
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
          appSnackBar('Could not skip quarantine: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSkippingQuarantine = false);
    }
  }

  void _reassignTransporter(RescueCase c) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssignRiderPage(
            caseId: widget.caseId,
            data: c.raw,
            postAcceptTrackingMode: TrackingMode.intakeTransfer,
          ),
        ),
      );

  /// Before intake is confirmed: Confirm Intake (or Set Shelter Location
  /// when none is usable yet) and Reassign, in the same sticky bar every
  /// other case page uses.
  Widget _confirmBar(
    RescueCase c, {
    required String? defaultUid,
    required String defaultName,
    required String defaultType,
    required bool defaultIsDemo,
  }) {
    final d = _resolvedDestination;
    final hasDestination = d != null && d.lat != null && d.lng != null;
    final CaseAction primary;
    if (_resolvingDestination) {
      primary = const CaseAction('Confirm Intake', null);
    } else if (!hasDestination) {
      primary = CaseAction('Set Shelter Location', _openShelterPicker);
    } else {
      primary = CaseAction(
        'Confirm Intake',
        defaultUid == null
            ? null
            : () => _confirmIntake(
                  c: c,
                  transporterUid: defaultUid,
                  transporterName: defaultName,
                  transporterType: defaultType,
                  transporterIsDemo: defaultIsDemo,
                ),
      );
    }
    // Reassign lives on the transporter card's menu; Assign shows here only
    // while there is no transporter yet.
    return CaseActionBar(
      primary: primary,
      secondary: defaultUid == null
          ? CaseAction('Assign Transporter', () => _reassignTransporter(c), icon: Icons.swap_horiz)
          : null,
      busy: _isConfirmingIntake,
    );
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

    final completionKey =
        '${completedIndexes.length}/$totalAnimals/$selectedAnimalsReceived/${c.intakeReceivedAt != null}';
    if (completionKey != _lastIntakeCompletionKey) {
      _lastIntakeCompletionKey = completionKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          if (widget.animalIndexes != null) {
            if (completedIndexes.length >= totalAnimals && selectedAnimalsReceived) {
              await ref.read(rescueCaseRepositoryProvider).completeIntakeForAnimals(
                    caseId: widget.caseId,
                    animalIndexes: widget.animalIndexes!,
                  );
            }
          } else {
            await _checkIntakeAutoComplete(
              c,
              completedCount: completedIndexes.length,
              totalAnimals: totalAnimals,
            );
          }
        } catch (e) {
          debugPrint('Intake auto-complete skipped: $e');
          _lastIntakeCompletionKey = null; // retry on the next change
        }
      });
    }

    final dischargeDateStr = c.dischargedAt != null
        ? formatDate(c.dischargedAt!)
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
        // Nothing left to change once the animal is at the shelter.
        actions: [
          if (!selectedAnimalsReceived)
          CaseOverflowMenu(
            busy: _isConfirmingReceived || _isClosingCase,
            actions: [
              CaseAction('Change Intake Destination', _openShelterPicker, icon: Icons.home_work_outlined),
              CaseAction('Close Case', _isClosingCase ? null : () => _closeCase(c), icon: Icons.block, destructive: true),
            ],
          ),
        ],
      ),
      // Once intake is confirmed, the bar has only Confirm Animal Received
      // (until it is). Transport Tracking and Reassign Transporter are on the
      // transporter card; Change Intake Destination and Close Case are in
      // the app bar's menu.
      bottomNavigationBar: c.intakeConfirmedAt == null
          ? _confirmBar(c,
              defaultUid: defaultUid,
              defaultName: defaultName,
              defaultType: defaultType,
              defaultIsDemo: defaultIsDemo)
          : CaseActionBar.maybe(
              primary: selectedAnimalsReceived
                  ? null
                  : CaseAction('Confirm Animal Received', _isConfirmingReceived ? null : () => _confirmAnimalReceived(c)),
              busy: _isConfirmingReceived || _isClosingCase,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — same hierarchy as Treatment Details / Rescue Reports.
            CaseHeaderCard(
              title: c.speciesSummary,
              caseId: c.shortCaseId,
              reporterName: c.reporterName,
              photoUrls: c.photoUrls,
              badges: [
                if ((c.vetClinicName ?? '').isNotEmpty)
                  CaseBadge(label: c.vetClinicName!, icon: Icons.local_hospital_outlined),
                CaseBadge(label: 'Discharged $dischargeDateStr', icon: Icons.event_outlined, color: AppColors.tearspwn),
                if (c.raw['sourceType'] == 'adoptionReturn')
                  const CaseBadge(
                      label: 'Intake source: adoption return',
                      icon: Icons.assignment_return_outlined,
                      color: AppColors.pinkrspwn),
              ],
            ),
            const SizedBox(height: kCaseGap),
            if (c.intakeConfirmedAt == null)
              const CaseOutcomeBanner(
                tone: CaseBannerTone.info,
                icon: Icons.arrow_forward,
                title: 'Next: confirm intake',
                message: 'Check the shelter destination and the transporter, then confirm to start the trip.',
              )
            else if (selectedAnimalsReceived)
              CaseOutcomeBanner(
                tone: CaseBannerTone.success,
                icon: Icons.check_circle_outline,
                title: 'Animal received',
                message: c.intakeReceivedAt == null
                    ? 'Receipt confirmed. Finish quarantine and the animal records below.'
                    : 'Received ${formatDate(c.intakeReceivedAt!)}. Finish quarantine and the animal records below.',
              )
            else
              const CaseOutcomeBanner(
                tone: CaseBannerTone.info,
                icon: Icons.local_shipping_outlined,
                title: 'Transport in progress',
                message: 'Confirm the animal was received when it arrives at the shelter.',
              ),
            const SizedBox(height: kCaseGap),

            if (c.intakeConfirmedAt == null)
              _ConfirmIntakeSection(
                destination: _resolvedDestination,
                resolvingDestination: _resolvingDestination,
                assignment: (latestAssignment != null &&
                        (latestAssignment.status == TransportAssignmentStatus.accepted ||
                            latestAssignment.status == TransportAssignmentStatus.completed))
                    ? latestAssignment
                    : null,
                defaultUid: defaultUid,
                defaultName: defaultName,
                defaultType: defaultType,
                onChangeShelter: _openShelterPicker,
                onReassign: () => _reassignTransporter(c),
              )
            else ...[
              CaseInfoGrid(
                title: 'Intake destination',
                items: [
                  CaseInfoItem('Destination', c.intakeDestinationName ?? '-'),
                  CaseInfoItem('Address', c.intakeDestinationAddress, wide: true),
                ],
              ),
              const SizedBox(height: kCaseGap),

              // Transporter Card Regression spec §4 — restores the shared
              // transporter card here too (it previously showed only a
              // compact text summary, deferring to Track Case for the full
              // card). Reuses `latestAssignment` — the SAME
              // currentAssignmentProvider value _confirmIntake itself uses
              // for transporterUid/Name/Type — so this can never disagree
              // with what intake actually records, and tolerates legacy
              // case-level assignments the same way that fallback already
              // does. Stays visible (with a "Completed" chip) after
              // delivery for historical context; Reassign Transporter
              // stays in the overflow menu (see AppBar actions above) —
              // not re-added to the card itself.
              if (latestAssignment != null &&
                  (latestAssignment.status == TransportAssignmentStatus.accepted ||
                      latestAssignment.status == TransportAssignmentStatus.completed)) ...[
                _SectionHeader('Clinic-to-Shelter Transport'),
                TransporterDetailsCard(
                  assignment: latestAssignment,
                  onTrack: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminTrackCasePage(
                        caseId: widget.caseId,
                        data: c.raw,
                        mode: TrackingMode.intakeTransfer,
                      ),
                    ),
                  ),
                  menuActions: [
                    if (c.intakeReceivedAt == null)
                      CaseAction(
                        'Reassign Transporter',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssignRiderPage(
                              caseId: widget.caseId,
                              data: c.raw,
                              postAcceptTrackingMode: TrackingMode.intakeTransfer,
                            ),
                          ),
                        ),
                        icon: Icons.swap_horiz,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
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
              _AnimalRecordsSection(
                caseId: widget.caseId,
                data: c.raw,
                totalAnimals: totalAnimals,
                completedCount: completedIndexes.length,
                received: selectedAnimalsReceived,
                sourceAnimalRecordId: sourceAnimalRecordId,
                animalIndexes: widget.animalIndexes,
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
  final ShelterDestination? destination;
  final bool resolvingDestination;
  final TransportAssignment? assignment;
  final String? defaultUid;
  final String defaultName;
  final String defaultType;
  final VoidCallback onChangeShelter;
  final VoidCallback onReassign;

  const _ConfirmIntakeSection({
    required this.destination,
    required this.resolvingDestination,
    required this.assignment,
    required this.defaultUid,
    required this.defaultName,
    required this.defaultType,
    required this.onChangeShelter,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final hasUsableDestination =
        destination != null && destination!.lat != null && destination!.lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Shelter destination'),
        if (resolvingDestination)
          const _DestinationLoadingCard()
        else
          _DestinationCard(destination: destination, onChangeShelter: onChangeShelter),
        const SizedBox(height: 16),
        _SectionHeader('Clinic-to-shelter transporter'),
        if (assignment != null)
          TransporterDetailsCard(
            assignment: assignment!,
            menuActions: [CaseAction('Reassign Transporter', onReassign, icon: Icons.swap_horiz)],
          )
        else if (defaultUid != null) ...[
          _InfoItem('Transporter', '$defaultName ($defaultType)'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onReassign,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Reassign Transporter'),
            ),
          ),
        ]
        else
          Text(
            'No transporter yet. Use Assign Transporter below.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
        if (!resolvingDestination && (!hasUsableDestination || defaultUid == null)) ...[
          const SizedBox(height: 12),
          Text(
            !hasUsableDestination
                ? 'Set a shelter location before confirming intake.'
                : 'Assign a transporter before confirming intake.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DestinationLoadingCard extends StatelessWidget {
  const _DestinationLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Loading shelter location…',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// "Intake Destination / `<name>` / [Change Location]" or, with nothing
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
                      color: AppColors.error,
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
      if (c.quarantineStatus == 'skipped') {
        return (title: 'Quarantine', subtitle: 'Skipped');
      }
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
              style: AppButtons.dangerOutline,
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
            style: AppButtons.outline,
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

  String _fmtDate(DateTime d) => formatDate(d);
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
              style: AppButtons.primary,
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
            style: AppButtons.primary,
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

