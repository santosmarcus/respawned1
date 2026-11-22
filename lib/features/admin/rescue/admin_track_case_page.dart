import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/route_result.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/widgets/transit_route.dart';
import 'package:geolocator/geolocator.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';
import 'package:respawnd1/core/utils/species_summary.dart'
as species_summary_util;
import 'package:respawnd1/core/widgets/rescue_risk_banner.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_flow.dart';
import 'package:respawnd1/features/admin/rescue/widgets/community_reports_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transporter_details_card.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

// Raw case-doc status values written by the pet-transporter app's own
// transit flow (see transit_progress_page.dart) once it has physically
// reached the clinic — either waiting on the clinic's accept/reject
// decision ('dropoff'), or already past it ('in_transit_shelter'). Neither
// of these is the multi-day clinical-care phase this screen's "Proceed to
// Treatment" button starts — that's a separate, admin-triggered status
// (RescueStatus.treatment / 'in_treatment').
// 'awaiting_adopter_pickup': the clinic accepted treatment and a confirmed
// adopter will collect the animal there (Rescue gaps 6/10), so staff
// continue with Proceed to Treatment.
const _kArrivedAtClinicStatuses = {'dropoff', 'in_transit_shelter', 'awaiting_adopter_pickup'};

// Same transporter-written status vocabulary, but the slice that means
// "animal already picked up, headed toward a clinic" — 'treatment' here is
// the transporter's own (confusingly-named) en-route-to-clinic status, not
// RescueStatus.treatment. Once in one of these, the tracking destination
// switches from the rescue case to the selected clinic.
const _kPostPickupStatuses = {
  'treatment',
  'dropoff',
  'searching_clinic',
  'in_transit_shelter',
};

/// Which leg of the case this screen is tracking. Added so the same
/// Track Case screen (map, route, transporter card, timeline) serves both
/// the original rescue pickup and the later clinic-to-shelter intake
/// transport, instead of building a second tracking page — only the
/// origin/destination resolution and which sections are visible change.
enum TrackingMode { rescuePickup, intakeTransfer }

class AdminTrackCasePage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final TrackingMode mode;
  const AdminTrackCasePage({
    super.key,
    required this.caseId,
    required this.data,
    this.mode = TrackingMode.rescuePickup,
  });

  @override
  ConsumerState<AdminTrackCasePage> createState() => _AdminTrackCasePageState();
}

class _AdminTrackCasePageState extends ConsumerState<AdminTrackCasePage> {
  int _tabIndex = 0;
  final _messageController = TextEditingController();

  // Drives the collapsible transporter card (see _CollapsibleTransporterCard)
  // — a purely local/visual toggle, never tied to re-fetching the
  // assignment stream itself (that's still watched once, at the top of
  // build()). Auto-collapses once the admin scrolls the tracking-detail
  // content down past a small threshold, expands again near the top; a tap
  // on the card itself can also toggle it directly (see onToggle below).
  final ScrollController _scrollController = ScrollController();
  bool _transporterCollapsed = false;
  static const _collapseThreshold = 24.0;
  bool _closing = false;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  /// "Change Clinic" (spec §7) — reuses the exact same Select Clinic sheet
  /// as the initial pick, just with `previousClinicName` set so the sheet
  /// calls RescueCaseRepository.changeClinic instead of assignClinic (see
  /// select_clinic_sheet.dart). Never creates a new case/assignment, never
  /// marks the transport assignment completed.
  Future<void> _changeClinic(RescueCase c) async {
    if (c.vetClinicName == null) return;
    final confirmed = await showConfirmActionDialog(context, title: 'Change Clinic?', message: 'Changing the clinic will update the transporter\'s destination and route. Continue?', confirmLabel: 'Continue');
    if (confirmed != true || !mounted) return;

    // Never auto-opens anything else once the sheet resolves — the admin
    // stays on this same tracking page either way.
    await showSelectClinicSheet(
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
      offerAssignRider: false,
      previousClinicName: c.vetClinicName,
    );
  }

  /// Ongoing's own Close Case entry point (spec §3) — calls the same
  /// performCloseCase helper Treatment/Intake/Rescue Details all use, not a
  /// separate Ongoing-only implementation. Pops back to Rescue history only
  /// after the write actually succeeds — never before, and never a second
  /// time from a listener (this method is the only place that pops).
  Future<void> _closeCase(RescueCase c, {ClosureReason? initialReason}) async {
    if (_closing) return;
    setState(() => _closing = true);
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
        // Only leave this tracking page once the CASE itself is closed —
        // a per-animal death that leaves the case active (other animals
        // still in treatment) should keep the admin here, not bounce them
        // back to Rescue history for a case that's still ongoing.
        if (outcome.wholeCaseClosed) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not close case: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _handleScroll() {
    final offset = _scrollController.offset;
    if (offset > _collapseThreshold && !_transporterCollapsed) {
      setState(() => _transporterCollapsed = true);
    } else if (offset <= _collapseThreshold && _transporterCollapsed) {
      setState(() => _transporterCollapsed = false);
    }
  }

  void _toggleTransporterCard() =>
      setState(() => _transporterCollapsed = !_transporterCollapsed);

  /// Guards against double-tapping "Proceed to Treatment" and drives the
  /// button's loading state while the write is in flight and being
  /// verified.
  bool _isProceedingToTreatment = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('messages')
        .add({
      'senderId': 'admin',
      'senderName': 'Loved by the Gapz',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  Future<void> _proceedToTreatment(Map<String, dynamic> data) async {
    if (_isProceedingToTreatment) return; // guard against double-tap
    setState(() => _isProceedingToTreatment = true);

    final caseRef = FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId);
    final expectedStatus =
        RescueStatus.treatment.firestoreValue; // 'in_treatment'

    try {
      await RescueCaseStore(FirebaseFirestore.instance).recordAction(
        caseId: widget.caseId,
        action: 'treatment_started',
        statusLine: 'The animal has reached the clinic. Animal is now in treatment.',
        actorUid: _actorUid,
        actorName: _actorName,
        fields: {
          'status': expectedStatus,
          'dateAdmitted': Timestamp.now(),
        },
      );

      // Don't navigate optimistically — re-read the doc and only proceed
      // once the write has actually landed with the expected status. A
      // stale local snapshot or a write that silently didn't apply would
      // otherwise still open Treatment Details on a case that Rescue
      // Reports/Rescue Details still see as 'ongoing'.
      final freshSnap = await caseRef.get();
      final freshStatus = freshSnap.data()?['status'] as String?;
      if (freshStatus != expectedStatus) {
        throw StateError(
          'Case status did not update as expected (got "$freshStatus").',
        );
      }

      // Frees the accepted transporter (demo or real) back to "Available"
      // — activeAssignmentsByRiderProvider derives each transporter's chip
      // from their single most-recent assignment, so marking this one
      // 'completed' is what clears their Busy state elsewhere. Only done
      // once the treatment transition itself is confirmed, never before.
      final assignment = ref
          .read(currentAssignmentProvider(widget.caseId))
          .asData
          ?.value;
      if (assignment != null &&
          assignment.status == TransportAssignmentStatus.accepted) {
        await ref
            .read(rescueCaseRepositoryProvider)
            .completeAssignment(
          caseId: widget.caseId,
          assignmentId: assignment.id,
        );
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TreatmentDetailPage(
              caseId: widget.caseId,
              data: {...data, 'status': expectedStatus},
            ),
          ),
        );
      }
    } catch (e) {
      // Stay on Track Case — never navigate on an unconfirmed/failed write.
      if (mounted) {
        setState(() => _isProceedingToTreatment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not move this case to treatment: $e', kind: AppMessageKind.error),
        );
      }
    }
  }

  // TESTING ONLY — simulates the transporter reaching the clinic without
  // waiting for real GPS movement (mirrors the same pattern already used by
  // transit_progress_page.dart's own _testSkipToNextStep). Lets staff
  // exercise "Proceed to Treatment" without a live rider in transit.
  Future<void> _fastForwardToClinic() async {
    await RescueCaseStore(FirebaseFirestore.instance).recordAction(
      caseId: widget.caseId,
      action: 'test_arrived_at_clinic',
      statusLine: '[TEST] Fast-forwarded — transporter marked as arrived at the clinic.',
      actorUid: _actorUid,
      actorName: _actorName,
      fields: {
        'status': 'dropoff',
      },
    );
  }

  LatLng? _caseLocationFrom(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// The transporter's last reported position (`riderLastLat`/`riderLastLng`,
  /// written by the transporter app's transit flow — see
  /// transit_case_service.dart), or null before they've reported one. The
  /// map then shows "location not shared yet" instead of a made-up pin.
  /// Never overwrites that field — this only reads it.
  LatLng? _riderLocationFrom(Map<String, dynamic> data) {
    final lat = (data['riderLastLat'] as num?)?.toDouble();
    final lng = (data['riderLastLng'] as num?)?.toDouble();
    return (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  /// Where the rider is currently heading. Before pickup, that's the
  /// rescue case; after pickup, it's the selected clinic — and once we're
  /// past pickup, this deliberately never falls back to the rescue case
  /// location even if clinic coordinates are temporarily missing, since
  /// that would silently send the rider to a stop they already left.
  /// Priority after pickup: saved selected-clinic coordinates ->
  /// legacy transporter-side dropoff coordinates -> visible warning
  /// (location null, caller shows markers-only / no route).
  ///
  /// In [TrackingMode.intakeTransfer], this is unrelated to the legacy
  /// pickup/dropoff status vocabulary entirely — the destination is always
  /// the intake shelter location saved by RescueCaseRepository.confirmIntake.
  ({LatLng? location, String label}) _destinationFrom(
      Map<String, dynamic> data,
      ) {
    if (widget.mode == TrackingMode.intakeTransfer) {
      final lat = (data['intakeDestinationLat'] as num?)?.toDouble();
      final lng = (data['intakeDestinationLng'] as num?)?.toDouble();
      final name = data['intakeDestinationName'] as String?;
      if (lat == null || lng == null) {
        return (location: null, label: 'No shelter destination available yet');
      }
      return (
      location: LatLng(lat, lng),
      label: (name != null && name.isNotEmpty)
          ? name
          : 'Organization Shelter',
      );
    }

    final rawStatus = data['status'] as String?;
    if (!_kPostPickupStatuses.contains(rawStatus)) {
      return (location: _caseLocationFrom(data), label: 'Rescue Case');
    }

    final vetLat = (data['vetClinicLat'] as num?)?.toDouble();
    final vetLng = (data['vetClinicLng'] as num?)?.toDouble();
    if (vetLat != null && vetLng != null) {
      return (location: LatLng(vetLat, vetLng), label: 'Selected Clinic');
    }

    // Legacy: the transporter app's own independent clinic-search
    // destination (see transit_progress_page.dart's
    // _findAndRouteToNextClinic) — used if a clinic was picked there
    // rather than through the admin's Select Clinic sheet.
    final dropoffLat = (data['dropoffLat'] as num?)?.toDouble();
    final dropoffLng = (data['dropoffLng'] as num?)?.toDouble();
    if (dropoffLat != null && dropoffLng != null) {
      return (
      location: LatLng(dropoffLat, dropoffLng),
      label: 'Clinic (legacy destination)',
      );
    }

    return (location: null, label: 'No clinic destination available yet');
  }

  /// The secondary "where they started from" marker — the original rescue
  /// location pre-intake, or the pickup clinic during intake transport.
  LatLng? _originMarkerLocationFrom(Map<String, dynamic> data) {
    if (widget.mode == TrackingMode.intakeTransfer) {
      final lat = (data['vetClinicLat'] as num?)?.toDouble();
      final lng = (data['vetClinicLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }
    return _caseLocationFrom(data);
  }

  String get _originMarkerLabel => widget.mode == TrackingMode.intakeTransfer
      ? 'Clinic Pickup'
      : 'Original Rescue Location';

  Future<void> _confirmAnimalReceived(TransportAssignment? assignment) async {
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .confirmAnimalReceived(
        caseId: widget.caseId,
        currentAssignmentId: assignment?.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Animal received — transport complete.', kind: AppMessageKind.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not confirm arrival: $e', kind: AppMessageKind.error),
        );
      }
    }
  }

  Widget _buildTrackingMap(
      Map<String, dynamic> data,
      TransportAssignment? assignment,
      ) {
    // Shown in place of the map, on this same page, whenever the current
    // offer hasn't been accepted yet — no separate Pending/Rejected page
    // or route. In normal use the admin never actually sees this: the
    // Assign Transporter modal already carries them through pending and
    // straight to acceptance before Track Case is ever opened. This only
    // matters for the edge case of reopening the case (e.g. after an app
    // restart) while an offer is still outstanding.
    if (assignment != null &&
        assignment.status == TransportAssignmentStatus.pending) {
      return _PendingAssignmentBanner(
        caseId: widget.caseId,
        assignment: assignment,
        caseData: data,
      );
    }
    if (assignment != null &&
        assignment.status == TransportAssignmentStatus.rejected) {
      return _DeclinedAssignmentBanner(
        assignment: assignment,
        onChooseAnother: () => Navigator.pop(context),
      );
    }

    final caseLocation = _originMarkerLocationFrom(data);
    final destination = _destinationFrom(data);

    if (caseLocation == null && destination.location == null) {
      // "Markers only" / no-line tier: nothing to plot at all. The
      // transporter card (when accepted) now lives below, in the
      // scrollable body — see build()'s _CollapsibleTransporterCard.
      return Container(
        height: 180,
        color: AppColors.slaterspwn,
        child: Center(
          child: Text(
            'No coordinates saved for this case.',
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final rider = _riderLocationFrom(data);

    if (destination.location == null) {
      // Post-pickup with no clinic coordinates on file at all (neither the
      // admin's selected clinic nor the transporter's own legacy dropoff
      // fields) — show a visible warning instead of silently routing back
      // to the rescue case, which the rider has already left.
      return SizedBox(
        height: 180,
        child: Stack(
          children: [
            GoogleMap(
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                ),
              },
              // caseLocation is non-null whenever rider is null here — the
              // both-missing case returned early above.
              initialCameraPosition: CameraPosition(
                target: rider ?? caseLocation!,
                zoom: 13,
              ),
              markers: {
                if (caseLocation != null)
                  Marker(
                    markerId: const MarkerId('rescue_case'),
                    position: caseLocation,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueViolet,
                    ),
                    infoWindow: InfoWindow(title: _originMarkerLabel),
                  ),
                if (rider != null)
                  Marker(
                    markerId: const MarkerId('rider'),
                    position: rider,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                    infoWindow: const InfoWindow(title: 'Transporter'),
                  ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        destination.label,
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final destinationLocation = destination.location!;
    final isPostPickupDestination = destination.label != 'Rescue Case';
    // Only add a separate "original case" marker once the destination has
    // actually moved on to the clinic — pre-pickup, the case *is* the
    // destination, so a second marker at the same point would be redundant.
    final showSeparateCaseMarker =
        isPostPickupDestination &&
            caseLocation != null &&
            (caseLocation.latitude != destinationLocation.latitude ||
                caseLocation.longitude != destinationLocation.longitude);

    // Same route line and color as the transporter's own map, with the
    // transporter's marker gliding between GPS reports (_LiveTrackingMap).
    return _LiveTrackingMap(
      caseId: widget.caseId,
      rider: rider,
      destination: destinationLocation,
      destinationLabel: destination.label,
      origin: showSeparateCaseMarker ? caseLocation : null,
      originLabel: _originMarkerLabel,
      directions: ref.read(directionsRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? (snapshot.data!.data() as Map<String, dynamic>? ?? widget.data)
            : widget.data;
        final statusHistory = List<Map<String, dynamic>>.from(
          data['statusHistory'] ?? [],
        );

        // Gate on the current transporter offer's persisted status — never
        // on local widget state — so reopening this page (e.g. after an
        // app restart while an offer is still pending) always shows the
        // right thing. This is a single page throughout: the pending/
        // declined states below only swap what's shown where the tracking
        // map normally goes (see _buildTrackingMap), never a separate
        // page/route. A missing assignment doc (legacy cases assigned
        // before this feature existed) falls through to the tracking map,
        // matching the old always-tracking behavior.
        final assignment = ref
            .watch(currentAssignmentProvider(widget.caseId))
            .asData
            ?.value;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.background),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              widget.mode == TrackingMode.intakeTransfer
                  ? 'Intake Transport'
                  : 'Track Case',
              style: GoogleFonts.tiltWarp(
                fontSize: 18,
                color: AppColors.background,
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.background),
                enabled: !_closing,
                onSelected: (value) {
                  final c = RescueCase.fromMap(widget.caseId, data);
                  if (value == 'change_clinic') {
                    _changeClinic(c);
                  } else if (value == 'close_case') {
                    // Controlled Close Case (spec §3) — full reason picker,
                    // no preset. The old "Animal Moved / Could Not Be
                    // Located" one-tap shortcut that used to live here is
                    // gone: an actual animal-moved location update now only
                    // ever comes from an approved Community Report, and any
                    // OTHER reason for closing this Ongoing case (including
                    // "animal moved / could not be located" as a genuine
                    // closure reason) goes through this same full sheet.
                    _closeCase(c);
                  }
                },
                itemBuilder: (context) => [
                  if (data['vetClinicName'] != null)
                    const PopupMenuItem(
                      value: 'change_clinic',
                      child: Text('Change Clinic'),
                    ),
                  const PopupMenuItem(
                    value: 'close_case',
                    child: Text('Close Case'),
                  ),
                ],
              ),
            ],
          ),
          // One coherent scrollable layout below the map — see
          // _CollapsibleTransporterCard / _handleScroll for how the
          // transporter card collapses as this scrolls, and
          // _AdminTrackingTab for the collapsible Messages section further
          // down. No nested independently-scrolling regions: the old
          // per-tab ListView/SingleChildScrollView wrappers are gone, this
          // single controller drives everything except the map itself.
          body: Column(
            children: [
              _buildTrackingMap(data, assignment),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),

                        if (assignment != null &&
                            assignment.status ==
                                TransportAssignmentStatus.accepted)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CollapsibleTransporterCard(
                              assignment: assignment,
                              collapsed: _transporterCollapsed,
                              onToggle: _toggleTransporterCard,
                            ),
                          ),

                        // Tab switcher — intake transport is a restricted
                        // view with only one tab (Case Detail carries
                        // reporter-facing content that doesn't belong here;
                        // see the class-level restriction note).
                        if (widget.mode != TrackingMode.intakeTransfer)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Row(
                              children: [
                                _AdminTabButton(
                                  label: 'Tracking Detail',
                                  selected: _tabIndex == 0,
                                  onTap: () => setState(() => _tabIndex = 0),
                                ),
                                _AdminTabButton(
                                  label: 'Case Detail',
                                  selected: _tabIndex == 1,
                                  onTap: () => setState(() => _tabIndex = 1),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 12),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '#${shortCaseId(widget.caseId)}',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 18,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RescueRiskBanner(
                            highRiskAnimals: highRiskAnimalsIn(
                              animals: data['animals'] as List?,
                              legacyBiteRisk: data['biteRisk'] as String?,
                              legacyEscapeRisk: data['escapeRisk'] as String?,
                            ),
                          ),
                        ),

                        (widget.mode == TrackingMode.intakeTransfer ||
                            _tabIndex == 0)
                            ? _AdminTrackingTab(
                          statusHistory: statusHistory,
                          caseId: widget.caseId,
                          messageController: _messageController,
                          onSend: _sendMessage,
                          isIntakeMode:
                          widget.mode == TrackingMode.intakeTransfer,
                          transporterHasReachedClinic:
                          _kArrivedAtClinicStatuses.contains(
                            data['status'],
                          ),
                          isProceedingToTreatment:
                          _isProceedingToTreatment,
                          onProceedToTreatment: () =>
                              _proceedToTreatment(data),
                          onFastForward: _fastForwardToClinic,
                          hasReceivedIntake:
                          data['intakeReceivedAt'] != null,
                          onConfirmAnimalReceived: () =>
                              _confirmAnimalReceived(assignment),
                          hideCommunityContent:
                          data['sourceType'] ==
                              'animalRecordAdmission',
                        )
                            : _AdminCaseDetailTab(data: data),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AdminTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.background : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Now a plain (non-independently-scrolling) column of content — this is
/// rendered inside AdminTrackCasePage's own single SingleChildScrollView
/// (see build()'s doc comment), not in its own ListView/Expanded, so the
/// status timeline, community reports, and Messages all share one scroll
/// gesture with the transporter card and map above them instead of
/// competing nested scroll regions.
class _AdminTrackingTab extends StatefulWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final bool transporterHasReachedClinic;
  final bool isProceedingToTreatment;
  final VoidCallback onProceedToTreatment;
  final VoidCallback onFastForward;
  final bool isIntakeMode;
  final bool hasReceivedIntake;
  final VoidCallback onConfirmAnimalReceived;

  /// True for an animal-record medical admission (see
  /// RescueCaseRepository.createAdmissionCase / data['sourceType']) —
  /// suppresses CommunityReportsSection, which only makes sense for a
  /// community-submitted rescue report. Reporter-facing messaging already
  /// doesn't render anywhere on this admin screen regardless, so nothing
  /// else needs hiding here.
  final bool hideCommunityContent;

  const _AdminTrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    required this.onSend,
    required this.transporterHasReachedClinic,
    required this.isProceedingToTreatment,
    required this.onProceedToTreatment,
    this.hideCommunityContent = false,
    required this.onFastForward,
    required this.isIntakeMode,
    required this.hasReceivedIntake,
    required this.onConfirmAnimalReceived,
  });

  @override
  State<_AdminTrackingTab> createState() => _AdminTrackingTabState();
}

class _AdminTrackingTabState extends State<_AdminTrackingTab> {
  // Collapsed by default so the status timeline above is readable without
  // the message composer taking most of the screen — independent of the
  // transporter card's own collapse state, no scroll-position involved
  // here, just a direct tap toggle.
  bool _messagesExpanded = false;

  Widget _buildTimelineItem(int index) {
    final statusHistory = widget.statusHistory;
    final item = statusHistory[index];
    final isLast = index == statusHistory.length - 1;
    final ts = item['timestamp'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null
        ? 'February ${ts.toDate().day}, ${ts.toDate().year}'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isLast ? AppColors.textPrimary : AppColors.slaterspwn,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textPrimary, width: 2),
              ),
              child: isLast
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (index < statusHistory.length - 1)
              Container(width: 2, height: 40, color: AppColors.textPrimary),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item['status'] ?? '',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: GoogleFonts.zain(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: GoogleFonts.zain(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusHistory = widget.statusHistory;
    return Column(
      children: [
        // Status timeline + community reports — same subcollection/section
        // widget the Rescue Details page uses, reused here rather than a
        // second implementation. Community reports (and, further down,
        // original case media/reporter content) are reporter-facing and
        // stay out of intake transport, which is restricted to the
        // organization + assigned transporter. No longer its own ListView —
        // this is now part of the page's single outer scroll (see the
        // class doc comment).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < statusHistory.length; i++)
                _buildTimelineItem(i),
              const SizedBox(height: 8),
              if (!widget.isIntakeMode && !widget.hideCommunityContent)
                CommunityReportsSection(caseId: widget.caseId),
              const SizedBox(height: 8),
            ],
          ),
        ),

        const Divider(),

        // Collapsible Messages — collapsed by default so the status
        // timeline above is readable without the composer taking most of
        // the screen. A single StreamBuilder always stays mounted here
        // (never conditionally created/destroyed by the collapse toggle),
        // so expanding/collapsing never disposes or duplicates the
        // messages listener — see the class doc comment.
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('cases')
              .doc(widget.caseId)
              .collection('messages')
              .orderBy('timestamp')
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final count = docs.length;
            final summary = count == 0
                ? 'No messages yet'
                : '$count message${count == 1 ? '' : 's'}';

            return Column(
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _messagesExpanded = !_messagesExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Messages',
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              summary,
                              style: GoogleFonts.zain(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _messagesExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_messagesExpanded) ...[
                  SizedBox(
                    height: 200,
                    child: docs.isEmpty
                        ? Center(
                      child: Text(
                        'No messages yet.',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final msg =
                        docs[i].data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: AppColors.slaterspwn,
                                child: Text(
                                  (msg['senderName'] ?? 'U')[0],
                                  style: GoogleFonts.zain(fontSize: 10),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${msg['senderName']}: ${msg['text']}',
                                  style: GoogleFonts.zain(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: widget.messageController,
                            decoration: InputDecoration(
                              hintText: 'Type a message',
                              hintStyle: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: const BorderSide(
                                  color: AppColors.slaterspwn,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: const BorderSide(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onSend,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.yellowrspwn,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),

        // Intake transport's own confirmation action, replacing the
        // rescue-pickup "Proceed to Treatment"/fast-forward controls
        // entirely — arriving at the shelter doesn't move the case past
        // Intake, it just unlocks quarantine/animal-record steps back on
        // Intake Details (see RescueCaseRepository.confirmAnimalReceived).
        if (widget.isIntakeMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: widget.hasReceivedIntake
                ? Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.greenrspwn.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text(
                  'Animal received at the shelter.',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            )
                : ElevatedButton(
              onPressed: widget.onConfirmAnimalReceived,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                minimumSize: const Size(double.infinity, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'Confirm Animal Received',
                style: GoogleFonts.tiltWarp(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          )
        // Proceed to Treatment — only enabled once the transporter has
        // actually reached the clinic (status 'dropoff'/'in_transit_shelter').
        // Before that, show a fast-forward control for testing without GPS.
        else if (widget.transporterHasReachedClinic)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: widget.isProceedingToTreatment
                  ? null
                  : widget.onProceedToTreatment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                disabledBackgroundColor: AppColors.slaterspwn,
                minimumSize: const Size(double.infinity, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: widget.isProceedingToTreatment
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              )
                  : Text(
                'Proceed to Treatment',
                style: GoogleFonts.tiltWarp(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text(
                  'Waiting for the transporter to reach the clinic…',
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onFastForward,
                  icon: const Icon(Icons.fast_forward, size: 18),
                  label: Text(
                    'Fast-forward to Clinic (Test)',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.slaterspwn),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdminCaseDetailTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AdminCaseDetailTab({required this.data});

  @override
  Widget build(BuildContext context) {
    // No longer its own SingleChildScrollView — this is now part of
    // AdminTrackCasePage's single outer scroll (see _AdminTrackingTab's
    // class doc comment for why nested independent scroll regions were
    // removed).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('Reporter Name', data['reporterName']),
          _Row('Reporter Mobile Number', data['reporterPhone']),
          _Row('Pet Transporter Name', data['assignedVolunteerName']),
          _Row('Pet Transporter Mobile Number', '-'),
          _Row('Address', data['address']),
          _Row('Description', data['condition']),
          _Row(
            'Type of Animal',
            species_summary_util.summarizeSpecies(
              animals: data['animals'] as List?,
              legacyAnimalType: data['animalType'] as String?,
            ),
          ),
          _Row('Urgency', data['urgency']),
          _Row('Coordination', data['coordinateWithShelter']),
          if (data['coordinateWithShelter'] == 'no') ...[
            _Row('Witness Name', data['witnessName']),
            _Row('Witness Mobile Number', data['witnessPhone']),
          ],
          _Row('Interest to adopt', data['interestedToAdopt']),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            value ?? '-',
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline replacement for what used to be a separate "Pending Transporter
/// Response" page — same Track Case page/route, just swapped in where the
/// map normally renders. In the normal flow this is never actually seen
/// (the Assign Transporter modal already carries the admin through
/// Pending before Track Case opens); it only surfaces if the case is
/// reopened while an offer is still outstanding.
/// Wraps the existing TransporterDetailsCard (expanded state, unchanged
/// look) with a compact collapsed row for when the admin has scrolled the
/// tracking content down — see AdminTrackCasePage._handleScroll for what
/// drives [collapsed]. Both states watch the same
/// transporterProfileProvider family key (uid/name/type/isDemo), so
/// toggling between them never causes a second fetch — Riverpod keeps that
/// provider's cached value alive as long as either widget is watching it,
/// and one of them always is. [assignment] itself is passed down unchanged
/// from the single currentAssignmentProvider watch at the top of
/// AdminTrackCasePage.build() — collapsing/expanding is pure local visual
/// state, never a new stream subscription.
class _CollapsibleTransporterCard extends StatelessWidget {
  final TransportAssignment assignment;
  final bool collapsed;
  final VoidCallback onToggle;

  const _CollapsibleTransporterCard({
    required this.assignment,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: collapsed
          ? _CompactTransporterRow(assignment: assignment, onTap: onToggle)
          : Column(
        children: [
          TransporterDetailsCard(assignment: assignment),
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed-state row: `[avatar] Name · Vehicle    Status ▼`. Tapping
/// anywhere expands the card again (see _CollapsibleTransporterCard).
class _CompactTransporterRow extends ConsumerWidget {
  final TransportAssignment assignment;
  final VoidCallback onTap;
  const _CompactTransporterRow({required this.assignment, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(
      transporterProfileProvider((
      uid: assignment.riderId,
      fallbackName: assignment.riderName,
      type: assignment.riderType,
      isDemo: assignment.isDemo,
      )),
    );
    final profile =
        profileAsync.asData?.value ??
            TransporterProfile(
              uid: assignment.riderId,
              name: assignment.riderName,
              type: assignment.riderType,
              vehicle: 'Not provided',
              plate: 'Not provided',
              isDemo: assignment.isDemo,
            );

    final isCompleted =
        assignment.status == TransportAssignmentStatus.completed;
    final chipLabel = isCompleted ? 'Completed' : 'Busy';
    final chipColor = isCompleted
        ? AppColors.slaterspwn
        : AppColors.yellowrspwn;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (profile.photoUrl != null && profile.photoUrl!.isNotEmpty)
                  ? Image.network(
                profile.photoUrl!,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 32,
                  height: 32,
                  color: AppColors.tearspwn,
                  child: const Icon(
                    Icons.directions_car,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
                  : Container(
                width: 32,
                height: 32,
                color: AppColors.tearspwn,
                child: const Icon(
                  Icons.directions_car,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${profile.name} · ${profile.vehicle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                chipLabel,
                style: GoogleFonts.zain(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reached whenever this page opens (or reopens — e.g. after an app
/// restart) while an offer is still outstanding (spec §4/§5). Shows how
/// long the offer has been waiting and a Cancel Offer action, so the admin
/// is never stuck watching an indefinite spinner with no way to move a case
/// off a transporter who isn't responding.
class _PendingAssignmentBanner extends ConsumerStatefulWidget {
  final String caseId;
  final TransportAssignment assignment;
  final Map<String, dynamic> caseData;
  const _PendingAssignmentBanner({
    required this.caseId,
    required this.assignment,
    required this.caseData,
  });

  @override
  ConsumerState<_PendingAssignmentBanner> createState() =>
      _PendingAssignmentBannerState();
}

class _PendingAssignmentBannerState
    extends ConsumerState<_PendingAssignmentBanner> {
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // Startup resolution (spec §4): a pending offer whose TTL already
    // elapsed before this page was even opened is cleaned up in place
    // rather than shown as if still actionable — currentAssignmentProvider
    // then reflects the clean, assignable state with no further action
    // here. A no-op if it hasn't actually expired.
    if (widget.assignment.isStalePending) {
      ref
          .read(rescueCaseRepositoryProvider)
          .reconcileStaleOffer(
        caseId: widget.caseId,
        assignmentId: widget.assignment.id,
      );
    }
  }

  String _pendingDuration() {
    final offeredAt = widget.assignment.offeredAt;
    if (offeredAt == null) return '';
    final elapsed = DateTime.now().difference(offeredAt);
    final pending = elapsed.inMinutes < 1 ? 'Pending for ${elapsed.inSeconds}s' : 'Pending for ${elapsed.inMinutes}m';
    // The wait depends on urgency (transportOfferTtlFor), so show the
    // offer's own deadline rather than assume one.
    final expiry = widget.assignment.expiryLabel();
    return expiry.isEmpty ? pending : '$pending · $expiry';
  }

  Future<void> _cancelOffer() async {
    final confirmed = await showConfirmActionDialog(context, title: 'Cancel this offer?', message: 'The pending offer to ${widget.assignment.riderName} will be cancelled, and you can select another transporter.', confirmLabel: 'Cancel Offer', cancelLabel: 'Keep Waiting', destructive: true);
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .cancelAssignment(
        caseId: widget.caseId,
        assignmentId: widget.assignment.id,
        reason: 'Cancelled by organization while waiting',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Offer cancelled. You may select another transporter.'),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not cancel this offer: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicName = widget.caseData['vetClinicName'] as String?;
    final duration = _pendingDuration();
    return Container(
      color: AppColors.slaterspwn,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 10),
            Text(
              'Awaiting transporter response',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Offered to: ${widget.assignment.riderName}',
              style: GoogleFonts.zain(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            if (duration.isNotEmpty)
              Text(
                duration,
                style: GoogleFonts.zain(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              clinicName != null && clinicName.isNotEmpty
                  ? 'Selected clinic: $clinicName'
                  : '',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _cancelling ? null : _cancelOffer,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: _cancelling
                  ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Text(
                'Cancel Offer',
                style: GoogleFonts.zain(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline replacement for what used to be a separate "Rider Rejected"
/// page — same Track Case page/route, swapped in where the map normally
/// renders. The rescue case itself was never marked rejected, only this
/// transporter's offer was, so the case is already assignable again;
/// "Choose Another Transporter" just returns to Rescue Details, where
/// "Assign Transporter" is available once more.
class _DeclinedAssignmentBanner extends StatelessWidget {
  final TransportAssignment assignment;
  final VoidCallback onChooseAnother;
  const _DeclinedAssignmentBanner({
    required this.assignment,
    required this.onChooseAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: AppColors.slaterspwn,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cancel_outlined,
              size: 28,
              color: AppColors.error,
            ),
            const SizedBox(height: 8),
            Text(
              '${assignment.riderName} declined the assignment.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              assignment.rejectionReason ?? 'No reason given',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onChooseAnother,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                'Choose Another Transporter',
                style: GoogleFonts.zain(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The admin's live view of a transit: the same route line and color as
/// the transporter's map (TransitRouteStyle), the trail already driven,
/// and the transporter's marker gliding between GPS reports instead of
/// jumping, with the route ahead trimmed at the marker so it shrinks as
/// they drive — like a transit app. The road route is re-requested only
/// when the destination changes, the transporter has moved 200 m since the
/// last request, or they leave the drawn line.
class _LiveTrackingMap extends StatefulWidget {
  final String caseId;
  final LatLng? rider;
  final LatLng destination;
  final String destinationLabel;
  final LatLng? origin;
  final String originLabel;
  final DirectionsRepository directions;

  const _LiveTrackingMap({
    required this.caseId,
    required this.rider,
    required this.destination,
    required this.destinationLabel,
    required this.origin,
    required this.originLabel,
    required this.directions,
  });

  @override
  State<_LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<_LiveTrackingMap> with SingleTickerProviderStateMixin {
  late final SmoothPositionAnimator _rider;
  GoogleMapController? _map;
  RouteResult? _route;
  LatLng? _routeFrom;
  LatLng? _routeTo;
  bool _fetching = false;
  bool _fitted = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _trailSub;
  List<LatLng> _trail = const [];
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _rider = SmoothPositionAnimator(vsync: this, onTick: _onTick);
    if (widget.rider != null) _rider.moveTo(widget.rider!);
    _trailSub = FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('tracking')
        .orderBy('timestamp')
        .limitToLast(100)
        .snapshots()
        .listen((snap) {
      final points = <LatLng>[];
      for (final d in snap.docs) {
        final lat = d.data()['lat'], lng = d.data()['lng'];
        if (lat is num && lng is num) points.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
      if (mounted) setState(() => _trail = points);
    }, onError: (_) {});
    _maybeFetchRoute();
  }

  @override
  void didUpdateWidget(covariant _LiveTrackingMap old) {
    super.didUpdateWidget(old);
    final rider = widget.rider;
    if (rider != null && rider != old.rider) _rider.moveTo(rider);
    if (widget.destination != old.destination) _fitted = false;
    _maybeFetchRoute();
  }

  @override
  void dispose() {
    _trailSub?.cancel();
    _rider.dispose();
    super.dispose();
  }

  // ~30 repaints a second while the marker glides.
  void _onTick() {
    final now = DateTime.now();
    if (now.difference(_lastPaint).inMilliseconds < 33) return;
    _lastPaint = now;
    if (mounted) setState(() {});
  }

  double _meters(LatLng a, LatLng b) => Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  void _maybeFetchRoute() {
    final rider = widget.rider;
    if (rider == null || _fetching) return;
    final dest = widget.destination;
    final destChanged = _routeTo != dest;
    final movedFar = _routeFrom == null || _meters(_routeFrom!, rider) > TransitRouteStyle.refetchAfterMovingMeters;
    final route = _route;
    final offRoute = route != null &&
        route.isRoadFollowing &&
        remainingRoute(route.polylinePoints, rider).offRouteMeters > TransitRouteStyle.offRouteMeters;
    if (!destChanged && !movedFar && !offRoute) return;
    _fetching = true;
    _routeFrom = rider;
    _routeTo = dest;
    widget.directions.fetchRoute(origin: rider, destination: dest).then((r) {
      if (!mounted) return;
      setState(() => _route = r);
      _fitCamera();
    }).catchError((Object e) {
      debugPrint('Admin tracking route failed: $e');
    }).whenComplete(() => _fetching = false);
  }

  /// Fits the route, the transporter and the destination once per
  /// destination, so later updates never fight the admin's own panning.
  void _fitCamera() {
    final map = _map;
    if (_fitted || map == null) return;
    final points = <LatLng>[
      widget.destination,
      ?_rider.position,
      ...?_route?.polylinePoints,
    ];
    if (points.length < 2) return;
    _fitted = true;
    double minLat = points.first.latitude, maxLat = minLat, minLng = points.first.longitude, maxLng = minLng;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    if (maxLat - minLat < 0.0005 && maxLng - minLng < 0.0005) {
      map.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
      return;
    }
    map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        48,
      ),
    );
  }

  double _pathMeters(List<LatLng> points) {
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _meters(points[i], points[i + 1]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final riderPos = _rider.position;
    final route = _route;
    final isRoadFollowing = route?.isRoadFollowing ?? false;

    List<LatLng>? ahead;
    if (route != null && route.polylinePoints.length >= 2) {
      ahead = riderPos == null ? route.polylinePoints : remainingRoute(route.polylinePoints, riderPos).points;
    } else if (riderPos != null) {
      ahead = [riderPos, widget.destination];
    }

    // The trail ends at the gliding marker, not at the newest report it
    // hasn't reached yet.
    final trail = (riderPos != null && _trail.isNotEmpty) ? [..._trail.take(_trail.length - 1), riderPos] : _trail;

    final remainingMeters = ahead == null ? null : _pathMeters(ahead);
    String? eta;
    final total = route == null ? null : _pathMeters(route.polylinePoints);
    if (route?.duration != null && remainingMeters != null && total != null && total > 0) {
      final minutes = (route!.duration!.inSeconds * (remainingMeters / total) / 60).ceil();
      eta = minutes <= 1 ? '~1 min' : '~$minutes min';
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: widget.destinationLabel),
      ),
      if (widget.origin != null)
        Marker(
          markerId: const MarkerId('rescue_case'),
          position: widget.origin!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(title: widget.originLabel),
        ),
      if (riderPos != null)
        Marker(
          markerId: const MarkerId('rider'),
          position: riderPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 1),
          zIndexInt: 2,
          infoWindow: const InfoWindow(title: 'Transporter'),
        ),
    };

    final polylines = <Polyline>{
      if (trail.length >= 2) TransitRouteStyle.trail(trail),
      if (ahead != null && ahead.length >= 2) TransitRouteStyle.route(ahead, roadFollowing: isRoadFollowing),
    };

    return SizedBox(
      height: 180,
      child: Stack(
        children: [
          GoogleMap(
            gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
            initialCameraPosition: CameraPosition(target: riderPos ?? widget.destination, zoom: 14),
            onMapCreated: (ctrl) {
              _map = ctrl;
              _fitCamera();
            },
            markers: markers,
            polylines: polylines,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 10,
            bottom: 10,
            right: 10,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  remainingMeters == null || riderPos == null
                      ? 'Heading to ${widget.destinationLabel} · transporter location not shared yet'
                      : '${(remainingMeters / 1000).toStringAsFixed(1)} km${eta == null ? '' : ' · $eta'} to ${widget.destinationLabel}'
                          '${route != null && !isRoadFollowing ? ' (straight-line estimate)' : ''}',
                  style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
          if (route != null && !isRoadFollowing)
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Road route unavailable. Showing approximate path.',
                        style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
