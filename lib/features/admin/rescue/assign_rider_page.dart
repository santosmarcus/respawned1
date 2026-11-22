import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/core/utils/current_org_kind.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/rescue_case/transport_assignment_rules.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';
import 'package:respawnd1/core/utils/transporter_ranking.dart';
import 'package:respawnd1/core/utils/transport_suitability.dart';
import 'package:respawnd1/core/utils/species_summary.dart' as species_summary_util;
import 'package:respawnd1/core/widgets/rescue_risk_banner.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';

// ---- Demo transporters ---------------------------------------------------
// Two fixed, clearly-marked (isDemo: true) test transporters so the whole
// offer/accept/reject lifecycle can be exercised without a real
// pet-transporter account. Not read from Firestore `users` at all — their
// uids never collide with real accounts. Remove this block (and its uses
// below) once real transporter accounts are available for testing instead.
// TODO: internal identifiers here (riderId/riderName/etc., inherited from
// the repository's existing parameter names) are left as-is for now —
// only user-facing text says "Transporter". Migrate rider* -> transporter*
// internally in a later pass if/when it's worth the churn.
const _demoAcceptingRiderUid = 'demo-rider-a';
const _demoAcceptingRiderName = 'Demo Transporter A (Auto-Accept)';
const _demoAcceptingRiderVehicle = 'Yamaha NMAX';
const _demoAcceptingRiderPlate = 'DEMO-001';

const _demoRejectingRiderUid = 'demo-rider-b';
const _demoRejectingRiderName = 'Demo Transporter B (Auto-Reject)';
const _demoRejectingRiderVehicle = 'Honda Click';
const _demoRejectingRiderPlate = 'DEMO-002';
const _demoRejectionReason = 'Already handling another rescue and cannot accept this case';

/// Schedules the demo auto-accept/auto-reject response, detached from any
/// widget's lifecycle (fire-and-forget, plain `RescueCaseRepository`/
/// `FirebaseFirestore` calls, no `ref`/`context`). This is deliberate: if
/// the admin navigates away or backgrounds the app before the delay
/// elapses, the response must still land — a State-scoped Timer would be
/// cancelled by `dispose()` and silently never fire (see spec edge case
/// "demo timer completes while screen not visible"). Re-reads the
/// assignment doc fresh right before acting and no-ops if it's no longer
/// pending, so this can never double-resolve an already-answered offer.
void _scheduleDemoResponse({
  required String caseId,
  required String assignmentId,
  required String riderId,
}) {
  final delay = Duration(seconds: 3 + math.Random().nextInt(3)); // 3-5s
  Future.delayed(delay, () async {
    try {
      final freshDoc = await FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('transportAssignments')
          .doc(assignmentId)
          .get();
      if (!freshDoc.exists || freshDoc.data()?['status'] != 'pending') return;

      final repo = RescueCaseRepository();
      if (riderId == _demoAcceptingRiderUid) {
        await repo.acceptAssignment(
          caseId: caseId,
          assignmentId: assignmentId,
          riderId: riderId,
          riderName: _demoAcceptingRiderName,
          riderVehicle: _demoAcceptingRiderVehicle,
          riderPlate: _demoAcceptingRiderPlate,
        );
      } else if (riderId == _demoRejectingRiderUid) {
        await repo.rejectAssignment(
          caseId: caseId,
          assignmentId: assignmentId,
          reason: _demoRejectionReason,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AssignRiderPage: demo response failed: $e');
    }
  });
}

enum _RiderAvailability { available, pending, busy }

enum _FallbackChoice { retry, chooseAnother, refer, selfTransport, keepWaiting }

class _RiderVm {
  final String uid;
  final String name;
  final String type;
  // Null (with distanceKm) when the transporter hasn't shared a location.
  final LatLng? position;
  final String vehicle;
  final String plate;
  final String? photoUrl;
  final String? phone;
  final bool isDemo;
  final _RiderAvailability availability;
  final double? distanceKm;
  final VehicleCategory vehicleCategory;
  final int compatibilityScore;
  final bool isPreferred;

  /// Whether the vehicle can carry this trip's animals, and why
  /// (transport_suitability.dart). Unsuitable transporters are listed but
  /// never selectable.
  final VehicleSuitability suitability;

  bool get isSelectable => availability == _RiderAvailability.available && suitability.suitable;

  const _RiderVm({
    required this.uid,
    required this.name,
    required this.type,
    required this.position,
    required this.vehicle,
    required this.plate,
    required this.photoUrl,
    required this.isDemo,
    required this.availability,
    required this.distanceKm,
    required this.vehicleCategory,
    required this.compatibilityScore,
    required this.suitability,
    this.phone,
    this.isPreferred = false,
  });

  _RiderVm copyWith({bool? isPreferred}) => _RiderVm(
    uid: uid,
    name: name,
    type: type,
    position: position,
    vehicle: vehicle,
    plate: plate,
    photoUrl: photoUrl,
    phone: phone,
    isDemo: isDemo,
    availability: availability,
    distanceKm: distanceKm,
    vehicleCategory: vehicleCategory,
    compatibilityScore: compatibilityScore,
    suitability: suitability,
    isPreferred: isPreferred ?? this.isPreferred,
  );

  String get distanceLabel =>
      distanceKm == null ? 'Location not shared' : '${distanceKm!.toStringAsFixed(1)} km away';
}

class AssignRiderPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  /// Which Track Case mode to open once a transporter accepts. Defaults to
  /// the original rescue-pickup tracking (every existing call site keeps
  /// working unchanged); Intake Details' "Reassign Transporter" passes
  /// [TrackingMode.intakeTransfer] instead, so accepting a replacement
  /// transporter mid-intake lands on the clinic-to-shelter tracking view
  /// rather than the rescue-pickup one. Purely additive — this is still
  /// the one Assign Transporter interface, not a separate intake picker.
  final TrackingMode postAcceptTrackingMode;
  const AssignRiderPage({
    super.key,
    required this.caseId,
    required this.data,
    this.postAcceptTrackingMode = TrackingMode.rescuePickup,
  });

  @override
  ConsumerState<AssignRiderPage> createState() => _AssignRiderPageState();
}

class _AssignRiderPageState extends ConsumerState<AssignRiderPage> {
  /// Transporter tapped/chosen but not yet written to Firestore —
  /// selection is purely local state until "Next" is confirmed.
  String? _selectedRiderUid;

  /// True only while the confirmed assignment is being saved, to guard
  /// against duplicate taps on "Send offer".
  bool _isAssigning = false;

  /// High-risk cases: the bite/escape risk is acknowledged with a checkbox
  /// on this page rather than a separate popup before the offer goes out.
  bool _riskAcknowledged = false;

  bool _savingClinic = false;

  // ---- The offer this page sent ------------------------------------------
  //
  // One place for the whole offer: the inline panel below the map shows it
  // while it is pending (with a live timer, Cancel offer and Send to
  // another transporter), a declined or expired offer gets Retry and Choose
  // another transporter, and an acceptance goes on to tracking by itself.
  // (There used to be a popup showing the same thing on top of this panel.)

  /// The offer sent from this page, so its acceptance opens tracking.
  String? _sentAssignmentId;
  bool _openedTracking = false;

  /// A declined/expired offer the admin dismissed with Choose another.
  String? _dismissedOutcomeId;

  /// Ticks the pending panel's elapsed/expiry labels once a second.
  Timer? _ticker;

  /// The account belongs to an independent rescuer, who may bring the
  /// animal to the clinic themselves at any point (shelters only once no
  /// transporter can be found).
  bool _isIndependent = false;

  @override
  void initState() {
    super.initState();
    _loadOrgKind();
  }

  Future<void> _loadOrgKind() async {
    final independent = await currentOrgIsIndependent();
    if (mounted && independent) setState(() => _isIndependent = true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool pending) {
    if (pending && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!pending && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  GoogleMapController? _mapController;
  bool _hasFitCamera = false;

  // Progressive Search Radius spec — no organization-settings model exists
  // yet to source a real configured starting/max radius from (see
  // organization_model.dart, which has no settings sub-object at all), so
  // these are the documented defaults to migrate to org config later.
  static const List<double> _radiusStepsKm = [3, 5, 10, 20];
  double _currentRadiusKm = _radiusStepsKm.first;
  double get _maxRadiusKm => _radiusStepsKm.last;
  bool _autoExpanding = false;

  void _expandRadius() {
    final next = _radiusStepsKm.firstWhere((r) => r > _currentRadiusKm, orElse: () => _maxRadiusKm);
    if (next == _currentRadiusKm) return;
    setState(() => _currentRadiusKm = next);
  }

  void _resetRadius() => setState(() => _currentRadiusKm = _radiusStepsKm.first);

  // ---- No transporter available ------------------------------------------
  //
  // Shown once the search radius is at its maximum with nobody available,
  // or after kNoTransporterAttemptLimit declined/expired offers
  // (shouldOfferNoTransporterFallback). "Keep waiting" hides it until
  // another offer fails.

  /// Failed-offer count at the moment staff chose "Keep waiting"; null
  /// while the prompt hasn't been dismissed.
  int? _fallbackDismissedAtCount;
  bool _fallbackBusy = false;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  Future<void> _referFromFallback() async {
    final rescueCase = ref.read(caseDetailProvider(widget.caseId)).asData?.value;
    if (rescueCase == null) return;
    final sent = await showReferCaseSheet(
      context,
      rescueCase: rescueCase,
      caseRepository: ref.read(rescueCaseRepositoryProvider),
      organizationDirectory: ref.read(organizationDirectoryRepositoryProvider),
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Referral sent. The case is now Referred.'));
    Navigator.pop(context);
  }

  Future<void> _organizationWillTransport() async {
    final toShelter = _currentCaseData()['transportDestination'] == 'shelter';
    final place = toShelter ? 'your shelter' : 'the selected clinic';
    final next = toShelter ? 'start intake' : 'start treatment';
    final confirmed = await showConfirmActionDialog(
      context,
      title: _isIndependent ? 'Bring it yourself?' : 'Organization will transport?',
      message: _isIndependent
          ? 'You or someone on your team brings the animal to $place, without a transporter. '
              'The case moves to Ongoing; confirm arrival on Rescue Details to $next. '
              "If the trip can't be finished, switch to a transporter from Rescue Details."
          : 'Your organization will bring the animal to $place itself, without a transporter. '
              'The case moves to Ongoing; confirm arrival on Rescue Details to $next.',
      confirmLabel: _isIndependent ? "I'll Bring It" : 'We Will Transport',
      cancelLabel: 'Back',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _fallbackBusy = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).startOrganizationTransport(
        caseId: widget.caseId,
        actorUid: _actorUid,
        actorName: _actorName,
        byChoice: _isIndependent,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(_isIndependent
            ? 'Recorded: your team is bringing this animal to ${toShelter ? 'the shelter' : 'the clinic'}.'
            : 'Recorded: your organization is transporting this animal.'),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(e is ActiveAssignmentConflictException ? e.userMessage : 'Could not record this: $e',
              kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _fallbackBusy = false);
    }
  }

  String _fallbackReason(int failedOffers) => failedOffers >= kNoTransporterAttemptLimit
      ? '$failedOffers transporter offers for this case were declined or expired.'
      : 'Nobody is available within ${_maxRadiusKm.toStringAsFixed(0)} km.';

  /// True while the no-transporter sheet is on screen, so build() doesn't
  /// stack a second one.
  bool _fallbackSheetOpen = false;

  /// Latest transporter list, for Retry from the sheet.
  List<_RiderVm> _latestRiders = const [];

  /// The no-transporter options as a bottom sheet, so they aren't squeezed
  /// between the map and the transporter list. Opens by itself when the
  /// fallback applies (again on every visit to this page, and again when
  /// another offer fails); the banner reopens it after Keep Waiting.
  Future<void> _openFallbackSheet({
    required int failedOffers,
    required bool isCritical,
    required TransportAssignment? failedOffer,
  }) async {
    if (_fallbackSheetOpen || !mounted) return;
    _fallbackSheetOpen = true;
    final tone = isCritical ? AppColors.error : AppColors.warning;
    final declined = failedOffer?.status == TransportAssignmentStatus.rejected;
    final choice = await showModalBottomSheet<_FallbackChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.warning_amber_rounded, color: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('No transporter yet',
                      style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('${_fallbackReason(failedOffers)} Choose how to move this case forward.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              if (failedOffer != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    [
                      declined ? 'Last offer: ${failedOffer.riderName} declined' : 'Last offer to ${failedOffer.riderName} expired',
                      if (declined && (failedOffer.rejectionReason ?? '').isNotEmpty) failedOffer.rejectionReason!,
                    ].join('\n'),
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _sheetLabel('Try a transporter again'),
              if (failedOffer != null) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, _FallbackChoice.retry),
                  style: AppButtons.outline,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('Retry ${failedOffer.riderName}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, _FallbackChoice.chooseAnother),
                style: AppButtons.outline,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text('Choose Another Transporter', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              _sheetLabel('Or move the case another way'),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, _FallbackChoice.refer),
                style: AppButtons.primary,
                icon: const Icon(Icons.forward_outlined, size: 18),
                label: Text('Refer Case', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, _FallbackChoice.selfTransport),
                style: AppButtons.outline,
                icon: const Icon(Icons.directions_car_outlined, size: 18),
                label: Text(_isIndependent ? "I'll Bring It Myself" : 'Organization Will Transport',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _FallbackChoice.keepWaiting),
                child: Text('Keep Waiting for a Transporter',
                    style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
    _fallbackSheetOpen = false;
    if (!mounted) return;
    // Any close (including a swipe down) counts as Keep Waiting: it comes
    // back when another offer fails, on the next visit, or from the banner.
    setState(() => _fallbackDismissedAtCount = failedOffers);
    switch (choice) {
      case _FallbackChoice.retry:
        if (failedOffer != null) await _retryRider(failedOffer, _latestRiders);
      case _FallbackChoice.chooseAnother:
        if (failedOffer != null) setState(() => _dismissedOutcomeId = failedOffer.id);
      case _FallbackChoice.refer:
        await _referFromFallback();
      case _FallbackChoice.selfTransport:
        await _organizationWillTransport();
      case _FallbackChoice.keepWaiting:
      case null:
        break;
    }
  }

  Widget _sheetLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.zain(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary)),
      );

  /// One line in place of the old inline prompt; reopens the sheet.
  Widget _fallbackBanner({
    required int failedOffers,
    required bool isCritical,
    required TransportAssignment? failedOffer,
  }) {
    final tone = isCritical ? AppColors.error : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: tone.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: tone)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _fallbackBusy
              ? null
              : () => _openFallbackSheet(failedOffers: failedOffers, isCritical: isCritical, failedOffer: failedOffer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: tone, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failedOffers >= kNoTransporterAttemptLimit
                        ? 'No transporter yet · $failedOffers offers declined or expired'
                        : 'No transporter available nearby',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                _fallbackBusy
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Text('Options',
                        style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const Icon(Icons.chevron_right, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Guards reconcileStaleOffer against being fired again on every rebuild
  /// while its own write is still in flight (the write itself is already
  /// idempotent — this just avoids redundant calls).
  final Set<String> _reconcilingAssignmentIds = {};
  bool _cancellingOffer = false;

  /// Shown as the pending offer while [_sendOffer] is still saving it
  /// (id empty until the server answers).
  TransportAssignment? _optimisticOffer;

  /// An offer being cancelled: hidden at once instead of after the server.
  String? _optimisticCancelledId;

  void _reconcileIfStale(TransportAssignment assignment) {
    if (!assignment.isStalePending) return;
    if (_reconcilingAssignmentIds.contains(assignment.id)) return;
    _reconcilingAssignmentIds.add(assignment.id);
    ref.read(rescueCaseRepositoryProvider).reconcileStaleOffer(
      caseId: widget.caseId,
      assignmentId: assignment.id,
    );
  }

  /// Cancels the pending offer. [toAnother]: the admin wants to pick a
  /// different transporter, so no confirmation and the list comes back
  /// with nothing selected.
  Future<void> _cancelExistingOffer(TransportAssignment assignment, {bool toAnother = false}) async {
    if (!toAnother) {
      final confirmed = await showConfirmActionDialog(context,
          title: 'Cancel this offer?',
          message: 'The pending offer to ${assignment.riderName} will be cancelled.',
          confirmLabel: 'Cancel Offer',
          cancelLabel: 'Keep Waiting',
          destructive: true);
      if (confirmed != true || !mounted) return;
    }
    // Back to the transporter list at once; the cancel is a server
    // transaction and is undone here if it fails.
    setState(() {
      _cancellingOffer = true;
      _optimisticOffer = null;
      _optimisticCancelledId = assignment.id;
      _dismissedOutcomeId = assignment.id;
      _selectedRiderUid = null;
    });
    if (toAnother) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Offer cancelled. Choose another transporter.'));
    }
    try {
      await ref.read(rescueCaseRepositoryProvider).cancelAssignment(
        caseId: widget.caseId,
        assignmentId: assignment.id,
        reason: toAnother ? 'Sent to another transporter' : 'Cancelled by organization while waiting',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticCancelledId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not cancel this offer: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingOffer = false);
    }
  }

  /// The pending offer, shown in place of the rider list (an admin can't
  /// pick a second transporter while one is outstanding). Updates every
  /// second; the transporter's answer arrives live.
  Widget _pendingOfferPanel(TransportAssignment assignment) {
    final offeredAt = assignment.offeredAt;
    String pendingFor = '';
    if (offeredAt != null) {
      final d = DateTime.now().difference(offeredAt);
      pendingFor = d.inMinutes < 1 ? 'Waiting ${d.inSeconds}s' : 'Waiting ${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    final expiry = assignment.expiryLabel();
    // Part of the page's single scroll (no Expanded), so it can never
    // overflow under the banners above it.
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.yellowrspwn, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.greenrspwn),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Waiting for ${assignment.riderName}',
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                        Text(
                          [pendingFor, expiry].where((t) => t.isNotEmpty).join(' · '),
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                // Disabled for the moment the offer is still being saved.
                onPressed: _cancellingOffer || assignment.id.isEmpty
                    ? null
                    : () => _cancelExistingOffer(assignment, toAnother: true),
                style: AppButtons.primary,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text('Send to Another Transporter', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _cancellingOffer || assignment.id.isEmpty ? null : () => _cancelExistingOffer(assignment),
                style: AppButtons.dangerOutline,
                child: _cancellingOffer
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Cancel Offer', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
  }

  /// A declined or expired offer: why, then Retry that transporter or
  /// choose another.
  Widget _failedOfferCard(TransportAssignment a, List<_RiderVm> riders) {
    final declined = a.status == TransportAssignmentStatus.rejected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(declined ? '${a.riderName} declined' : 'Offer to ${a.riderName} expired',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            if (declined && (a.rejectionReason ?? '').isNotEmpty)
              Text(a.rejectionReason!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            // Short labels: the header already names the transporter, and
            // a name inside a half-width button got squeezed.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isAssigning ? null : () => _retryRider(a, riders),
                    style: AppButtons.outline.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 10))),
                    child: Text('Retry', maxLines: 1, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _dismissedOutcomeId = a.id),
                    style: AppButtons.primary.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 10))),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Choose another', maxLines: 1, style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LatLng? _caseLocationFrom(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// A transporter's most-recent assignment being `rejected` is bucketed as
  /// Busy here too, not Available — a transporter who just declined an
  /// offer shouldn't loop straight back into the selectable pool. Only
  /// `completed`/`cancelled` (or no assignment at all) reads as Available.
  _RiderAvailability _availabilityFor(String uid, Map<String, TransportAssignmentStatus> activeByRider) {
    final status = activeByRider[uid];
    if (status == TransportAssignmentStatus.accepted || status == TransportAssignmentStatus.rejected) {
      return _RiderAvailability.busy;
    }
    if (status == TransportAssignmentStatus.pending) return _RiderAvailability.pending;
    return _RiderAvailability.available;
  }

  LatLng _positionFor(LatLng center, String uid) {
    final offset = deterministicDemoOffset(center.latitude, center.longitude, uid);
    return LatLng(offset.lat, offset.lng);
  }

  /// Order: demo transporters while Available, then real transporters
  /// grouped Available -> Pending -> Busy (a demo transporter that goes
  /// Pending/Busy — e.g. right after declining — joins those same groups
  /// instead of staying pinned to the top). Each group sorted by distance.
  /// Pending/busy transporters are never hidden — only OFFLINE real
  /// transporters are (spec: only online + available transporters are
  /// assignable; pending/busy real transporters are still online, just not
  /// selectable right now). Demo transporters are dev-only and never shown
  /// outside kDebugMode, regardless of any online concept (they don't have
  /// real presence data at all).
  List<_RiderVm> _buildRiderVms(
      LatLng center,
      LatLng? caseLocation,
      List<PetTransporter> transporters,
      Map<String, TransportAssignmentStatus> activeByRider,
      AnimalTransportProfile animalProfile, {
      required int tripAnimals,
      }) {
    // Unverified transporters can't take transits (firestore.rules
    // isVerifiedResponder), so they are never offered one.
    // Phone and location are required too: staff call the transporter
    // about the pickup, and distance/radius need where they are.
    final onlineTransporters = transporters
        .where((t) =>
            t.isOnline &&
            t.isVerified &&
            (t.phone ?? '').trim().isNotEmpty &&
            t.lastLat != null &&
            t.lastLng != null)
        .toList();
    double distanceFor(LatLng pos) =>
        haversineDistanceKm(center.latitude, center.longitude, pos.latitude, pos.longitude);

    _RiderVm demoRider({
      required String uid,
      required String name,
      required String vehicle,
      required String plate,
    }) {
      final pos = _positionFor(center, uid);
      final category = classifyVehicle(vehicle);
      return _RiderVm(
        uid: uid,
        name: name,
        type: 'Pet Transporter',
        position: pos,
        vehicle: vehicle,
        plate: plate,
        photoUrl: null,
        isDemo: true,
        availability: _availabilityFor(uid, activeByRider),
        distanceKm: distanceFor(pos),
        vehicleCategory: category,
        compatibilityScore: vehicleCompatibilityScore(category, animalProfile),
        suitability: vehicleSuitability(
          vehicleType: vehicle,
          declaredCapacity: null,
          animals: tripAnimals,
        ),
      );
    }

    // Demo transporters have no real presence data at all — never shown
    // outside a debug build, regardless of any online concept.
    final demoA = kDebugMode
        ? demoRider(
      uid: _demoAcceptingRiderUid,
      name: _demoAcceptingRiderName,
      vehicle: _demoAcceptingRiderVehicle,
      plate: _demoAcceptingRiderPlate,
    )
        : null;
    final demoB = kDebugMode
        ? demoRider(
      uid: _demoRejectingRiderUid,
      name: _demoRejectingRiderName,
      vehicle: _demoRejectingRiderVehicle,
      plate: _demoRejectingRiderPlate,
    )
        : null;

    // Real transporters are placed only where they actually are (the
    // lastLat/lastLng they shared on going online) — never at a made-up
    // offset. Distance also needs the case's own coordinates; without
    // either, it's shown as unknown rather than estimated.
    final realRiders = onlineTransporters.map((t) {
      final pos = (t.lastLat != null && t.lastLng != null) ? LatLng(t.lastLat!, t.lastLng!) : null;
      final category = classifyVehicle(t.vehicleType);
      return _RiderVm(
        uid: t.uid,
        name: t.name,
        type: 'Pet Transporter',
        position: pos,
        vehicle: t.vehicleType ?? 'Not provided',
        plate: t.licensePlate ?? 'Not provided',
        photoUrl: t.photoUrl,
        phone: t.phone,
        isDemo: false,
        availability: _availabilityFor(t.uid, activeByRider),
        distanceKm: (pos == null || caseLocation == null) ? null : distanceFor(pos),
        vehicleCategory: category,
        compatibilityScore: vehicleCompatibilityScore(category, animalProfile),
        suitability: vehicleSuitability(
          vehicleType: t.vehicleType,
          declaredCapacity: t.maxAnimals,
          animals: tripAnimals,
        ),
      );
    }).toList();

    // Unknown distances sort after every known one.
    int byDistance(_RiderVm a, _RiderVm b) {
      final da = a.distanceKm, db = b.distanceKm;
      if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
      return da.compareTo(db);
    }
    // Transporter Ranking spec — within the Available bucket, the best
    // vehicle/capacity match ranks first; distance only breaks ties within
    // the same compatibility score, never overriding it (a compatible
    // transporter farther away still outranks an incompatible closer one).
    int byCompatibilityThenDistance(_RiderVm a, _RiderVm b) {
      final byScore = b.compatibilityScore.compareTo(a.compatibilityScore);
      return byScore != 0 ? byScore : byDistance(a, b);
    }

    // Demo transporters are only pinned above the real-available group
    // while they themselves are Available. The moment one goes Pending or
    // Busy (e.g. right after declining), it drops into the same
    // distance-sorted Pending/Busy bucket as everyone else instead of
    // staying artificially glued to the top — that's what actually moves
    // a just-declined transporter down and out of easy re-selection.
    final demoRiders = [?demoA, ?demoB];
    final allRiders = [...demoRiders, ...realRiders];

    final demoAvailable = demoRiders.where((r) => r.availability == _RiderAvailability.available).toList()
    ..sort(byDistance);
    // Vehicle suitability first (transport_suitability.dart): available
    // transporters whose vehicle can carry this trip, ranked; then the
    // available ones whose vehicle can't, listed with the reason but not
    // selectable. Preferred only ever goes to a suitable transporter.
    var available = realRiders
        .where((r) => r.availability == _RiderAvailability.available && r.suitability.suitable)
        .toList()
    ..sort(byCompatibilityThenDistance);
    if (available.isNotEmpty) {
    available = [available.first.copyWith(isPreferred: true), ...available.skip(1)];
    }
    final availableUnsuitable = realRiders
        .where((r) => r.availability == _RiderAvailability.available && !r.suitability.suitable)
        .toList()
    ..sort(byDistance);
    final pending = allRiders.where((r) => r.availability == _RiderAvailability.pending).toList()
    ..sort(byDistance);
    final busy = allRiders.where((r) => r.availability == _RiderAvailability.busy).toList()
    ..sort(byDistance);

    return [...demoAvailable, ...available, ...availableUnsuitable, ...pending, ...busy];
  }

  void _selectRider(_RiderVm rider) {
    if (rider.availability != _RiderAvailability.available || _isAssigning) return;
    if (!rider.suitability.suitable) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar("${rider.name}'s vehicle isn't suitable for this trip: ${rider.suitability.reason}."),
      );
      return;
    }
    setState(() {
      // Tapping the already-selected transporter deselects it; tapping a
      // different available transporter replaces the selection — only one
      // at a time either way.
      _selectedRiderUid = _selectedRiderUid == rider.uid ? null : rider.uid;
    });
  }

  /// Picks (or changes) the case's clinic without leaving this page: the
  /// clinic and the transporter are chosen together here, then one
  /// "Send offer" starts the trip.
  Future<void> _pickClinic(Map<String, dynamic> d) async {
    if (_savingClinic) return;
    final c = ref.read(caseDetailProvider(widget.caseId)).asData?.value;
    final currentName = (d['vetClinicName'] as String?)?.trim();
    final hasClinic = currentName != null && currentName.isNotEmpty;
    setState(() => _savingClinic = true);
    try {
      final outcome = await showSelectClinicSheet(
        context,
        repository: ref.read(clinicSearchRepositoryProvider),
        caseRepository: ref.read(rescueCaseRepositoryProvider),
        savedClinicsRepository: ref.read(savedClinicsRepositoryProvider),
        caseId: widget.caseId,
        actorUid: _actorUid,
        actorName: _actorName,
        centerLat: c?.lat ?? (d['lat'] as num?)?.toDouble(),
        centerLng: c?.lng ?? (d['lng'] as num?)?.toDouble(),
        currentClinicName: currentName,
        currentClinicAddress: d['vetClinicAddress'] as String?,
        currentClinicPlaceId: d['vetClinicPlaceId'] as String?,
        currentClinicLat: (d['vetClinicLat'] as num?)?.toDouble(),
        currentClinicLng: (d['vetClinicLng'] as num?)?.toDouble(),
        currentClinicPhone: d['vetClinicPhone'] as String?,
        offerAssignRider: false,
        previousClinicName: hasClinic ? currentName : null,
      );
      if (!mounted) return;
      if (outcome.result == ClinicSheetResult.clinicSaved) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Clinic set: ${outcome.clinic?.name ?? ''}'));
      }
    } finally {
      if (mounted) setState(() => _savingClinic = false);
    }
  }

  /// Direct to shelter applies only to organizations with a shelter —
  /// independent rescuers have none (statusAfterTreatmentAccepted).
  bool _canGoToShelter(Map<String, dynamic> d) => !_isIndependent && d['ownerKind'] != 'independent';

  /// Staff chose "straight to the shelter" and the pin is on the case.
  static bool _shelterChosen(Map<String, dynamic> d) =>
      d['transportDestination'] == 'shelter' && d['shelterLat'] is num && d['shelterLng'] is num;

  /// Direct to shelter: resolves the organization's shelter pin and saves
  /// it as the destination. Without a pin, offers to set one first.
  Future<void> _chooseShelter(Map<String, dynamic> d) async {
    if (_savingClinic) return;
    final orgId = (d['organizationId'] as String?) ?? '';
    final directory = ref.read(organizationDirectoryRepositoryProvider);
    setState(() => _savingClinic = true);
    try {
      var s = await directory.resolveShelterLocation(orgId);
      if (!mounted) return;
      if (s == null || s.lat == null || s.lng == null) {
        final setNow = await showConfirmActionDialog(
          context,
          title: 'Shelter location not set',
          message: "Pin your shelter's exact location first. The transporter's arrival is checked against it.",
          confirmLabel: 'Set Shelter Location',
          cancelLabel: 'Not Now',
        );
        if (!setNow || !mounted || orgId.isEmpty) return;
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ShelterLocationPickerPage(
              organizationId: orgId,
              initialName: s?.name,
              initialAddress: s?.address,
              initialPlaceId: s?.placeId,
            ),
          ),
        );
        if (saved != true || !mounted) return;
        s = await directory.resolveShelterLocation(orgId);
        if (!mounted || s == null || s.lat == null || s.lng == null) return;
      }
      await ref.read(rescueCaseRepositoryProvider).sendToShelter(
            caseId: widget.caseId,
            shelterName: s.name,
            shelterAddress: s.address,
            shelterLat: s.lat!,
            shelterLng: s.lng!,
            actorUid: _actorUid,
            actorName: _actorName,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Destination: ${s.name} (shelter)'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not set the shelter as the destination: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _savingClinic = false);
    }
  }

  /// Clinic chosen again: keeps the clinic already saved, or opens the
  /// clinic picker when there is none.
  Future<void> _chooseClinic(Map<String, dynamic> d) async {
    if (_savingClinic) return;
    final clinicName = (d['vetClinicName'] as String?)?.trim() ?? '';
    if (clinicName.isEmpty) return _pickClinic(d);
    if (d['transportDestination'] != 'shelter') return;
    setState(() => _savingClinic = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).useClinicDestination(
            caseId: widget.caseId,
            clinicName: clinicName,
            actorUid: _actorUid,
            actorName: _actorName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not switch back to the clinic: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _savingClinic = false);
    }
  }

  /// Where the transporter takes the animal: a clinic (then on to the
  /// shelter after treatment) or straight to the organization's shelter.
  Widget _clinicCard(Map<String, dynamic> d) {
    final toShelter = d['transportDestination'] == 'shelter';
    final name = toShelter
        ? (d['shelterName'] as String?)?.trim() ?? ''
        : (d['vetClinicName'] as String?)?.trim() ?? '';
    final address = toShelter
        ? (d['shelterAddress'] as String?)?.trim() ?? ''
        : (d['vetClinicAddress'] as String?)?.trim() ?? '';
    final ready = toShelter ? _shelterChosen(d) : name.isNotEmpty;
    final showChoice = _canGoToShelter(d);
    final chipStyle = GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: ready ? Colors.white : AppColors.yellowrspwn.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ready ? AppColors.slaterspwn : AppColors.yellowrspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showChoice) ...[
            Text('Take the animal to',
                style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text('Clinic first', style: chipStyle),
                  avatar: const Icon(Icons.local_hospital_outlined, size: 16),
                  selected: !toShelter,
                  onSelected: _savingClinic ? null : (_) => _chooseClinic(d),
                ),
                ChoiceChip(
                  label: Text('Straight to shelter', style: chipStyle),
                  avatar: const Icon(Icons.home_outlined, size: 16),
                  selected: toShelter,
                  onSelected: _savingClinic ? null : (_) => _chooseShelter(d),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Icon(toShelter ? Icons.home_outlined : Icons.local_hospital_outlined, color: AppColors.textPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        toShelter
                            ? 'Shelter'
                            : name.isNotEmpty
                                ? 'Clinic'
                                : 'Choose a clinic first',
                        style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    Text(name.isNotEmpty ? name : 'Where the transporter takes the animal',
                        style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (address.isNotEmpty)
                      Text(address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    if (toShelter)
                      Text('No clinic stop: the animal goes from pickup to intake.',
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (_savingClinic)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (!toShelter)
                TextButton(
                  onPressed: () => _pickClinic(d),
                  child: Text(name.isNotEmpty ? 'Change' : 'Choose',
                      style: GoogleFonts.zain(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The live case document, not the possibly-stale snapshot passed in at
  /// construction time.
  Map<String, dynamic> _currentCaseData() =>
      ref.read(caseDetailProvider(widget.caseId)).asData?.value?.raw ?? widget.data;

  Future<void> _handleNext(List<_RiderVm> riders) async {
    final selectedUid = _selectedRiderUid;
    if (selectedUid == null || _isAssigning) return; // nothing selected / already saving

    // Re-verify availability at confirmation time — the transporter may
    // have become pending/busy on another case between selection and now.
    final rider = riders.where((r) => r.uid == selectedUid).cast<_RiderVm?>().firstWhere((r) => true, orElse: () => null);
    if (rider == null || rider.availability != _RiderAvailability.available) {
      setState(() => _selectedRiderUid = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('This transporter is no longer available. Please select another.', kind: AppMessageKind.error),
        );
      }
      return;
    }

    await _sendOffer(rider);
  }

  /// Sends the offer to [rider]; the inline panel takes it from there.
  /// [allowReassign] replaces an already-accepted transporter (Intake's
  /// Reassign Transporter), after the admin confirms.
  Future<void> _sendOffer(_RiderVm rider, {bool allowReassign = false}) async {
    if (_isAssigning) return;
    // Shown straight away; the offer is a server transaction, and waiting
    // for it plus the live update made the panel appear seconds later.
    final offeredAt = DateTime.now();
    TransportAssignment placeholder(String id) => TransportAssignment(
          id: id,
          caseId: widget.caseId,
          riderId: rider.uid,
          riderName: rider.name,
          riderType: rider.type,
          status: TransportAssignmentStatus.pending,
          offeredAt: offeredAt,
          isDemo: rider.isDemo,
          vehicle: rider.vehicle,
          plate: rider.plate,
        );
    setState(() {
      _isAssigning = true;
      _optimisticOffer = placeholder('');
    });
    try {
      final assignmentId = await ref.read(rescueCaseRepositoryProvider).createAssignmentOffer(
        caseId: widget.caseId,
        riderId: rider.uid,
        riderName: rider.name,
        riderType: rider.type,
        isDemo: rider.isDemo,
        allowReassign: allowReassign,
        vehicle: rider.vehicle,
        plate: rider.plate,
      );
      if (!mounted) return;
      if (rider.isDemo) {
        _scheduleDemoResponse(caseId: widget.caseId, assignmentId: assignmentId, riderId: rider.uid);
      }
      setState(() {
        _sentAssignmentId = assignmentId;
        _selectedRiderUid = null;
        // Now cancellable, even before the live update arrives.
        _optimisticOffer = placeholder(assignmentId);
      });
    } on ActiveAssignmentConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _isAssigning = false;
        _optimisticOffer = null;
      });
      if (e.status == TransportAssignmentStatus.accepted) {
        final replace = await showConfirmActionDialog(
          context,
          title: 'Replace ${e.riderName}?',
          message: '${e.riderName} already accepted this transport. Send the offer to ${rider.name} instead? '
              '${e.riderName} is taken off the case if ${rider.name} accepts.',
          confirmLabel: 'Send to ${rider.name}',
          cancelLabel: 'Keep ${e.riderName}',
        );
        if (replace == true && mounted) await _sendOffer(rider, allowReassign: true);
      } else {
        // A pending offer already exists: the panel below shows it.
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('${e.riderName} already has a pending offer for this case.'));
      }
      return;
    } on TransporterNoLongerOnlineException catch (e) {
      _offerRefused(e.toString());
    } on TransporterNotReachableException catch (e) {
      _offerRefused(e.toString());
    } on UnsuitableVehicleException catch (e) {
      _offerRefused(e.toString());
    } catch (e, st) {
      debugPrint('Assign transporter failed: $e\n$st');
      if (mounted) {
        setState(() => _optimisticOffer = null);
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          'Could not send the offer to ${rider.name}.',
          kind: AppMessageKind.error,
          action: SnackBarAction(label: 'Retry', onPressed: () => _sendOffer(rider, allowReassign: allowReassign)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  /// The server refused the offer for this transporter: back to the list.
  void _offerRefused(String message) {
    if (!mounted) return;
    setState(() {
      _optimisticOffer = null;
      _selectedRiderUid = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(message, kind: AppMessageKind.error));
  }

  /// Retry the same transporter after a decline or expiry. Skips the
  /// availability check on purpose: the admin chose them again.
  Future<void> _retryRider(TransportAssignment previous, List<_RiderVm> riders) async {
    final rider = riders.where((r) => r.uid == previous.riderId).firstOrNull;
    if (rider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('${previous.riderName} is not online right now. Choose another transporter.'),
      );
      setState(() => _dismissedOutcomeId = previous.id);
      return;
    }
    await _sendOffer(rider);
  }

  /// Opens tracking once the offer this page sent is accepted.
  void _openTrackingOnAccept(TransportAssignment? assignment) {
    if (_openedTracking || assignment == null) return;
    if (assignment.id != _sentAssignmentId || assignment.status != TransportAssignmentStatus.accepted) return;
    _openedTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('${assignment.riderName} accepted. Opening tracking.'));
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => AdminTrackCasePage(
              caseId: widget.caseId, data: _currentCaseData(), mode: widget.postAcceptTrackingMode)));
    });
  }

  void _fitCameraOnce(LatLng? center, List<_RiderVm> riders) {
    if (_hasFitCamera || _mapController == null || center == null) return;
    _hasFitCamera = true;
    final points = [center, ...riders.map((r) => r.position).whereType<LatLng>()];
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      48,
    ));
  }

  Set<Marker> _buildMarkers(LatLng? center, List<_RiderVm> riders) {
    return {
      if (center != null)
        Marker(
          markerId: const MarkerId('rescue_case'),
          position: center,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Rescue Case'),
        ),
      for (final rider in riders)
        if (rider.position != null)
          Marker(
            markerId: MarkerId(rider.uid),
            position: rider.position!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              rider.uid == _selectedRiderUid
                  ? BitmapDescriptor.hueGreen
                  : switch (rider.availability) {
                _RiderAvailability.pending => BitmapDescriptor.hueOrange,
                _RiderAvailability.busy => BitmapDescriptor.hueViolet,
                _RiderAvailability.available => BitmapDescriptor.hueRed,
              },
            ),
            infoWindow: InfoWindow(
              title: rider.name,
              snippet: rider.distanceLabel,
            ),
          ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read) so the header/clinic info here stay live if
    // the case changes while this page is open, not just at the moment it
    // was opened.
    final liveCase = ref.watch(caseDetailProvider(widget.caseId)).asData?.value;
    final d = liveCase?.raw ?? widget.data;
    final urgency = d['urgency'] ?? '';

    final caseLocation = _caseLocationFrom(d);
    // Riders still need a center to be positioned around even when the
    // case itself has no saved coordinates yet.
    final riderCenter = caseLocation ?? const LatLng(14.5995, 120.9842); // Manila fallback

    final transportersAsync = ref.watch(petTransportersProvider);
    final transportersLoading = !transportersAsync.hasValue && !transportersAsync.hasError;
    final transporters = transportersAsync.value ?? const <PetTransporter>[];
    final activeByRider =
        ref.watch(activeAssignmentsByRiderProvider).asData?.value ?? const <String, TransportAssignmentStatus>{};

    final animals = (d['animals'] as List?) ?? const [];
    // Ranking and suitability need only the number of passengers (animals
    // riding); no "enclosed vehicle" requirement.
    final animalProfile = AnimalTransportProfile(
      animalCount: animals.isEmpty ? 1 : animals.length,
    );
    // What the trip needs from a vehicle (transport_suitability.dart).
    final tripAnimals = animalsToTransport(d);
    final riders = _buildRiderVms(riderCenter, caseLocation, transporters, activeByRider, animalProfile,
        tripAnimals: tripAnimals);

    // Progressive Search Radius spec — only riders within the current
    // radius are actually shown/selectable; the underlying compatibility/
    // availability ordering from _buildRiderVms is preserved by filtering
    // rather than re-sorting. Riders with no known distance are always
    // listed — the radius can't rule them in or out, and hiding them would
    // hide every transporter who hasn't shared a location.
    final visibleRiders = riders.where((r) => r.distanceKm == null || r.distanceKm! <= _currentRadiusKm).toList();
    // "Available" here means available with a suitable vehicle: the search
    // keeps widening until one is in range.
    final hasAvailableInRadius = visibleRiders.any((r) => r.isSelectable);
    final hasAvailableAnywhere = riders.any((r) => r.isSelectable);
    final hasUnsuitableOnly = !hasAvailableAnywhere &&
        riders.any((r) => r.availability == _RiderAvailability.available);
    final atMaxRadius = _currentRadiusKm >= _maxRadiusKm;

    // Auto-expand one step at a time whenever nothing compatible/available
    // is in range yet but something is further out — never past the
    // configured maximum, and it stops the moment an available transporter
    // is found in range. Scheduled after the frame (not during build) so
    // this triggers a clean, separate rebuild rather than mutating state
    // mid-build.
    if (!hasAvailableInRadius && hasAvailableAnywhere && !atMaxRadius && !_autoExpanding) {
      _autoExpanding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoExpanding = false;
        _expandRadius();
      });
    } else if (hasAvailableInRadius || atMaxRadius) {
      _autoExpanding = false;
    }

    // Startup / reopen resolution (spec §4): this case may already have a
    // valid pending offer outstanding (e.g. the admin backgrounded the app
    // mid-offer and is reopening this case from the Assign queue). Never
    // let the rider list/Next button be reachable while that's true — only
    // View Pending / Cancel Offer are available until it resolves.
    final currentAssignment = ref.watch(currentAssignmentProvider(widget.caseId)).asData?.value;
    // The offer just sent stands in until the live one arrives.
    final optimistic = _optimisticOffer != null &&
            (_sentAssignmentId == null || currentAssignment?.id != _sentAssignmentId)
        ? _optimisticOffer
        : null;
    final blockingOffer = optimistic ??
        (currentAssignment != null &&
                currentAssignment.status == TransportAssignmentStatus.pending &&
                currentAssignment.id != _optimisticCancelledId
            ? currentAssignment
            : null);
    if (blockingOffer != null) {
      if (blockingOffer.isStalePending) {
        _reconcileIfStale(blockingOffer);
      }
    }
    _syncTicker(blockingOffer != null);
    _openTrackingOnAccept(currentAssignment);
    final failedOffer = currentAssignment != null &&
            (currentAssignment.status == TransportAssignmentStatus.rejected ||
                currentAssignment.status == TransportAssignmentStatus.expired) &&
            currentAssignment.id != _dismissedOutcomeId
        ? currentAssignment
        : null;

    // Set once the admin closes the accepted dialog with "Close" instead of
    // "View Transport Tracking" (spec §6) — shows a persistent, explicit
    // "Continue to Tracking" banner instead of ever auto-navigating there.
    final acceptedAssignment =
    currentAssignment != null && currentAssignment.status == TransportAssignmentStatus.accepted
        ? currentAssignment
        : null;

    final failedOffers = ref.watch(failedOfferCountProvider(widget.caseId)).asData?.value ?? 0;
    final searchExhausted = atMaxRadius && !hasAvailableInRadius;
    final fallbackDismissed = _fallbackDismissedAtCount != null && failedOffers <= _fallbackDismissedAtCount!;
    // Only for the rescue pickup: this page is also the intake-leg
    // reassignment picker, where referring or "organization will
    // transport" don't apply.
    // fallbackApplies: the banner stays to reopen the options;
    // showFallback: the sheet opens by itself (not after Keep Waiting).
    final fallbackApplies = RescueStatus.fromFirestoreValue(d['status'] as String?) ==
        RescueStatus.awaitingAssignment &&
        blockingOffer == null &&
        acceptedAssignment == null &&
        shouldOfferNoTransporterFallback(searchExhausted: searchExhausted, failedOfferCount: failedOffers);
    final showFallback = fallbackApplies && !fallbackDismissed;
    _latestRiders = riders;
    if (showFallback && !_fallbackSheetOpen && !transportersLoading) {
      final isCritical = urgency == 'Critical';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openFallbackSheet(failedOffers: failedOffers, isCritical: isCritical, failedOffer: failedOffer);
      });
    }

    // Independent rescuers choose up front: bring it themselves, or pick a
    // transporter below. Needs the clinic saved first (awaitingAssignment).
    final showSelfTransport = _isIndependent &&
        !fallbackApplies &&
        RescueStatus.fromFirestoreValue(d['status'] as String?) == RescueStatus.awaitingAssignment &&
        blockingOffer == null &&
        acceptedAssignment == null;

    final highRisk = highRiskAnimalsIn(
      animals: d['animals'] as List?,
      legacyBiteRisk: d['biteRisk'] as String?,
      legacyEscapeRisk: d['escapeRisk'] as String?,
    );
    // Rescue pickup needs a destination: a clinic, or the shelter pin when
    // staff chose straight to shelter.
    final needsClinic = widget.postAcceptTrackingMode == TrackingMode.rescuePickup &&
        (d['transportDestination'] == 'shelter'
            ? !_shelterChosen(d)
            : ((d['vetClinicName'] as String?)?.trim().isEmpty ?? true));
    final canSend = _selectedRiderUid != null &&
        !_isAssigning &&
        !needsClinic &&
        (highRisk.isEmpty || _riskAcknowledged);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          // Normal page navigation only — always returns to Rescue
          // Details, regardless of selection.
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Assign Transport',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
      ),
      // One scroll for the whole page: banners, the map, notices and the
      // transporter list. A fixed column used to overflow on phones when
      // several banners showed, leaving a striped error block and a list
      // that couldn't be reached.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
        children: [
          // Case header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        species_summary_util.summarizeSpecies(
                            animals: d['animals'] as List?, legacyAnimalType: d['animalType'] as String?),
                        style: GoogleFonts.tiltWarp(
                            fontSize: 22, color: AppColors.textPrimary)),
                    Text(
                        'CASE ID: ${shortCaseId(widget.caseId)}',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgency == 'Critical'
                        ? AppColors.error
                        : AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(urgency,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          // Rescue pickup: the clinic is picked here too, so clinic and
          // transporter are one page. The intake leg's pickup is the
          // clinic the animal is already at.
          if (widget.postAcceptTrackingMode == TrackingMode.rescuePickup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _clinicCard(d),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: RescueRiskBanner(
              highRiskAnimals: highRiskAnimalsIn(
                animals: d['animals'] as List?,
                legacyBiteRisk: d['biteRisk'] as String?,
                legacyEscapeRisk: d['escapeRisk'] as String?,
              ),
            ),
          ),
          // Real map: case marker + transporter markers (real-or-demo positions).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: caseLocation == null
                    ? Container(
                  color: AppColors.slaterspwn,
                  child: Center(
                    child: Text('No coordinates saved for this case.',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                )
                    : GoogleMap(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                  initialCameraPosition: CameraPosition(target: caseLocation, zoom: 13),
                  markers: _buildMarkers(caseLocation, visibleRiders),
                  // Transporter search geofence — grows with the radius steps.
                  circles: {
                    Circle(
                      circleId: const CircleId('search_radius'),
                      center: caseLocation,
                      radius: _currentRadiusKm * 1000,
                      strokeWidth: 2,
                      strokeColor: AppColors.greenrspwn,
                      fillColor: AppColors.greenrspwn.withValues(alpha: 0.08),
                    ),
                  },
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    _fitCameraOnce(caseLocation, visibleRiders);
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (acceptedAssignment != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.greenrspwn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.check_circle, size: 18, color: AppColors.greenrspwn),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Accepted — ${acceptedAssignment.riderName}',
                            style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                            builder: (_) => AdminTrackCasePage(
                                caseId: widget.caseId, data: _currentCaseData(), mode: widget.postAcceptTrackingMode))),
                        style: AppButtons.primary,
                        child: Text('Continue to Tracking', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (acceptedAssignment != null) const SizedBox(height: 16),

          if (blockingOffer != null)
            _pendingOfferPanel(blockingOffer)
          else ...[
            if (fallbackApplies)
              _fallbackBanner(failedOffers: failedOffers, isCritical: urgency == 'Critical', failedOffer: failedOffer)
            else if (failedOffer != null)
              _failedOfferCard(failedOffer, riders),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Transporters',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary)),
                  Text('${_currentRadiusKm.toStringAsFixed(0)} km radius · ${visibleRiders.length} found',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),

            // Progressive Search Radius spec — status/manual controls.
            // Shown whenever nothing available is in range yet, so the
            // admin always knows why the list looks thin and can act
            // (expand sooner, or refresh) without waiting for auto-expand.
            if (!hasAvailableInRadius) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasUnsuitableOnly
                            ? 'No available vehicle has room for this trip\'s $tripAnimals '
                                'passenger${tripAnimals == 1 ? '' : 's'}.'
                            : atMaxRadius
                            ? (hasAvailableAnywhere
                        // Shouldn't happen (max radius should contain
                        // everyone), kept only as a safe fallback.
                            ? 'No available transporters in range.'
                            : 'No compatible transporters are currently available. Try again later or use manual assignment.')
                            : hasAvailableAnywhere
                            ? 'No suitable transporters nearby. Expanding the search radius…'
                            : 'No available transporters nearby.',
                        style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                      if (atMaxRadius)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Maximum search radius reached (${_maxRadiusKm.toStringAsFixed(0)} km).',
                              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!atMaxRadius)
                            OutlinedButton(
                              onPressed: _expandRadius,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Expand Now', style: TextStyle(fontSize: 12)),
                            ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _resetRadius,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Refresh', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            if (showSelfTransport)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: OutlinedButton.icon(
                  onPressed: _fallbackBusy ? null : _organizationWillTransport,
                  style: AppButtons.outline,
                  icon: const Icon(Icons.directions_car_outlined, size: 18),
                  label: Text("I'll Bring It Myself — or pick a transporter below",
                      style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
                ),
              ),

            // What the vehicle has to carry (transport_suitability.dart).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Passengers: $tripAnimals animal${tripAnimals == 1 ? '' : 's'}. '
                'Transporters without room for them are listed but can\'t be selected.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),

            // Transporter list — fixed order (see _buildRiderVms): demo
            // transporters pinned above the real-Available group only while
            // they're Available themselves, then real transporters grouped
            // available -> pending -> busy, each by distance. Pending/busy
            // transporters stay visible, just not selectable. Filtered to
            // the current search radius (Progressive Search Radius spec) —
            // scroll position/list identity otherwise untouched by radius
            // changes since this is the same ListView, just fewer/more items.
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: transportersLoading
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  : visibleRiders.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No online transporters are currently available.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              )
                  : ListView.separated(
                key: const PageStorageKey('assign_rider_list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: visibleRiders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final rider = visibleRiders[index];
                  final isSelected = _selectedRiderUid == rider.uid;
                  return _RiderCard(
                    rider: rider,
                    isSelected: isSelected,
                    onSelect: () => _selectRider(rider),
                    animalProfile: animalProfile,
                    tripAnimals: tripAnimals,
                  );
                },
              ),
            ),

          ],
        ],
            ),
          ),
        ],
      ),
      // Fixed bottom action, outside the scroll so it stays reachable.
      bottomNavigationBar: blockingOffer != null
          ? null
          : // Fixed bottom action — always visible; "Send offer" stays
            // disabled until a clinic (rescue pickup), an available
            // transporter and, for high-risk animals, the risk
            // acknowledgement are all in place.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.slaterspwn)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (highRisk.isNotEmpty)
                      CheckboxListTile(
                        value: _riskAcknowledged,
                        onChanged: (v) => setState(() => _riskAcknowledged = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('I\'ve told the transporter about the bite/escape risk above.',
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    if (needsClinic)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Choose where the animal goes to send the offer.',
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: !canSend ? null : () => _handleNext(visibleRiders),
                        style: AppButtons.primary,
                        child: _isAssigning
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                            : Text(
                                _selectedRiderUid == null ? 'Select a transporter' : 'Send offer',
                                style: GoogleFonts.tiltWarp(
                                    fontSize: 15,
                                    color: canSend ? AppColors.textPrimary : AppColors.textSecondary),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final _RiderVm rider;
  final bool isSelected;
  final VoidCallback onSelect;
  final AnimalTransportProfile animalProfile;
  final int tripAnimals;

  const _RiderCard({
    required this.rider,
    required this.isSelected,
    required this.onSelect,
    required this.animalProfile,
    required this.tripAnimals,
  });

  // Same tel: launch pattern as transporter_details_card.dart's _launchCall.
  Future<void> _launchCall(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: rider.phone!.trim());
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Could not start the call.'),
      );
    }
  }

  (String, Color, Color) _statusChip() => switch (rider.availability) {
    _RiderAvailability.available => ('Available', AppColors.greenrspwn, AppColors.textPrimary),
    _RiderAvailability.pending => ('Pending', AppColors.yellowrspwn, AppColors.textPrimary),
    _RiderAvailability.busy => ('Busy', AppColors.slaterspwn, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final isAvailable = rider.availability == _RiderAvailability.available;
    final (statusLabel, statusColor, statusTextColor) = _statusChip();

    return GestureDetector(
      // Tapping anywhere on an available card selects it; pending/busy
      // cards aren't interactive at all (stay visible, just not selectable).
      onTap: isAvailable ? onSelect : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          // Selection is communicated ONLY through this border highlight —
          // never by changing the status chip (which always reflects true
          // Available/Pending/Busy state, selected or not).
          border: isSelected
              ? Border.all(color: AppColors.textPrimary, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(photoUrl: rider.photoUrl),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The name gets the full width (two lines if needed);
                  // the labels wrap underneath instead of squeezing it.
                  Text(rider.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Selection is shown only by the card border; this
                      // always reflects true Available/Pending/Busy state.
                      _pill(statusLabel, fill: statusColor, text: statusTextColor),
                      _pill(rider.type, fill: AppColors.yellowrspwn, text: AppColors.textPrimary),
                      // Transporter Ranking spec — "Preferred" is shown as an
                      // explicit reason, never a silent reordering.
                      if (rider.isPreferred)
                        _pill('Preferred',
                            fill: AppColors.greenrspwn.withValues(alpha: 0.18), text: AppColors.greenrspwn),
                      if (!rider.suitability.suitable)
                        _pill('Not suitable', fill: AppColors.error.withValues(alpha: 0.12), text: AppColors.error),
                      if (rider.isDemo)
                        _pill('DEMO',
                            fill: Colors.transparent,
                            text: AppColors.textSecondary,
                            border: AppColors.textSecondary.withValues(alpha: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(rider.distanceLabel,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(compatibilityReason(rider.vehicleCategory, animalProfile),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text('${rider.plate}  ${rider.vehicle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textSecondary)),
                  // Why this transporter is (or isn't) suitable: declared
                  // capacity against the animals in this trip.
                  Text(
                    '${rider.suitability.declaredCapacity == null ? 'Capacity not declared' : 'Carries up to ${rider.suitability.declaredCapacity}'}'
                    ' · this trip: $tripAnimals',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  Text(
                    rider.suitability.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: rider.suitability.suitable ? AppColors.greenrspwn : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),

            // Call only (messages live on Track Case). Hidden when there's
            // no number to dial (demo transporters).
            if ((rider.phone ?? '').trim().isNotEmpty)
              IconButton(
                onPressed: () => _launchCall(context),
                tooltip: 'Call',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.textPrimary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, {required Color fill, required Color text, Color? border}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(20),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Text(label,
            style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: text)),
      );
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          photoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: AppColors.tearspwn,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.directions_car, color: AppColors.textSecondary),
  );
}
