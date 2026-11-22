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
import 'package:respawnd1/core/utils/rescue_risk.dart';
import 'package:respawnd1/core/widgets/rescue_risk_banner.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_flow.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animals_card.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/features/admin/rescue/widgets/community_reports_section.dart';
import 'package:respawnd1/features/rescue/widgets/case_chat.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transporter_details_card.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/repos/rescue_case/case_message_sender.dart';
import 'package:respawnd1/core/utils/photo_marker.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

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
  final _messageController = TextEditingController();

  /// How much of the screen the details sheet covers (0-1). The map's
  /// height follows it, so sliding the sheet down shows more map instead
  /// of an empty band (the map used to stop at a fixed 56%).
  double _sheetExtent = 0.48;

  /// The rescued animal's photo as its map pin (null until built, or when
  /// the case has no photo).
  BitmapDescriptor? _animalPin;
  String? _animalPinUrl;

  void _loadAnimalPin(String? url) {
    if (url == null || url.isEmpty || url == _animalPinUrl) return;
    _animalPinUrl = url;
    PhotoMarkers.forUrl(url, ring: AppColors.yellowrspwn).then((pin) {
      if (mounted && pin != null && _animalPinUrl == url) setState(() => _animalPin = pin);
    });
  }
  bool _closing = false;

  /// The last road route (or straight-line fallback) to the current
  /// destination — feeds the ETA headline and the transporter card.
  RouteResult? _lastRoute;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
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


  /// Guards against double-tapping "Proceed to Treatment" and drives the
  /// button's loading state while the write is in flight and being
  /// verified.
  bool _isProceedingToTreatment = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final sender = await CaseMessageSender.staffFields();
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('messages')
        .add({
      ...sender,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  Future<void> _proceedToTreatment(Map<String, dynamic> data) async {
    if (_isProceedingToTreatment) return; // guard against double-tap
    setState(() => _isProceedingToTreatment = true);

    final expectedStatus =
        RescueStatus.treatment.firestoreValue; // 'in_treatment'
    // The app-wide messenger, still there after this page is replaced.
    final messenger = ScaffoldMessenger.of(context);
    final assignment = ref
        .read(currentAssignmentProvider(widget.caseId))
        .asData
        ?.value;
    final repo = ref.read(rescueCaseRepositoryProvider);

    try {
      // Firestore applies the write on the phone at once; the future only
      // completes when the server confirms it, which on a slow connection
      // left this button spinning while the case had already moved (the
      // Treatment tab showed it). Wait briefly so an outright rejection
      // (e.g. permissions) still keeps the admin here, then move on and
      // report a late failure instead of blocking on it.
      final write = RescueCaseStore(FirebaseFirestore.instance).recordAction(
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
      var confirmed = false;
      try {
        await write.timeout(const Duration(seconds: 2));
        confirmed = true;
      } on TimeoutException {
        write.catchError((Object e) {
          messenger.showSnackBar(
            appSnackBar('Could not move this case to treatment: $e', kind: AppMessageKind.error),
          );
        });
      }

      // Frees the accepted transporter (demo or real) back to "Available"
      // — activeAssignmentsByRiderProvider derives each transporter's chip
      // from their single most-recent assignment, so marking this one
      // 'completed' is what clears their Busy state elsewhere. Sent after
      // the treatment write (Firestore keeps the order) and not awaited.
      if (assignment != null &&
          assignment.status == TransportAssignmentStatus.accepted) {
        final complete = repo.completeAssignment(caseId: widget.caseId, assignmentId: assignment.id);
        (confirmed ? complete : write.then((_) => complete)).catchError((Object e) {
          debugPrint('Could not complete assignment ${assignment.id}: $e');
        });
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
      return SizedBox.expand(
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
                    icon: _animalPin ?? BitmapDescriptor.defaultMarkerWithHue(
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
      // Before pickup the destination is the animal itself.
      destinationIcon: !isPostPickupDestination ? _animalPin : null,
      origin: showSeparateCaseMarker ? caseLocation : null,
      originLabel: _originMarkerLabel,
      originIcon: _animalPin,
      directions: ref.read(directionsRepositoryProvider),
      onRoute: (r) {
        if (mounted) setState(() => _lastRoute = r);
      },
    );
  }

  String _etaLabel(Duration d) {
    final mins = (d.inSeconds / 60).ceil();
    if (mins < 60) {
      // A range, like a delivery app: traffic and stops make an exact minute
      // misleading.
      final low = mins <= 2 ? 1 : (mins * 0.85).floor();
      final high = (mins * 1.25).ceil().clamp(low + 1, 999);
      return '$low–$high mins';
    }
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// Everything under the map: status + ETA, transporter, clinic, animal
  /// summary, banners, a collapsible timeline, community reports and
  /// messages — one list, no tabs.
  List<Widget> _sheetChildren(
    BuildContext context,
    RescueCase c,
    Map<String, dynamic> data,
    TransportAssignment? assignment,
    List<Map<String, dynamic>> statusHistory,
    Widget banner,
    bool isIntakeMode,
  ) {
    final accepted = assignment != null &&
        (assignment.status == TransportAssignmentStatus.accepted ||
            assignment.status == TransportAssignmentStatus.completed);
    final route = _lastRoute;
    const pad = EdgeInsets.symmetric(horizontal: 16);

    return [
      // The outcome banner (blue on the way, green arrived) heads the
      // sheet, with the ETA and distance; it replaced a separate status
      // card that said the same thing.
      Padding(padding: pad, child: banner),
      const SizedBox(height: 10),
      if (accepted) ...[
        Padding(
          padding: pad,
          child: TransporterDetailsCard(
            assignment: assignment,
            distanceKm: route?.distanceKm,
            etaDuration: route?.duration,
          ),
        ),
        const SizedBox(height: 10),
      ],
      if ((c.vetClinicName ?? '').isNotEmpty) ...[
        Padding(padding: pad, child: _ClinicCard(rescueCase: c, isPickup: isIntakeMode)),
        const SizedBox(height: 10),
      ],
      Padding(
        padding: pad,
        child: _AnimalSummaryCard(
          rescueCase: c,
          caseData: data,
          // An admission or adoption return has no report to open.
          showFullDetailsLink: !isIntakeMode && !_isRecordCase(data),
        ),
      ),
      const SizedBox(height: 10),
      // Bite/escape risks come from a community report; an animal moved
      // from its record has none.
      if (!_isRecordCase(data))
        Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RescueRiskBanner(
                highRiskAnimals: highRiskAnimalsIn(
                  animals: data['animals'] as List?,
                  legacyBiteRisk: data['biteRisk'] as String?,
                  legacyEscapeRisk: data['escapeRisk'] as String?,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      _AdminTrackingTab(
        statusHistory: statusHistory,
        caseId: widget.caseId,
        messageController: _messageController,
        onSend: _sendMessage,
        isIntakeMode: isIntakeMode,
        hideCommunityContent: data['sourceType'] == 'animalRecordAdmission',
      ),
    ];
  }

  /// A case opened from an existing animal record (Medical > Admit, or an
  /// adoption return): no community report behind it, and the animal's
  /// name and photo come from its record.
  static bool _isRecordCase(Map<String, dynamic> data) =>
      ((data['sourceAnimalRecordId'] as String?) ?? '').isNotEmpty &&
      (data['sourceType'] == 'animalRecordAdmission' || data['sourceType'] == 'adoptionReturn');

  /// ETA and distance lines for the outcome banner while the animal moves.
  List<(String, String)> _etaFacts(Map<String, dynamic> data) {
    final route = _lastRoute;
    final destination = _destinationFrom(data);
    final eta = route?.duration;
    return [
      if (eta != null) ('ETA', _etaLabel(eta)),
      (
        'To',
        route == null
            ? destination.label
            : '${destination.label} · ${route.distanceKm.toStringAsFixed(1)} km'
                '${route.isRoadFollowing ? '' : ' (straight line)'}',
      ),
    ];
  }

  String _statusHeadline(Map<String, dynamic> data, bool isIntakeMode) {
    if (isIntakeMode) {
      return data['intakeReceivedAt'] != null ? 'Animal received at the shelter' : 'On the way to the shelter';
    }
    if (_kArrivedAtClinicStatuses.contains(data['status'])) return 'Transporter is at the clinic';
    if (_kPostPickupStatuses.contains(data['status'])) return 'Animal picked up · heading to the clinic';
    return 'Transporter heading to the rescue location';
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

        final c = RescueCase.fromMap(widget.caseId, data);
        // The animal's own record (name, photo) when the case came from one.
        final record = _isRecordCase(data)
            ? ref.watch(animalRecordProvider(data['sourceAnimalRecordId'] as String)).asData?.value
            : null;
        final recordPhoto = record != null && record.photoUrls.isNotEmpty ? record.photoUrls.first : null;
        _loadAnimalPin(recordPhoto ?? (c.photoUrls.isNotEmpty ? c.photoUrls.first : null));
        final isIntakeMode = widget.mode == TrackingMode.intakeTransfer;
        final reachedClinic = _kArrivedAtClinicStatuses.contains(data['status']);
        final hasReceivedIntake = data['intakeReceivedAt'] != null;
        // Change Clinic and Close Case used to sit in the app bar's menu;
        // they're in the app bar's menu (top right).
        // Nothing left to change once the animal is at the shelter.
        final overflow = isIntakeMode && hasReceivedIntake
            ? const <CaseAction>[]
            : <CaseAction>[
          // Testing without GPS, before the transporter reaches the clinic.
          if (kDebugMode && !isIntakeMode && !reachedClinic)
            CaseAction('Fast-forward to Clinic (Test)', _fastForwardToClinic, icon: Icons.fast_forward),
          if (data['vetClinicName'] != null)
            CaseAction('Change Clinic', _closing ? null : () => _changeClinic(c), icon: Icons.local_hospital_outlined),
          // Controlled Close Case (spec §3) — full reason picker, no
          // preset; an animal-moved location update only ever comes from an
          // approved Community Report.
          CaseAction('Close Case', _closing ? null : () => _closeCase(c), icon: Icons.block, destructive: true),
        ];
        // Intake transport confirms arrival at the shelter (that doesn't move
        // the case past Intake); a rescue pickup proceeds to treatment only
        // once the transporter has actually reached the clinic.
        final CaseAction? primary = isIntakeMode
            ? (hasReceivedIntake ? null : CaseAction('Confirm Animal Received', () => _confirmAnimalReceived(assignment)))
            : CaseAction('Proceed to Treatment',
                reachedClinic && !_isProceedingToTreatment ? () => _proceedToTreatment(data) : null);
        final banner = isIntakeMode
            ? (hasReceivedIntake
                ? const CaseOutcomeBanner(tone: CaseBannerTone.success, title: 'Animal received at the shelter.')
                : CaseOutcomeBanner(
                    tone: CaseBannerTone.info,
                    icon: Icons.local_shipping_outlined,
                    title: 'On the way to the shelter',
                    message: 'Confirm when the animal arrives; quarantine and the animal record continue on Intake Details.',
                    facts: _etaFacts(data),
                  ))
            : reachedClinic
                ? const CaseOutcomeBanner(
                    tone: CaseBannerTone.success,
                    icon: Icons.local_hospital_outlined,
                    title: 'Transporter is at the clinic',
                    message: 'Proceed to Treatment to start the treatment log.',
                  )
                : CaseOutcomeBanner(
                    tone: CaseBannerTone.info,
                    icon: Icons.local_shipping_outlined,
                    title: _statusHeadline(data, false),
                    message: 'Proceed to Treatment unlocks on arrival.',
                    facts: _etaFacts(data),
                  );

        return Scaffold(
          backgroundColor: AppColors.background,
          bottomNavigationBar: CaseActionBar.maybe(
            primary: primary,
            busy: _isProceedingToTreatment,
          ),
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
            actions: [CaseOverflowMenu(actions: overflow, busy: _isProceedingToTreatment)],
          ),
          // Map behind a draggable sheet (like a delivery tracker): the map
          // takes about half the screen and the details slide up over it.
          // A pending/declined offer replaces the map with its banner, so
          // that edge case keeps a plain scrolling layout.
          body: (assignment != null &&
                  (assignment.status == TransportAssignmentStatus.pending ||
                      assignment.status == TransportAssignmentStatus.rejected))
              ? ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _buildTrackingMap(data, assignment),
                    const SizedBox(height: 12),
                    ..._sheetChildren(context, c, data, assignment, statusHistory, banner, isIntakeMode),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return NotificationListener<DraggableScrollableNotification>(
                    onNotification: (n) {
                      // Rebuild only on a visible change (the sheet sends
                      // one notification per frame while dragging).
                      if ((n.extent - _sheetExtent).abs() > 0.01) setState(() => _sheetExtent = n.extent);
                      return false;
                    },
                    child: Stack(
                    children: [
                      // Down to where the sheet starts (plus the sheet's
                      // rounded corner), following the sheet as it moves.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: constraints.maxHeight * (1 - _sheetExtent) + 20,
                        child: _buildTrackingMap(data, assignment),
                      ),
                      DraggableScrollableSheet(
                        initialChildSize: 0.48,
                        minChildSize: 0.22,
                        maxChildSize: 0.94,
                        snap: true,
                        snapSizes: const [0.48],
                        builder: (context, scrollController) => Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              Center(
                                child: Container(
                                  margin: const EdgeInsets.only(top: 8, bottom: 10),
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: AppColors.slaterspwn,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              ..._sheetChildren(context, c, data, assignment, statusHistory, banner, isIntakeMode),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  );
                  },
                ),
        );
      },
    );
  }
}

class _AdminTrackingTab extends StatefulWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final bool isIntakeMode;

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
    this.hideCommunityContent = false,
    required this.isIntakeMode,
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

  /// The timeline shows the latest two updates until expanded.
  bool _timelineExpanded = false;
  static const _timelinePreview = 2;

  Widget _buildTimelineItem(List<Map<String, dynamic>> statusHistory, int index) {
    final item = statusHistory[index];
    // Newest first: the top entry is the current state.
    final isLast = index == 0;
    final ts = item['timestamp'] as Timestamp?;
    final timeStr = ts != null ? formatTime(ts.toDate()) : '';
    final dateStr = ts != null ? formatDate(ts.toDate()) : '';

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
              Container(width: 2, height: 28, color: AppColors.textPrimary),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CaseCard(
                title: 'Status timeline',
                child: statusHistory.isEmpty
                    ? Text('No updates yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
                    : Builder(builder: (context) {
                        final newestFirst = statusHistory.reversed.toList();
                        final shown = _timelineExpanded
                            ? newestFirst
                            : newestFirst.take(_timelinePreview).toList();
                        final hidden = newestFirst.length - shown.length;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < shown.length; i++) _buildTimelineItem(shown, i),
                            if (newestFirst.length > _timelinePreview)
                              TextButton.icon(
                                onPressed: () => setState(() => _timelineExpanded = !_timelineExpanded),
                                icon: Icon(_timelineExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                                label: Text(
                                  _timelineExpanded ? 'Show less' : 'Show $hidden earlier update${hidden == 1 ? '' : 's'}',
                                  style: GoogleFonts.zain(fontWeight: FontWeight.w700),
                                ),
                                style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
                              ),
                          ],
                        );
                      }),
              ),
              const SizedBox(height: 8),
              if (!widget.isIntakeMode && !widget.hideCommunityContent)
                CollapsibleSection(
                  title: 'Community reports',
                  icon: Icons.campaign_outlined,
                  summary: 'Sightings and updates from the public',
                  child: CommunityReportsSection(caseId: widget.caseId),
                ),
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
        // Messages: the same chat as Rescue Details and the reporter's
        // Track Case (CaseChat). Collapsed by default so the timeline above
        // stays readable.
        InkWell(
          onTap: () => setState(() => _messagesExpanded = !_messagesExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Messages',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Icon(_messagesExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (_messagesExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: CaseChat(caseId: widget.caseId, staff: true),
          ),

      ],
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


/// The clinic the animal is going to (or, on intake, collected from): name,
/// address, and quick Call / Directions.
class _ClinicCard extends StatelessWidget {
  final RescueCase rescueCase;
  final bool isPickup;
  const _ClinicCard({required this.rescueCase, required this.isPickup});

  Future<void> _call(BuildContext context) async {
    final phone = rescueCase.vetClinicPhone?.trim();
    if (phone == null || phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  }

  Future<void> _directions() async {
    final lat = rescueCase.vetClinicLat;
    final lng = rescueCase.vetClinicLng;
    final uri = (lat != null && lng != null)
        ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(rescueCase.vetClinicName ?? '')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = (rescueCase.vetClinicPhone ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.pinkrspwn, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.local_hospital, color: AppColors.textPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPickup ? 'Pickup clinic' : 'Clinic',
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                Text(rescueCase.vetClinicName ?? '',
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if ((rescueCase.vetClinicAddress ?? '').isNotEmpty)
                  Text(rescueCase.vetClinicAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (hasPhone)
            IconButton(
              tooltip: 'Call clinic',
              icon: const Icon(Icons.call_outlined, color: AppColors.textPrimary),
              onPressed: () => _call(context),
            ),
          IconButton(
            tooltip: 'Directions',
            icon: const Icon(Icons.directions_outlined, color: AppColors.textPrimary),
            onPressed: _directions,
          ),
        ],
      ),
    );
  }
}

/// Short animal summary — photo, species and the key facts — that expands
/// to the full basics and the bold Health / Behavior sections, with a link
/// to the full case.
class _AnimalSummaryCard extends ConsumerStatefulWidget {
  final RescueCase rescueCase;
  final Map<String, dynamic> caseData;
  final bool showFullDetailsLink;
  const _AnimalSummaryCard({required this.rescueCase, required this.caseData, required this.showFullDetailsLink});

  @override
  ConsumerState<_AnimalSummaryCard> createState() => _AnimalSummaryCardState();
}

class _AnimalSummaryCardState extends ConsumerState<_AnimalSummaryCard> {
  bool _expanded = false;

  String _facts() {
    final c = widget.rescueCase;
    final animals = c.animals;
    Map? first = animals.isNotEmpty ? animals.first as Map? : null;
    String? field(String k) {
      final v = first != null ? first[k] : c.raw[k];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
    }

    final parts = [field('sex'), field('size'), field('breed'), field('colorMarkings')].whereType<String>().toList();
    if (animals.length > 1) parts.insert(0, '${animals.length} animals');
    return parts.isEmpty ? 'Tap for details' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    // A case opened from an animal record shows that record (its name,
    // photo and details), not the case's generic species label.
    final recordId = _AdminTrackCasePageState._isRecordCase(widget.caseData)
        ? widget.caseData['sourceAnimalRecordId'] as String
        : null;
    final record = recordId == null ? null : ref.watch(animalRecordProvider(recordId)).asData?.value;
    final photo = record != null && record.photoUrls.isNotEmpty
        ? record.photoUrls.first
        : (c.photoUrls.isNotEmpty ? c.photoUrls.first : null);
    final title = record == null
        ? c.speciesSummary
        : (record.name.trim().isNotEmpty ? record.name.trim() : record.species);
    final facts = record == null
        ? _facts()
        : [record.species, record.sex, record.breed].where((v) => v.trim().isNotEmpty).join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: photo == null
                          ? Container(color: AppColors.tearspwn, child: const Icon(Icons.pets, color: AppColors.textPrimary))
                          : Image.network(photo, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  Container(color: AppColors.tearspwn, child: const Icon(Icons.pets))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                        Text(facts,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (recordId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: CaseAnimalsSection(currentCase: c),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: record == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnimalRecordDetailPage(animalId: record.id, data: record.raw),
                            ),
                          ),
                  child: Text('Animal record →',
                      style: GoogleFonts.zain(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
              ),
            if (widget.showFullDetailsLink)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RescueDetailPage(caseId: c.id, data: widget.caseData),
                    ),
                  ),
                  child: Text('Full case details →',
                      style: GoogleFonts.zain(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
              ),
          ],
        ],
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
  final BitmapDescriptor? destinationIcon;
  final BitmapDescriptor? originIcon;
  final DirectionsRepository directions;
  /// What is left to drive (route ahead, distance, ETA), for the page's
  /// ETA headline and transporter card. Called when a route arrives and
  /// on each new GPS report, not on every animation frame.
  final ValueChanged<RouteResult> onRoute;

  const _LiveTrackingMap({
    required this.caseId,
    required this.rider,
    required this.destination,
    required this.destinationLabel,
    required this.origin,
    required this.originLabel,
    this.destinationIcon,
    this.originIcon,
    required this.directions,
    required this.onRoute,
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
    if (rider != null && rider != old.rider) {
      _rider.moveTo(rider);
      _reportProgress();
    }
    if (widget.destination != old.destination) _fitted = false;
    _maybeFetchRoute();
  }

  /// Tells the page how much is left from the latest reported position.
  void _reportProgress() {
    final route = _route;
    final rider = widget.rider;
    if (route == null) return;
    if (rider == null || route.polylinePoints.length < 2) {
      widget.onRoute(route);
      return;
    }
    final ahead = remainingRoute(route.polylinePoints, rider).points;
    final total = _pathMeters(route.polylinePoints);
    final left = _pathMeters(ahead);
    final share = total > 0 ? (left / total).clamp(0.0, 1.0) : 1.0;
    widget.onRoute(RouteResult(
      polylinePoints: ahead,
      distanceKm: route.isRoadFollowing ? route.distanceKm * share : left / 1000,
      duration: route.duration == null ? null : Duration(seconds: (route.duration!.inSeconds * share).round()),
      isRoadFollowing: route.isRoadFollowing,
    ));
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
      _reportProgress();
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
        icon: widget.destinationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: widget.destinationLabel),
      ),
      if (widget.origin != null)
        Marker(
          markerId: const MarkerId('rescue_case'),
          position: widget.origin!,
          icon: widget.originIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
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
      if (ahead != null && ahead.length >= 2)
        ...(route != null && isRoadFollowing
            ? TransitRouteStyle.route(ahead)
            : TransitRouteStyle.straightLine(ahead)),
    };

    return SizedBox.expand(
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
            padding: const EdgeInsets.only(bottom: 40),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 10,
            top: (route != null && !isRoadFollowing) ? 52 : 10,
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
