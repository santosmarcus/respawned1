import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/features/admin/animals/animal_records_flow_page.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transporter_details_card.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';

typedef ShelterDestination = ({String name, String? address, String? placeId, double? lat, double? lng});

class IntakeDetailPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const IntakeDetailPage({super.key, required this.caseId, required this.data});

  @override
  ConsumerState<IntakeDetailPage> createState() => _IntakeDetailPageState();
}

class _IntakeDetailPageState extends ConsumerState<IntakeDetailPage> {
  bool _isConfirmingIntake = false;
  bool _isStartingQuarantine = false;
  bool _isEndingQuarantine = false;
  bool _isSkippingQuarantine = false;
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

  /// Resolves the org's saved shelter location as the Intake destination —
  /// no hardcoded fallback: if the organization hasn't configured a shelter
  /// location yet (and has no legacy `location` field either), the
  /// destination stays null and the UI prompts "Set Shelter Location"
  /// instead of silently defaulting to a placeholder address.
  Future<void> _resolveDestination() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    ShelterDestination? resolved;
    String? orgId;
    if (uid != null) {
      final membership = await OrgMembershipService().getMembership(uid);
      orgId = membership?.organizationId;
      resolved = await ref.read(organizationDirectoryRepositoryProvider).resolveShelterLocation(orgId);
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
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No organization is linked to this account yet.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ShelterLocationPickerPage(organizationId: orgId)),
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
      await ref.read(rescueCaseRepositoryProvider).checkAndCompleteQuarantineIfDue(c);
    }
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
    if (destination == null || destination.lat == null || destination.lng == null) return;
    if (transporterUid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Intake', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow('Intake Destination', destination.name),
            _ConfirmRow('Transporter', '$transporterName ($transporterType)'),
            _ConfirmRow('Clinic Pickup Location', c.vetClinicName ?? 'Not on file'),
            _ConfirmRow('Case ID', '#${c.shortCaseId}'),
            _ConfirmRow('Species Summary', c.speciesSummary),
            _ConfirmRow(
                'Discharge Date',
                c.dischargedAt != null
                    ? '${_monthName(c.dischargedAt!.month)} ${c.dischargedAt!.day}, ${c.dischargedAt!.year}'
                    : 'Not on file'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('Confirm', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isConfirmingIntake = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).confirmIntake(
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
          SnackBar(content: Text('Could not confirm intake: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _startQuarantine() async {
    final days = int.tryParse(_quarantineDaysController.text.trim());
    if (days == null || days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a quarantine duration in days.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _isStartingQuarantine = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).startQuarantine(caseId: widget.caseId, durationDays: days);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start quarantine: $e'), backgroundColor: Colors.redAccent),
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
      message: 'This marks quarantine complete right now, ahead of its scheduled end.',
      confirmLabel: 'End Quarantine',
    );
    if (!confirmed) return;
    setState(() => _isEndingQuarantine = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).endQuarantine(caseId: widget.caseId, reason: 'Manually ended early.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end quarantine: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isEndingQuarantine = false);
    }
  }

  Future<void> _skipQuarantine() async {
    setState(() => _isSkippingQuarantine = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).skipQuarantine(caseId: widget.caseId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not skip quarantine: $e'), backgroundColor: Colors.redAccent),
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkQuarantineAutoComplete(c));

    final latestAssignment = ref.watch(currentAssignmentProvider(widget.caseId)).asData?.value;

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

    final completedIndexes = ref.watch(completedAnimalRecordIndexesProvider(widget.caseId)).asData?.value ?? <int>{};
    final totalAnimals = c.animalCount;

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
        title: Text('Intake Details', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — same hierarchy as Treatment Details / Rescue Reports.
            Text('#${c.shortCaseId}', style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(c.speciesSummary,
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if ((c.vetClinicName ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(c.vetClinicName!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 2),
            Text('Discharged $dischargeDateStr', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),

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

              _SectionHeader('Transporter'),
              if (latestAssignment != null && latestAssignment.status == TransportAssignmentStatus.accepted)
                TransporterDetailsCard(assignment: latestAssignment)
              else if (latestAssignment != null && latestAssignment.status == TransportAssignmentStatus.completed)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${latestAssignment.riderName} — transport complete.',
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )
              else
                Text('No transporter on this leg yet.',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssignRiderPage(
                      caseId: widget.caseId,
                      data: c.raw,
                      postAcceptTrackingMode: TrackingMode.intakeTransfer,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Reassign Transporter', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 16),
              _SectionHeader('Clinic-to-Shelter Transport'),
              if (c.intakeReceivedAt != null)
                Text('Animal received at the shelter.',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.greenrspwn))
              else
                Text('Transport in progress.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
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
                label: Text('View Transport Tracking', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
                onToggleExpand: () => setState(() => _quarantineExpanded = !_quarantineExpanded),
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

  bool get _hasUsableDestination => destination != null && destination!.lat != null && destination!.lng != null;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _hasUsableDestination && defaultUid != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Confirm Intake'),
        _DestinationCard(destination: destination, onChangeShelter: onChangeShelter),
        const SizedBox(height: 16),
        _InfoItem('Selected Transporter', defaultUid != null ? '$defaultName ($defaultType)' : 'None selected'),
        _InfoItem('Clinic Pickup Location', rescueCase.vetClinicName ?? 'Not on file'),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onReassign,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.textPrimary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text('Reassign Transporter', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 20),
        if (!canConfirm) ...[
          Text(
            !_hasUsableDestination
                ? 'Set a shelter location before confirming intake.'
                : 'Select a transporter before confirming intake.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isConfirming
                ? null
                : (!_hasUsableDestination ? onChangeShelter : (canConfirm ? onConfirm : null)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              disabledBackgroundColor: AppColors.slaterspwn,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: isConfirming
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                : Text(
                    !_hasUsableDestination ? 'Set Shelter Location' : 'Confirm Intake',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
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

  const _DestinationCard({required this.destination, required this.onChangeShelter});

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
          Icon(Icons.home_work_outlined, color: hasCoords ? AppColors.textPrimary : AppColors.textSecondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Intake Destination',
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  d == null ? 'No shelter location configured.' : d.name,
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                if (d != null && (d.address ?? '').isNotEmpty)
                  Text(d.address!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                if (d != null && !hasCoords)
                  Text('No coordinates on file — set an exact location.',
                      style: GoogleFonts.zain(fontSize: 11, color: Colors.redAccent)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onChangeShelter,
            child: Text(d == null ? 'Set Shelter Location' : 'Change Location',
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
      return (title: 'Quarantine', subtitle: end != null ? 'Active · Ends ${_fmtDate(end)}' : 'Active');
    }
    if (c.hasQuarantineDecision) {
      if (c.quarantineStatus == 'skipped') return (title: 'Quarantine', subtitle: 'Skipped');
      final end = c.quarantineEndedAt;
      return (title: 'Quarantine', subtitle: end != null ? 'Completed ${_fmtDate(end)}' : 'Completed');
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
                      Text(summary.title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(summary.subtitle, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textPrimary),
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
          if (c.quarantineStartedAt != null) _InfoItem('Started', _fmtDate(c.quarantineStartedAt!)),
          if (c.quarantineDurationDays != null) _InfoItem('Duration', '${c.quarantineDurationDays} days'),
          if (c.quarantineScheduledEndAt != null) _InfoItem('Scheduled End', _fmtDate(c.quarantineScheduledEndAt!)),
          if (remaining != null) _InfoItem('Remaining', '${remaining.inDays} day(s)'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isEnding ? null : onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE05353),
                side: const BorderSide(color: Color(0xFFE05353)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: isEnding
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('End Quarantine', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );
    }

    if (c.hasQuarantineDecision) {
      final label = c.quarantineStatus == 'skipped'
          ? 'Quarantine was skipped for this case.'
          : 'Quarantine completed'
              '${c.quarantineEndedAt != null ? ' on ${_fmtDate(c.quarantineEndedAt!)}' : ''}.';
      return Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
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
                  labelStyle: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 6),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                  focusedBorder:
                      const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
                ),
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
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
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: isStarting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Start Quarantine', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: isSkipping ? null : onSkip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.slaterspwn),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: isSkipping
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Skip', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) => '${_monthName(d.month)} ${d.day}, ${d.year}';
}

class _AnimalRecordsSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final int totalAnimals;
  final int completedCount;

  const _AnimalRecordsSection({
    required this.caseId,
    required this.data,
    required this.totalAnimals,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    final allDone = completedCount >= totalAnimals;
    final label = allDone
        ? '$completedCount of $totalAnimals records created'
        : '$completedCount of $totalAnimals records created';
    final buttonLabel = allDone ? 'View Animal Records' : (completedCount == 0 ? 'Create Animal Records' : 'Continue Animal Records');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Animal Records'),
        Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AnimalRecordsFlowPage(caseId: caseId, caseData: data)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(buttonLabel, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
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
      child: Text(text, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
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
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
          Text(label, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

String _monthName(int month) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][month - 1];
